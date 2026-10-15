@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/introspection_fixture.dart';

final class _Fields {
  const _Fields(this.values);

  final Map<String, Object?> values;
}

final class _Complex {
  const _Complex(this.x, this.y);

  final List<String> x;
  final int y;
}

enum _SomeEnum { value }

// Ported from graphql-js src/type/__tests__/introspection-test.ts (the
// deprecation tests are in introspection_deprecation_test.dart);
// mapping/execution.csv says which tests are adapted or skipped, and why.
// graphql-js builds its schemas from SDL; these are built with the typed
// builder and have the same types, fields, defaults and descriptions.
void main() {
  const port = ExecutionPort();

  ExecutableSchemaBuilder<Object?> builder() => ExecutableSchemaBuilder();

  ObjectTypeDef<Object?> queryOf(
    ExecutableSchemaBuilder<Object?> b,
    List<FieldDef<Object?, Object?>> Function(FieldsBuilder<Object?, Object?> t)
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  FieldDef<Object?, Object?> someField(
    FieldsBuilder<Object?, Object?> t,
    OutputRef<Object?> type, {
    List<Arg<Object?>> args = const [],
    String name = 'someField',
  }) => t.field(name, type, args: args).resolve((_, a, c, i) => null);

  Future<Map<String, Object?>> introspect(
    ExecutableSchema<Object?> schema,
    String source,
  ) => port.respond(schema, source);

  group('Introspection', () {
    test('executes an introspection query', () async {
      final b = builder();
      final someObject = b.object<Object?>(
        'SomeObject',
        fields: (t) => [someField(t, b.string.nullable)],
      );
      final schema = b.build(query: someObject);

      final source = const IntrospectionQuery(
        includesDescriptions: false,
        includesSpecifiedByUrl: true,
        includesDirectiveIsRepeatable: true,
      ).text;

      final expected = const IntrospectionFixture().expected();
      expect(await introspect(schema, source), expected);
    });

    test('introspects on input object', () async {
      final b = builder();
      final someInput = b.inputObject<_Fields>(
        'SomeInputObject',
        fields: () => [
          Arg('a', b.string.nullable, defaultValue: 'tes\t de\fault'),
          Arg('b', b.inputList(b.string.nullable).nullable),
          Arg('c', b.string.nullable),
        ],
        decode: (values) => const _Fields({}),
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              b.string.nullable,
              args: [Arg('someArg', someInput.nullable)],
            ),
          ],
        ),
      );

      const source = '''

      {
        __type(name: "SomeInputObject") {
          kind
          name
          inputFields {
            name
            type { ...TypeRef }
            defaultValue
          }
        }
      }

      fragment TypeRef on __Type {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
            }
          }
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          '__type': {
            'kind': 'INPUT_OBJECT',
            'name': 'SomeInputObject',
            'inputFields': [
              {
                'name': 'a',
                'type': {'kind': 'SCALAR', 'name': 'String', 'ofType': null},
                'defaultValue': r'"tes\t de\fault"',
              },
              {
                'name': 'b',
                'type': {
                  'kind': 'LIST',
                  'name': null,
                  'ofType': {
                    'kind': 'SCALAR',
                    'name': 'String',
                    'ofType': null,
                  },
                },
                'defaultValue': null,
              },
              {
                'name': 'c',
                'type': {'kind': 'SCALAR', 'name': 'String', 'ofType': null},
                'defaultValue': null,
              },
            ],
          },
        },
      });
    });

    test('introspects any default value', () async {
      final b = builder();
      final complex = b.inputObject<_Complex>(
        'Complex',
        fields: () => [
          Arg('x', b.inputList(b.string.nullable).nullable),
          Arg('y', b.int.nullable),
        ],
        decode: (values) => const _Complex([], 0),
        encode: (value) => JsonObject({
          'x': JsonArray([for (final item in value.x) JsonString(item)]),
          'y': JsonNumber(value.y),
        }),
      );
      final withDefaults = b.inputObject<_Fields>(
        'InputObjectWithDefaultValues',
        fields: () => [
          Arg('a', b.string.nullable, defaultValue: 'Emoji: \u{1F600}'),
          Arg(
            'b',
            complex.nullable,
            defaultValue: const _Complex(['abc'], 123),
          ),
        ],
        decode: (values) => const _Fields({}),
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              b.string.nullable,
              args: [Arg('someArg', withDefaults.nullable)],
            ),
          ],
        ),
      );

      const source = '''

      {
        __type(name: "InputObjectWithDefaultValues") {
          inputFields {
            name
            defaultValue
          }
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          '__type': {
            'inputFields': [
              {'name': 'a', 'defaultValue': '"Emoji: \u{1F600}"'},
              {'name': 'b', 'defaultValue': '{ x: ["abc"], y: 123 }'},
            ],
          },
        },
      });
    });

    test('supports the __type root field', () async {
      final b = builder();
      final schema = b.build(
        query: queryOf(b, (t) => [someField(t, b.string.nullable)]),
      );

      const source = '''

      {
        __type(name: "Query") {
          name
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          '__type': {'name': 'Query'},
        },
      });
    });

    test('fails as expected on the __type root field without an arg', () async {
      final b = builder();
      final schema = b.build(
        query: queryOf(b, (t) => [someField(t, b.string.nullable)]),
      );

      const source = '''

      {
        __type {
          name
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'errors': [
          {
            'message': 'Argument "<meta>.__type(name:)" of type "String!" is required, but it was not provided.',
            'locations': [
              {'line': 3, 'column': 9},
            ],
          },
        ],
      });
    });

    test('exposes descriptions', () async {
      final b = builder();
      final someEnum = b.enumType<_SomeEnum>(
        'SomeEnum',
        _SomeEnum.values,
        description: 'Enum description',
        mapping: EnumValueMapping<_SomeEnum>(
          nameOf: (value) => 'VALUE',
          descriptionOf: (value) => 'Value description',
        ),
      );
      final someObject = b.object<Object?>(
        'SomeObject',
        description: 'Object description',
        fields: (t) => [
          t
              .field(
                'someField',
                b.string.nullable,
                args: [Arg('arg', someEnum.nullable)],
                description: 'Field description',
              )
              .resolve((_, a, c, i) => null),
        ],
      );
      final schema = b.build(
        query: someObject,
        options: const BuildOptions(description: 'Schema description'),
      );

      const source = '''

      {
        Schema: __schema { description }
        SomeObject: __type(name: "SomeObject") {
          description,
          fields {
            name
            description
          }
        }
        SomeEnum: __type(name: "SomeEnum") {
          description
          enumValues {
            name
            description
          }
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          'Schema': {'description': 'Schema description'},
          'SomeEnum': {
            'description': 'Enum description',
            'enumValues': [
              {'name': 'VALUE', 'description': 'Value description'},
            ],
          },
          'SomeObject': {
            'description': 'Object description',
            'fields': [
              {'name': 'someField', 'description': 'Field description'},
            ],
          },
        },
      });
    });

    test(
      'executes an introspection query without calling global resolvers',
      () async {
        final b = ExecutableSchemaBuilder<Object?>();
        final calls = <String>[];
        final schema = b.build(
          query: queryOf(b, (t) => [someField(t, b.string.nullable)]),
          options: BuildOptions<Object?>(
            middleware: [
              (next, site) => (parent, args, context, info) {
                calls.add('${info.parentTypeName}::${info.fieldName}');
                return next(parent, args, context, info);
              },
            ],
          ),
        );

        final source = const IntrospectionQuery(
          includesSpecifiedByUrl: true,
          includesDirectiveIsRepeatable: true,
          includesSchemaDescription: true,
        ).text;

        expect(await introspect(schema, source), isNot(contains('errors')));
        expect(calls, isEmpty);
      },
    );
  });
}
