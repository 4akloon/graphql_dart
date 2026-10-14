import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  /// The result of building [result] from introspection.
  BuildResult fromJson(Object? result) => const SchemaBuilder()
      .fromIntrospection(switch (const JsonReader().read(result)) {
        DecodeSuccess(:final value) => value,
        DecodeFailure() => throw StateError('not JSON: $result'),
      });

  /// The messages of the diagnostics of [result].
  List<String> messagesOf(BuildResult result) => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.code.id} ${diagnostic.message}',
  ];

  /// [sdl] written as introspection, as plain Dart objects to edit.
  Map<String, Object?> introspectionOf(String sdl) =>
      Built(sdl).schema.toIntrospection().toJson();

  /// The `__schema.types` entry of [json] named [name].
  Map<String, Object?> typeIn(Map<String, Object?> json, String name) {
    final schema = json['__schema']! as Map<String, Object?>;
    return (schema['types']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((type) => type['name'] == name);
  }

  group('SchemaBuilder.fromIntrospection', () {
    test('reads back what toIntrospection writes', () {
      const sdl = '''
"""A schema"""
schema {
  query: Root
}

directive @tag(name: String = "x") repeatable on FIELD_DEFINITION | QUERY

scalar Url @specifiedBy(url: "https://example.com")

type Root implements Node {
  id: ID!
  items(first: Int = 10, after: String @deprecated): [Item!]! @deprecated(reason: "Use edges")
  url: Url
}

interface Node {
  id: ID!
}

union Item = Root

enum Color {
  RED
  GREEN @deprecated
}

input Filter @oneOf {
  color: Color
  ids: [ID!]
}''';
      final schema = Built(sdl).schema;
      final result = fromJson(schema.toIntrospection().toJson());
      final rebuilt = (result as BuildSuccess).schema;
      expect(const SchemaPrinter().print(rebuilt), sdl);
    });

    test('leaves the built-in types and directives undeclared', () {
      final result = fromJson(introspectionOf('type Query { a: Int }'));
      final schema = (result as BuildSuccess).schema;
      expect(schema.types.map((type) => type.name), ['Query']);
      expect(schema.directives, isEmpty);
    });

    test('turns on @defer and @stream when the result lists them', () {
      final schema = const SchemaBuilder(
        includesDeferAndStream: true,
      ).fromSdl(Sdl('type Query { a: Int }').document);
      final json = (schema as BuildSuccess).schema.toIntrospection().toJson();
      final rebuilt = (fromJson(json) as BuildSuccess).schema;
      expect(rebuilt.includesDeferAndStream, isTrue);
      expect(rebuilt.directives, isEmpty);
    });

    test('rejects a result without __schema', () {
      expect(messagesOf(fromJson({'data': <String, Object?>{}})), [
        r'GQL150 $: Invalid or incomplete introspection result. Ensure that '
            'you are passing "data" property of introspection response and '
            'no "errors" was returned alongside.',
      ]);
    });

    test('reports a missing member with its path', () {
      final json = introspectionOf('type Query { a: Int }');
      typeIn(json, 'Query').remove('fields');
      expect(messagesOf(fromJson(json)), [
        r'GQL151 $.__schema.types[0]: Introspection result missing fields.',
      ]);
    });

    test('reports an unknown kind', () {
      final json = introspectionOf('type Query { a: Int }');
      typeIn(json, 'Query')['kind'] = 'TABLE';
      expect(fromJson(json).diagnostics.single.code.id, 'GQL152');
    });

    test('reports a member of the wrong JSON type', () {
      final json = introspectionOf('type Query { a: Int }');
      typeIn(json, 'Query')['description'] = 3;
      expect(messagesOf(fromJson(json)), [
        r'GQL153 $.__schema.types[0].description: expected a string',
      ]);
    });

    test('reports a default value that does not parse', () {
      final json = introspectionOf('type Query { a(b: Int = 1): Int }');
      final field =
          (typeIn(json, 'Query')['fields']! as List<Object?>).single!
              as Map<String, Object?>;
      final argument =
          (field['args']! as List<Object?>).single! as Map<String, Object?>;
      argument['defaultValue'] = r'$var';
      expect(
        fromJson(json).diagnostics.single.message,
        startsWith(
          r'$.__schema.types[0].fields[0].args[0].defaultValue: Default value '
          'is not a constant GraphQL value: ',
        ),
      );
    });

    test('reports an unknown directive location', () {
      final json = introspectionOf(
        'directive @a on FIELD type Query { a: Int }',
      );
      final schema = json['__schema']! as Map<String, Object?>;
      final directive =
          (schema['directives']! as List<Object?>).first!
              as Map<String, Object?>;
      directive['locations'] = ['FIELD', 'NOWHERE'];
      expect(messagesOf(fromJson(json)), [
        r'GQL153 $.__schema.directives[0].locations[1]: Unknown directive '
            'location "NOWHERE".',
      ]);
    });

    test('reports a reference to a type the result does not list', () {
      final json = introspectionOf('type Query { a: Int }');
      final schema = json['__schema']! as Map<String, Object?>;
      (schema['types']! as List<Object?>).removeWhere(
        (type) => (type! as Map<String, Object?>)['name'] == 'Int',
      );
      expect(messagesOf(fromJson(json)), [
        r'GQL154 $.__schema.types[0].fields[0].type: Invalid or incomplete '
            'schema, unknown type: Int. Ensure that a full introspection '
            'query is used in order to build a client schema.',
      ]);
    });

    test('reports a type deeper than the query read', () {
      final schema = Built('type Query { a: [[Int]] }').schema;
      final json = schema.toIntrospection(
        const IntrospectionQuery(typeDepth: 1),
      );
      expect(messagesOf(fromJson(json.toJson())), [
        r'GQL155 $.__schema.types[0].fields[0].type.ofType: Decorated type '
            'deeper than introspection query.',
      ]);
    });

    test('reports a non-null type inside a non-null type', () {
      final json = introspectionOf('type Query { a: Int! }');
      final field =
          (typeIn(json, 'Query')['fields']! as List<Object?>).single!
              as Map<String, Object?>;
      field['type'] = {
        'kind': 'NON_NULL',
        'name': null,
        'ofType': field['type'],
      };
      expect(messagesOf(fromJson(json)), [
        r'GQL153 $.__schema.types[0].fields[0].type: Expected a nullable '
            'type inside NON_NULL.',
      ]);
    });

    /// A result whose only field has [wrappers] `LIST` levels around `Int`.
    JsonObject resultWithWrappers(int wrappers) {
      JsonValue reference = JsonObject({
        'kind': const JsonString('SCALAR'),
        'name': const JsonString('Int'),
        'ofType': const JsonNull(),
      });
      for (var i = 0; i < wrappers; i++) {
        reference = JsonObject({
          'kind': const JsonString('LIST'),
          'name': const JsonNull(),
          'ofType': reference,
        });
      }
      final query = JsonObject({
        'kind': const JsonString('OBJECT'),
        'name': const JsonString('Query'),
        'interfaces': JsonArray(const []),
        'fields': JsonArray([
          JsonObject({
            'name': const JsonString('a'),
            'args': JsonArray(const []),
            'type': reference,
          }),
        ]),
      });
      final scalar = JsonObject({
        'kind': const JsonString('SCALAR'),
        'name': const JsonString('Int'),
      });
      return JsonObject({
        '__schema': JsonObject({
          'queryType': JsonObject({'name': const JsonString('Query')}),
          'types': JsonArray([query, scalar]),
        }),
      });
    }

    test('reads the deepest chain a query can ask for and prints it', () {
      final result = const SchemaBuilder().fromIntrospection(
        resultWithWrappers(100),
      );
      final schema = switch (result) {
        BuildSuccess(:final schema) => schema,
        BuildFailure() => fail('${messagesOf(result)}'),
      };
      final printed = const SchemaPrinter().print(schema);
      expect(printed, contains('${'[' * 100}Int${']' * 100}'));
    });

    test('reports a chain one level deeper than a query can ask for', () {
      final result = const SchemaBuilder().fromIntrospection(
        resultWithWrappers(101),
      );
      expect(
        messagesOf(result).single,
        endsWith(
          'type${'.ofType' * 100}: Decorated type deeper than introspection '
          'query.',
        ),
      );
    });

    test('reports a chain of 10000 levels at once, without recursion', () {
      final watch = Stopwatch()..start();
      final result = const SchemaBuilder().fromIntrospection(
        resultWithWrappers(10000),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
        messagesOf(result).single,
        endsWith(
          'type${'.ofType' * 100}: Decorated type deeper than introspection '
          'query.',
        ),
      );
    });
  });
}
