import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
type Query {
  hello: String
  user(id: ID!): User
}
type User {
  id: ID!
}
''');

const _documents = [
  ProjectFile(
    'lib/b.graphql',
    r'query UserById($id: ID!) { user(id: $id) { id } }',
  ),
  ProjectFile('lib/a.graphql', 'query Hello { hello }'),
];

void main() {
  CodegenConfig configOf(String text) {
    final result = CodegenConfig.parse(text, path: 'typed_graphql.yaml');
    if (result is! ConfigSuccess) fail('expected success, got $result');
    return result.config;
  }

  GenerationResult generate(String config) => ClientGenerator(
    configOf(config),
  ).generate(schema: _schema, documents: _documents);

  test('the manifest lists the operations sorted by name', () {
    final result = generate(
      'schema: schema.graphql\n'
      'persisted_operations: build/manifest.json\n',
    );
    expect(result.diagnostics, isEmpty);
    expect(
      result.files.last,
      const GeneratedFile('build/manifest.json', r'''
{
  "format": "apollo-persisted-query-manifest",
  "version": 1,
  "operations": [
    {
      "id": "f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623",
      "name": "Hello",
      "type": "query",
      "body": "query Hello{hello}"
    },
    {
      "id": "929f61823015722c0a8fcfd21c9d6ac0bb9d13a9fb519c13355294cf48357ce6",
      "name": "UserById",
      "type": "query",
      "body": "query UserById($id:ID!){user(id:$id){id __typename}}"
    }
  ]
}
'''),
    );
  });

  test('the manifest ids are the hashes the operation classes carry', () {
    final result = generate(
      'schema: schema.graphql\n'
      'persisted_operations: build/manifest.json\n',
    );
    final manifest = result.files.last.text;
    for (final file in result.files.where((f) => f.path.endsWith('.dart'))) {
      for (final match in RegExp(
        r'sha256:\s*\n?\s*\x27([0-9a-f]{64})\x27',
      ).allMatches(file.text)) {
        expect(manifest, contains(match.group(1)));
      }
    }
  });

  test('the files keep their order: schema types, libraries, manifest', () {
    final result = generate(
      'schema: schema.graphql\n'
      'persisted_operations: build/manifest.json\n',
    );
    expect(
      [for (final file in result.files) file.path],
      [
        'lib/schema.graphql.dart',
        'lib/a.graphql.dart',
        'lib/b.graphql.dart',
        'build/manifest.json',
      ],
    );
  });

  test('without the key no manifest is written', () {
    final result = generate('schema: schema.graphql\n');
    expect(
      result.files.where((file) => file.path.endsWith('.json')),
      isEmpty,
    );
  });

  test('the manifest path must end with .json', () {
    final result = CodegenConfig.parse(
      'schema: schema.graphql\npersisted_operations: build/manifest.txt\n',
      path: 'typed_graphql.yaml',
    );
    expect(
      (result as ConfigFailure).diagnostics.single.message,
      "'persisted_operations' must end with '.json'.",
    );
  });
}
