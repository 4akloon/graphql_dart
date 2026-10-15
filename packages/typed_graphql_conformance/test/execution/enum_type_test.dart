import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

enum _Color { red, green, blue }

enum _Complex { one, two }

enum _ThunkValues { a, b }

// Ported from the execution tests of graphql-js
// src/type/__tests__/enumType-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. A Dart enum has no internal value:
// where graphql-js's resolvers read or return the internal integers, these
// map the enum's index.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final color = b.enumType<_Color>(
    'Color',
    _Color.values,
    mapping: EnumValueMapping<_Color>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final complex = b.enumType<_Complex>(
    'Complex',
    _Complex.values,
    mapping: EnumValueMapping<_Complex>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final thunkValues = b.enumType<_ThunkValues>(
    'ThunkValues',
    _ThunkValues.values,
    mapping: EnumValueMapping<_ThunkValues>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final fromEnum = Arg('fromEnum', color.nullable);
  final fromInt = Arg('fromInt', b.int.nullable);
  final complexFromEnum = Arg(
    'fromEnum',
    complex,
    defaultValue: _Complex.one,
  );
  final provideGoodValue = Arg('provideGoodValue', b.boolean.nullable);
  final thunkFromEnum = Arg('fromEnum', thunkValues.nullable);
  final colorArg = Arg('color', color.nullable);
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field(
              'colorEnum',
              color.nullable,
              args: [fromEnum, fromInt],
            )
            .resolve((_, args, context, info) {
              final index = args.get(fromInt);
              return index == null ? args.get(fromEnum) : _Color.values[index];
            }),
        t
            .field('colorInt', b.int.nullable, args: [fromEnum])
            .resolve((_, args, context, info) => args.get(fromEnum)?.index),
        t
            .field(
              'complexEnum',
              complex.nullable,
              args: [complexFromEnum, provideGoodValue],
            )
            .resolve(
              (_, args, context, info) => args.get(provideGoodValue) == true
                  ? _Complex.two
                  : args.get(complexFromEnum),
            ),
        t
            .field(
              'complexEnumWithLegacyDefault',
              complex.nullable,
              args: [complexFromEnum],
            )
            .resolve((_, args, context, info) => args.get(complexFromEnum)),
        t
            .field(
              'thunkValuesString',
              b.string.nullable,
              args: [thunkFromEnum],
            )
            .resolve(
              (_, args, context, info) => args.get(thunkFromEnum)?.name,
            ),
      ],
    ),
    mutation: b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t
            .field('favoriteEnum', color.nullable, args: [colorArg])
            .resolve((_, args, context, info) => args.get(colorArg)),
      ],
    ),
  );

  Future<Map<String, Object?>> respond(
    String query, {
    Map<String, Object?>? variables,
    bool includesSuggestions = true,
  }) => port.respond(
    schema,
    query,
    variables: variables == null ? null : port.variablesOf(variables),
    includesSuggestions: includesSuggestions,
  );

  Map<String, Object?> failure(String message, int line, int column) => {
    'errors': [
      {
        'message': message,
        'locations': [
          {'line': line, 'column': column},
        ],
      },
    ],
  };

  group('Type System: Enum Values', () {
    test('accepts enum literals as input', () async {
      expect(await respond('{ colorInt(fromEnum: GREEN) }'), {
        'data': {'colorInt': 1},
      });
    });

    test('enum may be output type', () async {
      expect(await respond('{ colorEnum(fromInt: 1) }'), {
        'data': {'colorEnum': 'GREEN'},
      });
    });

    test('enum may be both input and output type', () async {
      expect(await respond('{ colorEnum(fromEnum: GREEN) }'), {
        'data': {'colorEnum': 'GREEN'},
      });
    });

    test('does not accept string literals', () async {
      expect(
        await respond('{ colorEnum(fromEnum: "GREEN") }'),
        failure(
          'Enum "Color" cannot represent non-enum value: "GREEN". '
          'Did you mean the enum value "GREEN"?',
          1,
          23,
        ),
      );
    });

    test('does not accept values not in the enum', () async {
      expect(
        await respond('{ colorEnum(fromEnum: GREENISH) }'),
        failure(
          'Value "GREENISH" does not exist in "Color" enum. '
          'Did you mean the enum value "GREEN"?',
          1,
          23,
        ),
      );
    });

    test('does not accept values not in the enum (no suggestions)', () async {
      expect(
        await respond(
          '{ colorEnum(fromEnum: GREENISH) }',
          includesSuggestions: false,
        ),
        failure('Value "GREENISH" does not exist in "Color" enum.', 1, 23),
      );
    });

    test('does not accept values with incorrect casing', () async {
      expect(
        await respond('{ colorEnum(fromEnum: green) }'),
        failure(
          'Value "green" does not exist in "Color" enum. '
          'Did you mean the enum value "GREEN" or "RED"?',
          1,
          23,
        ),
      );
    });

    test('does not accept internal value in place of enum literal', () async {
      expect(
        await respond('{ colorEnum(fromEnum: 1) }'),
        failure('Enum "Color" cannot represent non-enum value: 1.', 1, 23),
      );
    });

    test('does not accept enum literal in place of int', () async {
      expect(
        await respond('{ colorEnum(fromInt: GREEN) }'),
        failure('Int cannot represent non-integer value: GREEN', 1, 22),
      );
    });

    test('accepts JSON string as enum variable', () async {
      expect(
        await respond(
          r'query ($color: Color!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 'BLUE'},
        ),
        {
          'data': {'colorEnum': 'BLUE'},
        },
      );
    });

    test('accepts enum literals as input arguments to mutations', () async {
      expect(
        await respond(
          r'mutation ($color: Color!) { favoriteEnum(color: $color) }',
          variables: {'color': 'GREEN'},
        ),
        {
          'data': {'favoriteEnum': 'GREEN'},
        },
      );
    });

    test('does not accept internal value as enum variable', () async {
      expect(
        await respond(
          r'query ($color: Color!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 2},
        ),
        failure(
          r'Variable "$color" has invalid value: '
          'Enum "Color" cannot represent non-string value: 2.',
          1,
          8,
        ),
      );
    });

    test('does not accept string variables as enum input', () async {
      expect(
        await respond(
          r'query ($color: String!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 'BLUE'},
        ),
        {
          'errors': [
            {
              'message':
                  r'Variable "$color" of type "String!" used in position '
                  'expecting type "Color".',
              'locations': [
                {'line': 1, 'column': 8},
                {'line': 1, 'column': 47},
              ],
            },
          ],
        },
      );
    });

    test('does not accept internal value variable as enum input', () async {
      expect(
        await respond(
          r'query ($color: Int!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 2},
        ),
        {
          'errors': [
            {
              'message':
                  r'Variable "$color" of type "Int!" used in position '
                  'expecting type "Color".',
              'locations': [
                {'line': 1, 'column': 8},
                {'line': 1, 'column': 44},
              ],
            },
          ],
        },
      );
    });

    test('enum value may have an internal value of 0', () async {
      expect(
        await respond('''
      {
        colorEnum(fromEnum: RED)
        colorInt(fromEnum: RED)
      }
    '''),
        {
          'data': {'colorEnum': 'RED', 'colorInt': 0},
        },
      );
    });

    test('enum inputs may be nullable', () async {
      expect(
        await respond('''
      {
        colorEnum
        colorInt
      }
    '''),
        {
          'data': {'colorEnum': null, 'colorInt': null},
        },
      );
    });

    test('may be internally represented with complex values', () async {
      expect(
        await respond('''
      {
        first: complexEnum
        second: complexEnum(fromEnum: TWO)
        good: complexEnum(provideGoodValue: true)
      }
    '''),
        {
          'data': {'first': 'ONE', 'second': 'TWO', 'good': 'TWO'},
        },
      );
    });

    test(
      'may be internally represented with complex values using legacy internal defaults',
      () async {
        expect(
          await respond('''
      {
        complexEnumWithLegacyDefault
      }
    '''),
          {
            'data': {'complexEnumWithLegacyDefault': 'ONE'},
          },
        );
      },
    );

    test('may have values specified via a callback', () async {
      expect(await respond('{ thunkValuesString(fromEnum: B) }'), {
        'data': {'thunkValuesString': 'b'},
      });
    });
  });
}
