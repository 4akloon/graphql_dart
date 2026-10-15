import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _sdl = 'type Query { hello: String }\n';

void main() {
  const loader = SchemaLoader();

  SchemaLoadResult load(String path, String text) =>
      loader.load(ProjectFile(path, text));

  List<String> problems(String path, String text) {
    final result = load(path, text);
    if (result is! SchemaNotLoaded) fail('expected failure, got $result');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  ValidSchema loaded(String path, String text) {
    final result = load(path, text);
    if (result is! SchemaLoaded) fail('expected a schema, got $result');
    return result.schema;
  }

  String introspectionOf(String sdl) {
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    return schema.toIntrospection().toString();
  }

  group('SDL', () {
    test('a valid schema loads', () {
      final schema = loaded('schema.graphql', _sdl).schema;
      expect(schema.typeNamed('Query'), isA<ObjectType>());
    });

    test('a syntax error is printed at its place', () {
      expect(problems('schema.graphql', 'type Query {\n  hello String\n}\n'), [
        'schema.graphql:2:9: error GQL007: Expected ":", found Name "String".',
      ]);
    });

    test('a build error is reported', () {
      expect(problems('schema.graphql', '$_sdl\ntype Query { b: Int }\n'), [
        'schema.graphql:3:6: error GQL101: There can be only one type named '
            '"Query".',
      ]);
    });

    test('a validation error is reported', () {
      expect(problems('schema.graphql', 'type Query\n'), [
        'schema.graphql:1:1: error GQL125: Type Query must define one or '
            'more fields.',
      ]);
    });

    test('a schema of more than 15000 tokens loads', () {
      final fields = [for (var i = 0; i < 4000; i++) '  f$i: Int'];
      final text = 'type Query {\n${fields.join('\n')}\n}\n';
      expect(
        loaded('schema.graphql', text).schema.typeNamed('Query'),
        isNotNull,
      );
    });
  });

  group('introspection', () {
    test('a result loads', () {
      final text = introspectionOf(_sdl);
      expect(loaded('x.json', text).schema.typeNamed('Query'), isNotNull);
    });

    test('a response with data loads', () {
      final text = '{"data": ${introspectionOf(_sdl)}}';
      expect(loaded('x.json', text).schema.typeNamed('Query'), isNotNull);
    });

    test('text that is not JSON is reported', () {
      final messages = problems('x.json', '{');
      expect(messages, hasLength(1));
      expect(
        messages.single,
        startsWith(
          r'x.json:1:1: error GQL502: The schema file cannot be read: $: '
          'not JSON: ',
        ),
      );
    });

    test('a JSON array is reported', () {
      expect(problems('x.json', '[]'), [
        'x.json:1:1: error GQL502: The schema file must hold a JSON object.',
      ]);
    });

    test('an object without __schema is reported at the file', () {
      final messages = problems('x.json', '{}');
      expect(messages, hasLength(1));
      expect(messages.single, startsWith('x.json:1:1: error GQL15'));
    });
  });

  test(
    'a JSON nested past the depth limit is reported with the depth limit',
    () {
      final text = '${'[' * 2000}${']' * 2000}';
      final messages = problems('x.json', text);
      expect(messages, hasLength(1));
      expect(
        messages.single,
        r'x.json:1:1: error GQL502: The schema file cannot be read: $: arrays '
        'and objects are nested deeper than 512.',
      );
    },
  );
}
