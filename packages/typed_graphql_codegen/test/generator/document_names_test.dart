import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
interface Node { id: ID! }
type Query implements Node {
  id: ID!
  hello: String
  node: Node
  user(a: ID, b: ID): User
}
type Subscription implements Node {
  id: ID!
  changed: User
}
type User {
  id: ID!
  name: String
}
type Unknown implements Node {
  id: ID!
}
''');

void main() {
  List<String> check(
    List<ProjectFile> documents, {
    String config = 'schema: schema.graphql\n',
    ProjectFile schema = _schema,
  }) {
    final parsed = CodegenConfig.parse(config, path: 'typed_graphql.yaml');
    if (parsed is! ConfigSuccess) fail('expected success, got $parsed');
    final diagnostics = ClientGenerator(
      parsed.config,
    ).check(schema: schema, documents: documents);
    return [
      for (final diagnostic in diagnostics)
        [
          '$diagnostic',
          for (final place in diagnostic.related) 'also $place',
        ].join(' | '),
    ];
  }

  group('class names', () {
    test('an operation class and a fragment class with one name', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', 'query A { hello }'),
          ProjectFile('lib/b.graphql', 'fragment AQuery on Query { hello }'),
        ]),
        [
          "lib/b.graphql:1:10: error GQL507: The generated name 'AQuery' is "
              "declared twice: by the operation 'A' and by the fragment "
              "'AQuery'. | also lib/a.graphql:1:7",
        ],
      );
    });

    test('a nested class and a fragment class with one name', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', 'query Get { data: user { id } }'),
          ProjectFile('lib/b.graphql', 'fragment GetDataData on User { id }'),
        ]),
        [
          'lib/b.graphql:1:10: error GQL507: The generated name '
              "'GetDataData' is declared twice: by the operation 'Get' and by "
              "the fragment 'GetDataData'. | also lib/a.graphql:1:13",
        ],
      );
    });

    test('a variables class and a fragment class with one name', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            r'query A($a: ID) { user(a: $a) { id } }',
          ),
          ProjectFile('lib/b.graphql', 'fragment AVariables on User { id }'),
        ]).single,
        startsWith('lib/b.graphql:1:10: error GQL507: The generated name '),
      );
    });
  });

  group('members', () {
    test('two fields of one data class with one Dart name', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'query Get { user { user_name: name userName: name } }',
          ),
        ]),
        [
          'lib/a.graphql:1:36: error GQL507: The generated member '
              "'userName' of 'GetDataUser' is declared twice: by the field "
              "'user_name' and by the field 'userName'. | also "
              'lib/a.graphql:1:20',
        ],
      );
    });

    test('two fragments of one holder with one accessor, and as classes', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'query Get { user { ...UserCard ...userCard } }',
          ),
          ProjectFile(
            'lib/b.graphql',
            'fragment UserCard on User { id }\n'
                'fragment userCard on User { id }',
          ),
        ]),
        [
          'lib/a.graphql:1:32: error GQL507: The generated member '
              "'userCard' of 'GetDataUserFragments' is declared twice: by the "
              "fragment 'UserCard' and by the fragment 'userCard'. | also "
              'lib/a.graphql:1:20',
          "lib/b.graphql:2:10: error GQL507: The generated name 'UserCard' "
              "is declared twice: by the fragment 'UserCard' and by the "
              "fragment 'userCard'. | also lib/b.graphql:1:10",
        ],
      );
    });

    test('two variables with one Dart name', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            r'query Get($a_b: ID, $aB: ID) { user(a: $a_b, b: $aB) { id } }',
          ),
        ]),
        [
          "lib/a.graphql:1:21: error GQL507: The generated member 'aB' of "
              "'GetVariables' is declared twice: by the variable 'a_b' and by "
              "the variable 'aB'. | also lib/a.graphql:1:11",
        ],
      );
    });
  });

  group('reserved names', () {
    test('a fragment named List hides the Dart type', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', 'fragment List on User { id }'),
        ]),
        [
          "lib/a.graphql:1:10: error GQL508: The generated name 'List' would "
              "hide the Dart type 'List' the generated code uses.",
        ],
      );
    });

    test('an operation named List has no class of that name', () {
      expect(
        check(const [ProjectFile('lib/a.graphql', 'query List { hello }')]),
        isEmpty,
      );
    });
  });

  group('variants', () {
    test('a type named Unknown collides with the unknown class', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'query Q { node { id ... on Unknown { id } } }',
          ),
        ]),
        [
          'lib/a.graphql:1:11: error GQL507: The generated name '
              "'QDataNodeUnknown' is declared twice: by the class for the "
              "type 'Unknown' in the operation 'Q' and by the class for any "
              "other type in the operation 'Q'. | also lib/a.graphql:1:11",
        ],
      );
    });
  });

  group('limits', () {
    // Every alias reaches all the types that implement `Many`: a class per
    // type and alias from a few tokens.
    final schema = ProjectFile('schema.graphql', '''
interface Many { id: ID! }
interface Reached { id: ID! }
${[for (var i = 0; i < 1000; i++) 'type T$i implements Many & Reached { id: ID! }'].join('\n')}
type Query { many: Many }
''');
    final fields = [
      for (var index = 0; index < 11; index++)
        'f$index: many { ... on Reached { id } }',
    ].join(' ');

    test('an operation that needs too many classes is a GQL511', () {
      expect(
        check([
          ProjectFile('lib/a.graphql', 'query Q { $fields }'),
        ], schema: schema),
        [
          'lib/a.graphql:1:7: error GQL511: The code generator would declare '
              "more than 10000 classes for the operation 'Q'.",
        ],
      );
    });

    test('a fragment that needs too many classes is a GQL511', () {
      expect(
        check([
          ProjectFile('lib/a.graphql', 'fragment F on Query { $fields }'),
        ], schema: schema),
        [
          'lib/a.graphql:1:10: error GQL511: The code generator would declare '
              "more than 10000 classes for the fragment 'F'.",
        ],
      );
    });
  });

  group('files', () {
    test('a document library at the path of the schema types', () {
      expect(
        check(const [
          ProjectFile('lib/schema.graphql', 'query A { hello }'),
        ]),
        [
          'lib/schema.graphql:1:1: error GQL507: The generated file '
              "'lib/schema.graphql.dart' is written twice: by the schema "
              "types and by the document 'lib/schema.graphql'.",
        ],
      );
    });
  });

  group('the subscription root', () {
    const document = ProjectFile('lib/a.graphql', '''
subscription OnNode { ...NodeCard }
fragment NodeCard on Node { id ... on Query { hello } }
''');

    test('a sealed fragment is a GQL504 at the spread', () {
      expect(check(const [document]), [
        "lib/a.graphql:1:23: error GQL504: The subscription 'OnNode' spreads "
            "'...NodeCard' at its root, which reads the fragment 'NodeCard' on "
            "the abstract type 'Node'; the root would need '__typename', which "
            'a subscription cannot select.',
      ]);
    });

    test('a sealed fragment behind another spread names both', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', '''
subscription OnNode { ...Outer }
fragment Outer on Subscription { ...NodeCard }
fragment NodeCard on Node { id ... on Query { hello } }
'''),
        ]).single,
        "lib/a.graphql:1:23: error GQL504: The subscription 'OnNode' spreads "
        "'...Outer' at its root, which reads the fragment 'NodeCard' on the "
        "abstract type 'Node'; the root would need '__typename', which a "
        'subscription cannot select.',
      );
    });

    test('a fragment on an abstract type without narrowing is fine', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', '''
subscription OnNode { ...NodeCard }
fragment NodeCard on Node { id }
'''),
        ]),
        isEmpty,
      );
    });

    test('an inline fragment on an abstract type is fine', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'subscription OnNode { ... on Node { id } }',
          ),
        ]),
        isEmpty,
      );
    });

    test('an anonymous subscription is only a GQL503', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', '''
subscription { ...NodeCard }
fragment NodeCard on Node { id ... on Query { hello } }
'''),
        ]),
        [
          'lib/a.graphql:1:1: error GQL503: An operation needs a name: its '
              'classes are named after it.',
        ],
      );
    });

    test('the same spread in a query is fine', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', '''
query Q { ...NodeCard }
fragment NodeCard on Node { id ... on Query { hello } }
'''),
        ]),
        isEmpty,
      );
    });
  });
}
