import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _path = 'typed_graphql.yaml';

void main() {
  CodegenConfig read(String text) {
    final result = CodegenConfig.parse(text, path: _path);
    if (result is! ConfigSuccess) fail('expected success, got $result');
    return result.config;
  }

  List<String> problems(String text) {
    final result = CodegenConfig.parse(text, path: _path);
    if (result is! ConfigFailure) fail('expected failure, got $result');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  group('valid files', () {
    test('a full file is read with every key', () {
      final config = read(r'''
schema: https://api.example.com/graphql
documents:
  - lib/**.graphql
  - test/**.graphql
schema_types: lib/src/schema.dart
persisted_operations: lib/operations.json
scalars:
  Url:
    type: Uri
    codec: package:my_app/codecs.dart#UrlCodec
  DateTime:
    type: dart:core#DateTime
    codec: package:my_app/codecs.dart#DateTimeCodec
  Money:
    type: package:money/money.dart#Money
    codec: package:my_app/codecs.dart#MoneyCodec
headers:
  X-Trace: abc
  Authorization: Bearer ${TOKEN}
''');
      expect(
        config.schema,
        SchemaUrl(Uri.parse('https://api.example.com/graphql')),
      );
      expect(config.documents, ['lib/**.graphql', 'test/**.graphql']);
      expect(config.schemaTypes, 'lib/src/schema.dart');
      expect(config.persistedOperations, 'lib/operations.json');
      expect(config.scalars.keys, ['DateTime', 'Money', 'Url']);
      expect(config.headers, {
        'Authorization': r'Bearer ${TOKEN}',
        'X-Trace': 'abc',
      });
    });

    test('a file with only a schema takes the defaults', () {
      final config = read('schema: schema.graphql\n');
      expect(config.schema, const SchemaFile('schema.graphql'));
      expect(config.documents, ['lib/**.graphql']);
      expect(config.schemaTypes, 'lib/schema.graphql.dart');
      expect(config.persistedOperations, isNull);
      expect(config.scalars, isEmpty);
      expect(config.headers, isEmpty);
    });

    test('a JSON schema file is an introspection result', () {
      final config = read('schema: introspection.json\n');
      expect(config.schema, const SchemaFile('introspection.json'));
      expect((config.schema as SchemaFile).isIntrospection, isTrue);
    });

    test('documents may be a single string', () {
      expect(read('schema: s.graphql\ndocuments: ops/*.graphql\n').documents, [
        'ops/*.graphql',
      ]);
    });

    test('dart:core#DateTime has no library', () {
      final config = read('''
schema: s.graphql
scalars:
  Moment:
    type: dart:core#DateTime
    codec: package:a/a.dart#C
''');
      expect(
        config.scalars['Moment']?.type,
        const DartReference(null, 'DateTime'),
      );
    });

    test('a bare core type has no library', () {
      final config = read('''
schema: s.graphql
scalars:
  Moment:
    type: DateTime
    codec: package:a/a.dart#C
''');
      expect(
        config.scalars['Moment'],
        const ScalarMapping(
          DartReference(null, 'DateTime'),
          DartReference('package:a/a.dart', 'C'),
        ),
      );
    });

    test('a scalar mapping keeps the place of its key', () {
      final config = read(
        'schema: s.graphql\nscalars:\n  Moment:\n    type: DateTime\n'
        '    codec: package:a/a.dart#C\n',
      );
      expect('${config.scalars['Moment']!.span}', '$_path:3:3');
    });

    test('the maps are unmodifiable', () {
      final config = read('schema: https://h.dev/g\nheaders:\n  A: b\n');
      expect(() => config.headers['C'] = 'd', throwsUnsupportedError);
    });

    test('a URL schema keeps its headers raw', () {
      final config = read(
        'schema: http://localhost:4000/graphql\nheaders:\n'
        r'  Authorization: ${T}'
        '\n',
      );
      expect(config.headers, {'Authorization': r'${T}'});
    });
  });

  group('syntax errors', () {
    test('invalid YAML is a GQL500 at its place', () {
      expect(problems('schema: [a\n'), hasLength(1));
      expect(problems('schema: [a\n').single, startsWith('$_path:'));
      expect(problems('schema: [a\n').single, contains('error GQL500: '));
    });

    test('a duplicate key is a GQL500', () {
      expect(
        problems('schema: a.graphql\nschema: b.graphql\n').single,
        contains('error GQL500: '),
      );
    });
  });

  group('structure problems', () {
    test('an empty file must be a map', () {
      expect(problems(''), [
        '$_path:1:1: error GQL501: The configuration must be a YAML map.',
      ]);
    });

    test('a list root must be a map', () {
      expect(problems('- a\n'), [
        '$_path:1:1: error GQL501: The configuration must be a YAML map.',
      ]);
    });

    test('the schema key is required', () {
      expect(problems('documents: a.graphql\n'), [
        "$_path:1:1: error GQL501: The key 'schema' is required.",
      ]);
    });

    test('an unknown key lists the known ones', () {
      expect(problems('schema: s.graphql\nschemas: x\n'), [
        "$_path:2:1: error GQL501: Unknown key 'schemas'; the keys are "
            "'documents', 'headers', 'persisted_operations', 'scalars', "
            "'schema', 'schema_types'.",
      ]);
    });

    test('a value of the wrong kind says what is expected', () {
      expect(problems('schema: s.graphql\nschema_types: 5\n'), [
        "$_path:2:15: error GQL501: 'schema_types' must be a string.",
      ]);
    });

    test('a null schema is not a string', () {
      expect(problems('schema:\n'), [
        "$_path:1:7: error GQL501: 'schema' must be a string.",
      ]);
    });
  });

  group('path problems', () {
    test('an empty path', () {
      expect(problems('schema: ""\n'), [
        "$_path:1:9: error GQL501: 'schema' must not be empty.",
      ]);
    });

    test('an absolute path', () {
      expect(problems('schema: /etc/s.graphql\n'), [
        "$_path:1:9: error GQL501: 'schema' must be a relative path.",
      ]);
    });

    test('a drive letter path', () {
      expect(problems('schema: C:/s.graphql\n'), [
        "$_path:1:9: error GQL501: 'schema' must be a relative path.",
      ]);
    });

    test('a backslash', () {
      expect(problems("schema: 'a\\b.graphql'\n"), [
        "$_path:1:9: error GQL501: 'schema' must use '/' as the separator.",
      ]);
    });

    test('a parent segment', () {
      expect(problems('schema: ../s.graphql\n'), [
        "$_path:1:9: error GQL501: 'schema' must not have a '..' segment.",
      ]);
    });

    test('schema_types must end with .dart', () {
      expect(problems('schema: s.graphql\nschema_types: lib/s.txt\n'), [
        "$_path:2:15: error GQL501: 'schema_types' must end with '.dart'.",
      ]);
    });

    test('persisted_operations must end with .json', () {
      expect(problems('schema: s.graphql\npersisted_operations: p.txt\n'), [
        "$_path:2:23: error GQL501: 'persisted_operations' must end with "
            "'.json'.",
      ]);
    });

    test('an empty documents list', () {
      expect(problems('schema: s.graphql\ndocuments: []\n'), [
        "$_path:2:12: error GQL501: 'documents' must not be an empty list.",
      ]);
    });

    test('a bad entry of documents', () {
      expect(problems('schema: s.graphql\ndocuments:\n  - /abs\n'), [
        "$_path:3:5: error GQL501: 'documents' must be a relative path.",
      ]);
    });
  });

  group('schema location problems', () {
    test('a URL without a host', () {
      expect(problems('schema: http://\n'), [
        "$_path:1:9: error GQL501: 'schema' is not a valid URL.",
      ]);
    });

    test('headers need a schema URL', () {
      expect(problems('schema: s.graphql\nheaders:\n  A: b\n'), [
        "$_path:2:1: error GQL501: 'headers' apply only to a schema URL.",
      ]);
    });
  });

  group('headers problems', () {
    test('a header name with a colon', () {
      expect(problems('schema: https://h.dev/g\nheaders:\n  "A:b": c\n'), [
        "$_path:3:3: error GQL501: 'A:b' is not a valid header name.",
      ]);
    });

    test('a header value that is not a string', () {
      expect(problems('schema: https://h.dev/g\nheaders:\n  A: 1\n'), [
        "$_path:3:6: error GQL501: 'headers.A' must be a string.",
      ]);
    });

    test('headers that are not a map', () {
      expect(problems('schema: https://h.dev/g\nheaders: x\n'), [
        "$_path:2:10: error GQL501: 'headers' must be a map of header names "
            'to strings.',
      ]);
    });
  });
}
