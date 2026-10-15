import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/validateInputValue-test.ts
// (validateInputLiteral); each case writes the literal as the argument of a
// field and compares the errors of the response. mapping/execution.csv says
// which tests are adapted or skipped, and why.
void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final testScalar = b.scalar<JsonValue>(
    'TestScalar',
    const ProbeScalarCodec(),
  );
  final anyScalar = b.scalar<JsonValue>('AnyScalar', const JsonScalarCodec());
  final testEnum = b.enumType<ProbeEnum>(
    'TestEnum',
    ProbeEnum.values,
    mapping: EnumValueMapping<ProbeEnum>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final foo = Arg('foo', b.int);
  final bar = Arg.optional('bar', b.int.nullable);
  final optional = Arg('optional', b.int, defaultValue: 42);
  final testObject = b.inputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [foo, bar, optional],
    decode: (v) => {
      'foo': v.get(foo),
      if (v.get(bar) case Present(:final value)) 'bar': value,
      'optional': v.get(optional),
    },
  );
  final sevenFoo = Arg('foo', anyScalar, defaultValue: JsonNumber(7));
  final seven = b.inputObject<Map<String, Object?>>(
    'DefaultSevenObject',
    fields: () => [sevenFoo],
    decode: (v) => {'foo': v.get(sevenFoo)},
  );
  final probe = InputProbe(b, [
    ('nonNull', 'Int!', b.int),
    ('scalar', 'TestScalar', testScalar.nullable),
    ('enumValue', 'TestEnum', testEnum.nullable),
    ('object', 'TestInputObject', testObject.nullable),
    ('sevenDefault', 'DefaultSevenObject', seven.nullable),
    ('list', '[Int]', b.inputList(b.int.nullable).nullable),
    ('listNonNull', '[Int!]', b.inputList(b.int).nullable),
    (
      'nestedList',
      '[[Int]]',
      b.inputList(b.inputList(b.int.nullable).nullable).nullable,
    ),
  ]);

  const wrongObject =
      'Expected value of type "TestInputObject" to be an object, found: ';
  const unknown =
      'Expected value of type "TestInputObject" not to include unknown field';
  const intVariable = r'($var: Int)';

  Future<List<String>> object(
    String text, {
    String definitions = '',
    Map<String, Object?> variables = const {},
  }) => probe.literalErrors(
    'object',
    text,
    definitions: definitions,
    variables: variables,
  );

  group('validateInputLiteral', () {
    test(
      'returns an error for null variables for non-nullable types',
      () async {
        expect(
          await probe.literalErrors(
            'nonNull',
            r'$var',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            probe.argumentError(
              'nonNull',
              r'Expected variable "$var" provided to non-null type "Int!" not to be null.',
            ),
          ],
        );
      },
    );

    group('for GraphQLNonNull', () {
      test('returns no error for non-null value', () async {
        expect(await probe.literalErrors('nonNull', '1'), isEmpty);
      });

      test('returns an error for null value', () async {
        expect(await probe.literalErrors('nonNull', 'null'), [
          probe.argumentError(
            'nonNull',
            'Expected value of non-null type "Int!" not to be null.',
          ),
        ]);
      });
    });

    group('for GraphQLScalar', () {
      test('returns no error for valid input', () async {
        expect(await probe.literalErrors('scalar', '{ value: 1 }'), isEmpty);
      });

      test('returns no error for null result', () async {
        expect(await probe.literalErrors('scalar', '{ value: null }'), isEmpty);
      });

      test('returns no error for NaN result', () async {
        expect(await probe.literalErrors('scalar', '{ value: NaN }'), isEmpty);
      });

      test('returns an error for undefined result', () async {
        expect(await probe.literalErrors('scalar', '{}'), [
          probe.argumentError('scalar', ProbeScalarCodec.missingValue),
        ]);
      });

      test('returns an error for undefined result', () async {
        expect(
          await probe.literalErrors(
            'scalar',
            '{ error: "Some error message." }',
          ),
          [probe.argumentError('scalar', 'Some error message.')],
        );
      });
    });

    group('for GraphQLEnum', () {
      test('returns no error for a known enum name', () async {
        expect(await probe.literalErrors('enumValue', 'FOO'), isEmpty);
        expect(await probe.literalErrors('enumValue', 'BAR'), isEmpty);
      });

      test('returns an error for unknown enum value', () async {
        expect(await probe.literalErrors('enumValue', 'UNKNOWN'), [
          probe.argumentError(
            'enumValue',
            'Value "UNKNOWN" does not exist in "TestEnum" enum.',
          ),
        ]);
      });

      test('returns an error for misspelled enum value', () async {
        expect(await probe.literalErrors('enumValue', 'foo'), [
          probe.argumentError(
            'enumValue',
            'Value "foo" does not exist in "TestEnum" enum. Did you mean the enum value "FOO"?',
          ),
        ]);
      });

      test(
        'returns an error for misspelled enum value (no suggestions)',
        () async {
          expect(
            await probe.literalErrors(
              'enumValue',
              'foo',
              isShowingSuggestions: false,
            ),
            [
              probe.argumentError(
                'enumValue',
                'Value "foo" does not exist in "TestEnum" enum.',
              ),
            ],
          );
        },
      );

      test('returns an error for incorrect value type', () async {
        Future<List<String>> literal(
          String text, {
          bool isShowingSuggestions = true,
        }) => probe.literalErrors(
          'enumValue',
          text,
          isShowingSuggestions: isShowingSuggestions,
        );

        expect(await literal('"FOO"'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: "FOO". Did you mean the enum value "FOO"?',
          ),
        ]);
        expect(await literal('"FOO"', isShowingSuggestions: false), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: "FOO".',
          ),
        ]);
        expect(await literal('"UNKNOWN"'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: "UNKNOWN".',
          ),
        ]);
        expect(await literal('123'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: 123.',
          ),
        ]);
        expect(await literal('{ field: "value" }'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: { field: "value" }.',
          ),
        ]);
      });
    });

    group('for GraphQLInputObject', () {
      test('returns no error for a valid input', () async {
        expect(await object('{ foo: 123 }'), isEmpty);
      });

      test('returns an error for a non-object type', () async {
        expect(await object('123'), [
          probe.argumentError('object', '${wrongObject}123.'),
        ]);
      });

      test('returns an error for an invalid field', () async {
        expect(await object('{ foo: 1.5 }'), [
          probe.argumentError(
            'object',
            'Int cannot represent non-integer value: 1.5',
            '.foo',
          ),
        ]);
      });

      test('returns multiple errors for multiple invalid fields', () async {
        // An argument reports its first problem only; graphql-js reports
        // every one.
        expect(await object('{ foo: "abc", bar: "def" }'), [
          probe.argumentError(
            'object',
            'Int cannot represent non-integer value: "abc"',
            '.foo',
          ),
        ]);
      });

      test('returns error for a missing required field', () async {
        expect(await object('{ bar: 123 }'), [
          probe.argumentError(
            'object',
            'Expected value of type "TestInputObject" to include required field "foo", found: { bar: 123 }.',
          ),
        ]);
      });

      test('returns error for an unknown field', () async {
        expect(await object('{ foo: 123, unknownField: 123 }'), [
          probe.argumentError(
            'object',
            '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
          ),
        ]);
      });

      test('returns error for a misspelled field', () async {
        expect(await object('{ foo: 123, bart: 123 }'), [
          probe.argumentError(
            'object',
            '$unknown "bart". Did you mean "bar"? Found: { foo: 123, bart: 123 }.',
          ),
        ]);
      });

      test('allows variables in an object, statically', () async {
        expect(
          await object(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 1},
          ),
          isEmpty,
        );
      });

      test('allows correct use of variables', () async {
        expect(
          await object(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 123},
          ),
          isEmpty,
        );
      });

      test('allows missing variables in an nullable field', () async {
        expect(await object(r'{ foo: 123, bar: $var }'), isEmpty);
        expect(
          await object(r'{ foo: 123, bar: $var }', definitions: intVariable),
          isEmpty,
        );
      });

      test('allows missing variables in an optional field', () async {
        expect(
          await object(
            r'{ foo: 123, optional: $var }',
            definitions: intVariable,
          ),
          isEmpty,
        );
      });

      test('errors on missing variable in an required field', () async {
        expect(
          await object(r'{ foo: $var }', definitions: intVariable),
          [
            probe.argumentError(
              'object',
              r'Expected variable "$var" provided to type "Int!" to provide a runtime value.',
              '.foo',
            ),
          ],
        );
      });

      test('errors on null variable in an non-null field', () async {
        expect(
          await object(
            r'{ foo: 123, optional: $var }',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            probe.argumentError(
              'object',
              r'Expected variable "$var" provided to non-null type "Int!" not to be null.',
              '.optional',
            ),
          ],
        );
      });
    });

    group('for GraphQLInputObject with default value', () {
      test('no error for no errors for valid input value', () async {
        expect(
          await probe.literalErrors('sevenDefault', '{ foo: 5 }'),
          isEmpty,
        );
      });

      test('no error for object with default value', () async {
        expect(await probe.literalErrors('sevenDefault', '{}'), isEmpty);
      });
    });

    group('for GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(await probe.literalErrors('list', '[1, 2, 3]'), isEmpty);
      });

      test('returns an error for an invalid input', () async {
        expect(await probe.literalErrors('list', '[1, "b", true, 4]'), [
          probe.argumentError(
            'list',
            'Int cannot represent non-integer value: "b"',
            '[1]',
          ),
        ]);
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.literalErrors('list', '42'), isEmpty);
      });

      test('returns an error for a non-list invalid value', () async {
        expect(await probe.literalErrors('list', '"INVALID"'), [
          probe.argumentError(
            'list',
            'Int cannot represent non-integer value: "INVALID"',
          ),
        ]);
      });

      test('no error for null for a null value', () async {
        expect(await probe.literalErrors('list', 'null'), isEmpty);
      });

      test('allows variables in a list, statically', () async {
        expect(
          await probe.literalErrors(
            'list',
            r'[1, $var, 3]',
            definitions: intVariable,
            variables: {'var': 2},
          ),
          isEmpty,
        );
      });

      test(
        'allows missing variables in a list (which coerce to null)',
        () async {
          expect(
            await probe.literalErrors(
              'list',
              r'[1, $var, 3]',
              definitions: intVariable,
            ),
            isEmpty,
          );
        },
      );

      test('errors on missing variables in a list of non-null', () async {
        expect(
          await probe.literalErrors(
            'listNonNull',
            r'[1, $var, 3]',
            definitions: intVariable,
          ),
          [
            probe.argumentError(
              'listNonNull',
              r'Expected variable "$var" provided to type "Int!" to provide a runtime value.',
              '[1]',
            ),
          ],
        );
      });

      test('errors on null variables in a list of non-null', () async {
        expect(
          await probe.literalErrors(
            'listNonNull',
            r'[1, $var, 3]',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            probe.argumentError(
              'listNonNull',
              r'Expected variable "$var" provided to non-null type "Int!" not to be null.',
              '[1]',
            ),
          ],
        );
      });
    });

    group('for nested GraphQLList', () {
      test('no error for a valid input', () async {
        expect(
          await probe.literalErrors('nestedList', '[[1], [2, 3]]'),
          isEmpty,
        );
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.literalErrors('nestedList', '42'), isEmpty);
      });

      test('no error for null for a null value', () async {
        expect(await probe.literalErrors('nestedList', 'null'), isEmpty);
      });

      test('no error for nested lists for nested non-list values', () async {
        expect(await probe.literalErrors('nestedList', '[1, 2, 3]'), isEmpty);
      });

      test('no error for nested null for nested null values', () async {
        expect(
          await probe.literalErrors('nestedList', '[42, [null], null]'),
          isEmpty,
        );
      });
    });
  });
}
