import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/generator/rules/named_operations_rule.dart';
import 'package:typed_graphql_codegen/src/generator/rules/unsupported_directives_rule.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
type Query {
  hello: String
  user: User
}

type User {
  name: String
}

scalar Moment
''');

const _aFile = ProjectFile(
  'a.graphql',
  'query A {\n  user {\n    ...Name\n  }\n}\n',
);

const _bFile = ProjectFile(
  'b.graphql',
  'fragment Name on User {\n  name\n}\n',
);

void main() {
  CodegenConfig configOf(String text) {
    final result = CodegenConfig.parse(text, path: 'typed_graphql.yaml');
    if (result is! ConfigSuccess) fail('expected success, got $result');
    return result.config;
  }

  List<String> check(
    List<ProjectFile> documents, {
    ProjectFile schema = _schema,
    String config = 'schema: schema.graphql\n',
  }) {
    final diagnostics = ClientGenerator(
      configOf(config),
    ).check(schema: schema, documents: documents);
    return [
      for (final diagnostic in diagnostics)
        [
          '$diagnostic',
          for (final place in diagnostic.related) 'also $place',
        ].join(' | '),
    ];
  }

  group('documents', () {
    test('a valid project has no diagnostics', () {
      expect(check(const [_aFile, _bFile]), isEmpty);
    });

    test('an unknown field is reported in its file', () {
      expect(
        check(const [
          _aFile,
          ProjectFile('b.graphql', 'fragment Name on User {\n  nam\n}\n'),
        ]),
        [
          'b.graphql:2:3: error GQL205: Cannot query field "nam" on type '
              '"User". Did you mean "name"?',
        ],
      );
    });

    test('an unused fragment is not an error', () {
      expect(
        check(const [
          ProjectFile('a.graphql', 'query A { hello }\n'),
          _bFile,
        ]),
        isEmpty,
      );
    });

    test('an anonymous operation needs a name', () {
      expect(check(const [ProjectFile('a.graphql', '{ hello }\n')]), [
        'a.graphql:1:1: error GQL503: An operation needs a name: its classes '
            'are named after it.',
      ]);
    });

    test('two anonymous operations are each reported', () {
      expect(
        check(const [
          ProjectFile('a.graphql', '{ hello }\n'),
          ProjectFile('b.graphql', 'query { hello }\n'),
        ]),
        [
          'a.graphql:1:1: error GQL503: An operation needs a name: its '
              'classes are named after it.',
          'b.graphql:1:1: error GQL503: An operation needs a name: its '
              'classes are named after it.',
        ],
      );
    });

    test('@defer is not supported yet', () {
      expect(
        check(const [
          _aFile,
          ProjectFile(
            'b.graphql',
            'fragment Name on User {\n  ... @defer {\n    name\n  }\n}\n',
          ),
        ]),
        [
          'b.graphql:2:7: error GQL504: The code generator does not support '
              "'@defer' yet.",
        ],
      );
    });

    test('@stream is not supported yet', () {
      final schema = ProjectFile(
        'schema.graphql',
        '${_schema.text}type Other { names: [String] }\n'
            'extend type Query { other: Other }\n',
      );
      expect(
        check(const [
          ProjectFile(
            'a.graphql',
            'query A {\n  other {\n    names @stream\n  }\n}\n',
          ),
        ], schema: schema),
        [
          'a.graphql:3:11: error GQL504: The code generator does not support '
              "'@stream' yet.",
        ],
      );
    });

    test('an operation name used in two files is reported once, relating the other file', () {
      expect(
        check(const [
          ProjectFile('a.graphql', 'query A { hello }\n'),
          ProjectFile('b.graphql', 'query A { user { name } }\n'),
        ]),
        [
          'a.graphql:1:7: error GQL202: There can be only one operation '
              'named "A". | also b.graphql:1:7',
        ],
      );
    });

    test('a fragment defined in one file is spread in another', () {
      expect(check(const [_bFile, _aFile]), isEmpty);
    });
  });

  group('scalar mappings', () {
    const mappings = '''
schema: schema.graphql
scalars:
  Moment:
    type: DateTime
    codec: package:a/a.dart#C
''';

    String mapping(String name) =>
        'schema: schema.graphql\nscalars:\n  $name:\n    type: DateTime\n'
        '    codec: package:a/a.dart#C\n';

    test('a custom scalar of the schema may be mapped', () {
      expect(check(const [_aFile, _bFile], config: mappings), isEmpty);
    });

    test('an unknown scalar is reported at its key', () {
      expect(check(const [_aFile, _bFile], config: mapping('Foo')), [
        "typed_graphql.yaml:3:3: error GQL505: No scalar 'Foo' in the "
            'schema to map.',
      ]);
    });

    test('an object type is not a scalar', () {
      expect(check(const [_aFile, _bFile], config: mapping('User')), [
        "typed_graphql.yaml:3:3: error GQL505: 'User' is not a scalar, so "
            'it cannot be mapped.',
      ]);
    });

    test('a built-in scalar cannot be mapped', () {
      expect(check(const [_aFile, _bFile], config: mapping('Int')), [
        "typed_graphql.yaml:3:3: error GQL505: The built-in scalar 'Int' "
            'cannot be mapped.',
      ]);
    });

    test('a mapping error is listed before the documents errors', () {
      expect(
        check(const [
          ProjectFile('a.graphql', '{ hello }\n'),
        ], config: mapping('Foo')),
        [
          "typed_graphql.yaml:3:3: error GQL505: No scalar 'Foo' in the "
              'schema to map.',
          'a.graphql:1:1: error GQL503: An operation needs a name: its '
              'classes are named after it.',
        ],
      );
    });
  });

  group('inputs', () {
    test('no documents is one warning without a place', () {
      expect(check(const []), [
        "warning GQL506: No document matches the configuration's "
            "'documents'.",
      ]);
    });

    test('a broken schema is reported with the documents syntax errors', () {
      expect(
        check(
          const [ProjectFile('a.graphql', 'query A { hello\n')],
          schema: const ProjectFile('schema.graphql', 'type Query {\n'),
        ),
        [
          'schema.graphql:2:1: error GQL007: Expected Name, found <EOF>.',
          'a.graphql:2:1: error GQL007: Expected Name, found <EOF>.',
        ],
      );
    });

    test('a syntax error in a document stops validation', () {
      expect(check(const [ProjectFile('a.graphql', 'query A { \n')]), [
        'a.graphql:2:1: error GQL007: Expected Name, found <EOF>.',
      ]);
    });
  });

  group('rules', () {
    test('are the specified rules, minus two, plus the generator\'s', () {
      const dropped = {NoUnusedFragmentsRule, LoneAnonymousOperationRule};
      expect(
        [for (final rule in ClientGenerator.rules) rule.runtimeType],
        [
          for (final rule in DocumentValidator.specifiedRules)
            if (!dropped.contains(rule.runtimeType)) rule.runtimeType,
          NamedOperationsRule,
          UnsupportedDirectivesRule,
        ],
      );
    });
  });

  group('more inputs', () {
    test('empty and comment-only files next to a valid one are accepted', () {
      expect(
        check(const [
          ProjectFile('0.graphql', ''),
          _aFile,
          _bFile,
          ProjectFile('z.graphql', '# only a comment\n'),
        ]),
        isEmpty,
      );
    });

    test('a project of only empty files has no documents', () {
      expect(check(const [ProjectFile('a.graphql', '')]), [
        "warning GQL506: No document matches the configuration's "
            "'documents'.",
      ]);
    });

    test('a schema failure hides an unmapped custom scalar', () {
      // The mapping is checked against a schema, so only the schema's own
      // problem is reported.
      expect(
        check(
          const [_aFile, _bFile],
          schema: const ProjectFile('schema.graphql', 'type Query {\n'),
          config:
              'schema: schema.graphql\nscalars:\n  Foo:\n    type: DateTime\n'
              '    codec: package:a/a.dart#C\n',
        ),
        ['schema.graphql:2:1: error GQL007: Expected Name, found <EOF>.'],
      );
    });

    test('a JSON schema is read as an introspection result', () {
      final document = const Parser()
          .parse(Source(_schema.text))
          .requireDocument();
      final built = const SchemaBuilder().fromSdl(document) as BuildSuccess;
      final json = ProjectFile(
        'schema.json',
        built.schema.toIntrospection().toString(),
      );
      expect(
        check(
          const [_aFile, _bFile],
          schema: json,
          config: 'schema: schema.json\n',
        ),
        isEmpty,
      );
    });
  });
}
