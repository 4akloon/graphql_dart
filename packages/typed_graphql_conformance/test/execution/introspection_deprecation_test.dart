import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Fields {
  const _Fields();
}

enum _Value { nonDeprecated, deprecated, deprecatedWithEmptyReason, also }

// Ported from the deprecation tests of graphql-js
// src/type/__tests__/introspection-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. graphql-js builds its schemas from
// SDL; these are built with the typed builder and have the same members.
void main() {
  const port = ExecutionPort();

  ExecutableSchemaBuilder<Object?> builder() => ExecutableSchemaBuilder();

  ObjectTypeDef<Object?> queryOf(
    ExecutableSchemaBuilder<Object?> b,
    List<FieldDef<Object?, Object?>> Function(FieldsBuilder<Object?, Object?> t)
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  FieldStub<Object?, String?, Object?> stringField(
    FieldsBuilder<Object?, Object?> t,
    ExecutableSchemaBuilder<Object?> b,
    String name, {
    List<Arg<Object?>> args = const [],
  }) => t.field(name, b.string.nullable, args: args);

  FieldDef<Object?, Object?> resolved(
    FieldStub<Object?, String?, Object?> stub,
  ) => stub.resolve((_, a, c, i) => null);

  Future<Map<String, Object?>> introspect(
    ExecutableSchema<Object?> schema,
    String source,
  ) => port.respond(schema, source);

  ExecutableSchema<Object?> fieldSchema({required bool hasEmptyReason}) {
    final b = builder();
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(stringField(t, b, 'nonDeprecated')),
          resolved(
            stringField(t, b, 'deprecated').deprecated('Removed in 1.0'),
          ),
          if (hasEmptyReason)
            resolved(
              stringField(t, b, 'deprecatedWithEmptyReason').deprecated(''),
            ),
        ],
      ),
    );
  }

  ExecutableSchema<Object?> argumentSchema({required bool hasEmptyReason}) {
    final b = builder();
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(
            stringField(
              t,
              b,
              'someField',
              args: [
                Arg('nonDeprecated', b.string.nullable),
                Arg(
                  'deprecated',
                  b.string.nullable,
                  deprecationReason: 'Removed in 1.0',
                ),
                if (hasEmptyReason)
                  Arg(
                    'deprecatedWithEmptyReason',
                    b.string.nullable,
                    deprecationReason: '',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ExecutableSchema<Object?> enumSchema({required bool hasEmptyReason}) {
    final b = builder();
    final someEnum = b.enumType<_Value>(
      'SomeEnum',
      [
        for (final value in _Value.values)
          if (hasEmptyReason || value != _Value.deprecatedWithEmptyReason)
            value,
      ],
      mapping: EnumValueMapping<_Value>(
        nameOf: (value) => switch (value) {
          _Value.nonDeprecated => 'NON_DEPRECATED',
          _Value.deprecated => 'DEPRECATED',
          _Value.deprecatedWithEmptyReason => 'DEPRECATED_WITH_EMPTY_REASON',
          _Value.also => 'ALSO_NON_DEPRECATED',
        },
        deprecationReasonOf: (value) => switch (value) {
          _Value.deprecated => 'Removed in 1.0',
          _Value.deprecatedWithEmptyReason => '',
          _ => null,
        },
      ),
    );
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(
            stringField(
              t,
              b,
              'someField',
              args: [Arg('someArg', someEnum.nullable)],
            ),
          ),
        ],
      ),
    );
  }

  ExecutableSchema<Object?> inputSchema({required bool hasEmptyReason}) {
    final b = builder();
    final someInput = b.inputObject<_Fields>(
      'SomeInputObject',
      fields: () => [
        Arg('nonDeprecated', b.string.nullable),
        Arg(
          'deprecated',
          b.string.nullable,
          deprecationReason: 'Removed in 1.0',
        ),
        if (hasEmptyReason)
          Arg(
            'deprecatedWithEmptyReason',
            b.string.nullable,
            deprecationReason: '',
          ),
      ],
      decode: (values) => const _Fields(),
    );
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(
            stringField(
              t,
              b,
              'someField',
              args: [Arg('someArg', someInput.nullable)],
            ),
          ),
        ],
      ),
    );
  }

  group('Introspection', () {
    test('identifies deprecated fields', () async {
      const source = '''

      {
        __type(name: "Query") {
          fields(includeDeprecated: true) {
            name
            isDeprecated,
            deprecationReason
          }
        }
      }
    ''';

      expect(await introspect(fieldSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'fields': [
              {
                'name': 'nonDeprecated',
                'isDeprecated': false,
                'deprecationReason': null,
              },
              {
                'name': 'deprecated',
                'isDeprecated': true,
                'deprecationReason': 'Removed in 1.0',
              },
              {
                'name': 'deprecatedWithEmptyReason',
                'isDeprecated': true,
                'deprecationReason': '',
              },
            ],
          },
        },
      });
    });

    test('respects the includeDeprecated parameter for fields', () async {
      const source = '''

      {
        __type(name: "Query") {
          trueFields: fields(includeDeprecated: true) {
            name
          }
          falseFields: fields(includeDeprecated: false) {
            name
          }
          omittedFields: fields {
            name
          }
        }
      }
    ''';

      expect(await introspect(fieldSchema(hasEmptyReason: false), source), {
        'data': {
          '__type': {
            'trueFields': [
              {'name': 'nonDeprecated'},
              {'name': 'deprecated'},
            ],
            'falseFields': [
              {'name': 'nonDeprecated'},
            ],
            'omittedFields': [
              {'name': 'nonDeprecated'},
            ],
          },
        },
      });
    });

    test('identifies deprecated args', () async {
      const source = '''

      {
        __type(name: "Query") {
          fields {
            args(includeDeprecated: true) {
              name
              isDeprecated,
              deprecationReason
            }
          }
        }
      }
    ''';

      expect(await introspect(argumentSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'fields': [
              {
                'args': [
                  {
                    'name': 'nonDeprecated',
                    'isDeprecated': false,
                    'deprecationReason': null,
                  },
                  {
                    'name': 'deprecated',
                    'isDeprecated': true,
                    'deprecationReason': 'Removed in 1.0',
                  },
                  {
                    'name': 'deprecatedWithEmptyReason',
                    'isDeprecated': true,
                    'deprecationReason': '',
                  },
                ],
              },
            ],
          },
        },
      });
    });

    test('respects the includeDeprecated parameter for args', () async {
      const source = '''

      {
        __type(name: "Query") {
          fields {
            trueArgs: args(includeDeprecated: true) {
              name
            }
            falseArgs: args(includeDeprecated: false) {
              name
            }
            omittedArgs: args {
              name
            }
          }
        }
      }
    ''';

      expect(await introspect(argumentSchema(hasEmptyReason: false), source), {
        'data': {
          '__type': {
            'fields': [
              {
                'trueArgs': [
                  {'name': 'nonDeprecated'},
                  {'name': 'deprecated'},
                ],
                'falseArgs': [
                  {'name': 'nonDeprecated'},
                ],
                'omittedArgs': [
                  {'name': 'nonDeprecated'},
                ],
              },
            ],
          },
        },
      });
    });

    test('identifies deprecated enum values', () async {
      const source = '''

      {
        __type(name: "SomeEnum") {
          enumValues(includeDeprecated: true) {
            name
            isDeprecated,
            deprecationReason
          }
        }
      }
    ''';

      // The graphql-js enum has no value with an empty reason here.
      expect(await introspect(enumSchema(hasEmptyReason: false), source), {
        'data': {
          '__type': {
            'enumValues': [
              {
                'name': 'NON_DEPRECATED',
                'isDeprecated': false,
                'deprecationReason': null,
              },
              {
                'name': 'DEPRECATED',
                'isDeprecated': true,
                'deprecationReason': 'Removed in 1.0',
              },
              {
                'name': 'ALSO_NON_DEPRECATED',
                'isDeprecated': false,
                'deprecationReason': null,
              },
            ],
          },
        },
      });
    });

    test('respects the includeDeprecated parameter for enum values', () async {
      const source = '''

      {
        __type(name: "SomeEnum") {
          trueValues: enumValues(includeDeprecated: true) {
            name
          }
          falseValues: enumValues(includeDeprecated: false) {
            name
          }
          omittedValues: enumValues {
            name
          }
        }
      }
    ''';

      expect(await introspect(enumSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'trueValues': [
              {'name': 'NON_DEPRECATED'},
              {'name': 'DEPRECATED'},
              {'name': 'DEPRECATED_WITH_EMPTY_REASON'},
              {'name': 'ALSO_NON_DEPRECATED'},
            ],
            'falseValues': [
              {'name': 'NON_DEPRECATED'},
              {'name': 'ALSO_NON_DEPRECATED'},
            ],
            'omittedValues': [
              {'name': 'NON_DEPRECATED'},
              {'name': 'ALSO_NON_DEPRECATED'},
            ],
          },
        },
      });
    });

    test('identifies deprecated for input fields', () async {
      const source = '''

      {
        __type(name: "SomeInputObject") {
          inputFields(includeDeprecated: true) {
            name
            isDeprecated,
            deprecationReason
          }
        }
      }
    ''';

      expect(await introspect(inputSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'inputFields': [
              {
                'name': 'nonDeprecated',
                'isDeprecated': false,
                'deprecationReason': null,
              },
              {
                'name': 'deprecated',
                'isDeprecated': true,
                'deprecationReason': 'Removed in 1.0',
              },
              {
                'name': 'deprecatedWithEmptyReason',
                'isDeprecated': true,
                'deprecationReason': '',
              },
            ],
          },
        },
      });
    });

    test(
      'respects the includeDeprecated parameter for input fields',
      () async {
        const source = '''

      {
        __type(name: "SomeInputObject") {
          trueFields: inputFields(includeDeprecated: true) {
            name
          }
          falseFields: inputFields(includeDeprecated: false) {
            name
          }
          omittedFields: inputFields {
            name
          }
        }
      }
    ''';

        expect(await introspect(inputSchema(hasEmptyReason: false), source), {
          'data': {
            '__type': {
              'trueFields': [
                {'name': 'nonDeprecated'},
                {'name': 'deprecated'},
              ],
              'falseFields': [
                {'name': 'nonDeprecated'},
              ],
              'omittedFields': [
                {'name': 'nonDeprecated'},
              ],
            },
          },
        });
      },
    );
  });
}
