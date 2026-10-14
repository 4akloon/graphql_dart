import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/introspectionFromSchema-test.ts.
// graphql-js builds the schemas in code; the port writes them as SDL.
void main() {
  const port = SchemaPort();
  const dedent = Dedent();

  /// graphql-js's `introspectionToSDL`: [introspection] built back into a
  /// schema and printed.
  String introspectionToSdl(JsonObject introspection) =>
      switch (const SchemaBuilder().fromIntrospection(introspection)) {
        BuildSuccess(:final schema) => port.print(schema),
        BuildFailure(:final diagnostics) => fail('$diagnostics'),
      };

  group('introspectionFromSchema', () {
    final schema = port.build('''
"""This is a simple schema"""
schema {
  query: Simple
}

"""This is a simple type"""
type Simple {
  """This is a string field"""
  string: String
}
''');

    test('converts a simple schema', () {
      final introspection = schema.toIntrospection();
      expect(
        introspectionToSdl(introspection),
        dedent('''
          """This is a simple schema"""
          schema {
            query: Simple
          }

          """This is a simple type"""
          type Simple {
            """This is a string field"""
            string: String
          }
        '''),
      );
    });

    test('converts a simple schema without descriptions', () {
      final introspection = schema.toIntrospection(
        const IntrospectionQuery(
          includesDescriptions: false,
          includesSchemaDescription: true,
        ),
      );
      expect(
        introspectionToSdl(introspection),
        dedent('''
          schema {
            query: Simple
          }

          type Simple {
            string: String
          }
        '''),
      );
    });

    // Directive deprecation is working-draft (graphql-js 17), so the
    // query asks for it explicitly and the SDL applies `@deprecated` to a
    // directive definition.
    test('includes deprecated directives', () {
      final withDeprecatedDirective = port.build('''
type Query {
  string: String
}

directive @deprecatedDirective @deprecated(reason: "Use another directive") on QUERY
''');
      final introspection = withDeprecatedDirective.toIntrospection(
        const IntrospectionQuery(includesDirectiveDeprecation: true),
      );
      final directives = switch (introspection.fields['__schema']) {
        JsonObject(fields: {'directives': JsonArray(:final items)}) => items,
        _ => fail('No directives'),
      };
      final deprecatedDirective = directives.whereType<JsonObject>().where(
        (directive) =>
            directive.fields['name'] == const JsonString('deprecatedDirective'),
      );
      expect(deprecatedDirective, hasLength(1));
      expect(deprecatedDirective.single.fields, <String, JsonValue>{
        'name': const JsonString('deprecatedDirective'),
        'description': const JsonNull(),
        'isDeprecated': const JsonBool(true),
        'deprecationReason': const JsonString('Use another directive'),
        'locations': JsonArray(const [JsonString('QUERY')]),
        'args': JsonArray(const []),
      });
    });
  });
}
