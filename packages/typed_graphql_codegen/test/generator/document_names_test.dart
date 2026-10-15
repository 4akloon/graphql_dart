import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
interface Node { id: ID! }
type Query implements Node {
  id: ID!
  hello: String
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
''');

void main() {
  List<String> check(
    List<ProjectFile> documents, {
    String config = 'schema: schema.graphql\n',
  }) {
    final parsed = CodegenConfig.parse(config, path: 'typed_graphql.yaml');
    if (parsed is! ConfigSuccess) fail('expected success, got $parsed');
    final diagnostics = ClientGenerator(
      parsed.config,
    ).check(schema: _schema, documents: documents);
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
fragment NodeCard on Node { id }
''');

    test('a fragment on an abstract type is a GQL504 at the spread', () {
      expect(check(const [document]), [
        "lib/a.graphql:1:23: error GQL504: The subscription 'OnNode' spreads "
            "the fragment 'NodeCard' on the abstract type 'Node' at its root, "
            "where '__typename' cannot be selected.",
      ]);
    });

    test('an inline fragment on an abstract type is a GQL504 too', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'subscription OnNode { ... on Node { id } }',
          ),
        ]).single,
        contains("has an inline fragment on the abstract type 'Node'"),
      );
    });

    test('the same spread in a query is fine', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', '''
query Q { ...NodeCard }
fragment NodeCard on Node { id }
'''),
        ]),
        isEmpty,
      );
    });
  });
}
