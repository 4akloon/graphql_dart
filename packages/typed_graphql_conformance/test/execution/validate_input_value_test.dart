import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/validateInputValue-test.ts
// (validateInputValue); each case sends the value as a variable and compares
// the errors of the response. mapping/execution.csv says which tests are
// adapted or skipped, and why.
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
  // Late because the type refers to itself: assigned below, read by `fields`
  // only when the schema is built.
  late final Arg<Optional<Map<String, Object?>?>> nested;
  final testObject = b.inputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [foo, bar, nested],
    decode: (v) => {
      'foo': v.get(foo),
      if (v.get(bar) case Present(:final value)) 'bar': value,
      if (v.get(nested) case Present(:final value)) 'nested': value,
    },
  );
  nested = Arg.optional('nested', testObject.nullable);
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
    (
      'nestedList',
      '[[Int]]',
      b.inputList(b.inputList(b.int.nullable).nullable).nullable,
    ),
  ]);

  final ob = ExecutableSchemaBuilder<Object?>();
  final oneOfFoo = Arg.optional('foo', ob.int.nullable);
  final oneOfBar = Arg.optional('bar', ob.int.nullable);
  final oneOf = ob.oneOfInputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [oneOfFoo, oneOfBar],
    decode: (v) => {
      if (v.get(oneOfFoo) case Present(:final value)) 'foo': value,
      if (v.get(oneOfBar) case Present(:final value)) 'bar': value,
    },
  );
  final oneOfProbe = InputProbe(ob, [
    ('oneOf', 'TestInputObject', oneOf.nullable),
  ]);
  const badOneOf =
      'Within OneOf Input Object type "TestInputObject", exactly one field must be specified, and the value for that field must be non-null.';
  const wrongObject =
      'Expected value of type "TestInputObject" to be an object, found: ';
  const unknown =
      'Expected value of type "TestInputObject" not to include unknown field';

  group('validateInputValue', () {
    group('for GraphQLNonNull', () {
      test('returns no error for non-null value', () async {
        expect(await probe.valueErrors('nonNull', 1), isEmpty);
      });

      test('returns an error for undefined value', () async {
        expect(await probe.valueErrors('nonNull', null, isOmitted: true), [
          probe.variableError(
            'Expected a value of non-null type "Int!" to be provided.',
          ),
        ]);
      });

      test('returns an error for null value', () async {
        expect(await probe.valueErrors('nonNull', null), [
          probe.variableError(
            'Expected value of non-null type "Int!" not to be null.',
          ),
        ]);
      });
    });

    group('for GraphQLScalar', () {
      test('returns no error for valid input', () async {
        expect(await probe.valueErrors('scalar', {'value': 1}), isEmpty);
      });

      test('returns no error for null result', () async {
        expect(await probe.valueErrors('scalar', {'value': null}), isEmpty);
      });

      test('returns an error for undefined result', () async {
        expect(await probe.valueErrors('scalar', <String, Object?>{}), [
          probe.variableError(ProbeScalarCodec.missingValue),
        ]);
      });

      test('returns an error for undefined result', () async {
        expect(
          await probe.valueErrors('scalar', {'error': 'Some error message.'}),
          [probe.variableError('Some error message.')],
        );
      });
    });

    group('for GraphQLEnum', () {
      test('returns no error for a known enum name', () async {
        expect(await probe.valueErrors('enumValue', 'FOO'), isEmpty);
        expect(await probe.valueErrors('enumValue', 'BAR'), isEmpty);
      });

      test('returns an error for unknown enum value', () async {
        expect(await probe.valueErrors('enumValue', 'UNKNOWN'), [
          probe.variableError(
            'Value "UNKNOWN" does not exist in "TestEnum" enum.',
          ),
        ]);
      });

      test('returns an error for misspelled enum value', () async {
        expect(await probe.valueErrors('enumValue', 'foo'), [
          probe.variableError(
            'Value "foo" does not exist in "TestEnum" enum. Did you mean the enum value "FOO"?',
          ),
        ]);
      });

      test(
        'returns an error for misspelled enum value (no suggestions)',
        () async {
          expect(
            await probe.valueErrors(
              'enumValue',
              'foo',
              isShowingSuggestions: false,
            ),
            [
              probe.variableError(
                'Value "foo" does not exist in "TestEnum" enum.',
              ),
            ],
          );
        },
      );

      test('returns an error for incorrect value type', () async {
        expect(await probe.valueErrors('enumValue', 123), [
          probe.variableError(
            'Enum "TestEnum" cannot represent non-string value: 123.',
          ),
        ]);
        expect(await probe.valueErrors('enumValue', {'field': 'value'}), [
          probe.variableError(
            'Enum "TestEnum" cannot represent non-string value: { field: "value" }.',
          ),
        ]);
      });
    });

    group('for GraphQLInputObject', () {
      test('returns no error for a valid input', () async {
        expect(await probe.valueErrors('object', {'foo': 123}), isEmpty);
      });

      test('returns an error for a non-object type', () async {
        expect(await probe.valueErrors('object', 123), [
          probe.variableError('${wrongObject}123.'),
        ]);
      });

      test('returns an error for an invalid field', () async {
        expect(await probe.valueErrors('object', {'foo': 1.5}), [
          probe.variableError(
            'Int cannot represent non-integer value: 1.5',
            '.foo',
          ),
        ]);
      });

      test('returns multiple errors for multiple invalid fields', () async {
        expect(
          await probe.valueErrors('object', {'foo': 'abc', 'bar': 'def'}),
          [
            probe.variableError(
              'Int cannot represent non-integer value: "abc"',
              '.foo',
            ),
            probe.variableError(
              'Int cannot represent non-integer value: "def"',
              '.bar',
            ),
          ],
        );
      });

      test('returns error for a missing required field', () async {
        expect(await probe.valueErrors('object', {'bar': 123}), [
          probe.variableError(
            'Expected value of type "TestInputObject" to include required field "foo", found: { bar: 123 }.',
          ),
        ]);
      });

      test('returns error for an unknown field', () async {
        expect(
          await probe.valueErrors('object', {'foo': 123, 'unknownField': 123}),
          [
            probe.variableError(
              '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
            ),
          ],
        );
      });

      test('ignores unknown fields with undefined values', () async {
        expect(await probe.valueErrors('object', {'foo': 123}), isEmpty);
      });

      test('returns error when supplied with an array', () async {
        expect(
          await probe.valueErrors('object', [
            {'foo': 123},
            {'bar': 456},
          ]),
          [
            probe.variableError(
              '$wrongObject[{ foo: 123 }, { bar: 456 }].',
            ),
          ],
        );
      });

      test(
        'returns error when a nested input object is supplied with an array',
        () async {
          expect(
            await probe.valueErrors('object', {
              'foo': 123,
              'nested': [
                {'foo': 123},
                {'bar': 456},
              ],
            }),
            [
              probe.variableError(
                '$wrongObject[{ foo: 123 }, { bar: 456 }].',
                '.nested',
              ),
            ],
          );
        },
      );

      test('returns error for a misspelled field', () async {
        expect(await probe.valueErrors('object', {'foo': 123, 'bart': 123}), [
          probe.variableError(
            '$unknown "bart". Did you mean "bar"? Found: { foo: 123, bart: 123 }.',
          ),
        ]);
      });

      test('returns error for a misspelled field (no suggestions)', () async {
        expect(
          await probe.valueErrors(
            'object',
            {'foo': 123, 'bart': 123},
            isShowingSuggestions: false,
          ),
          [
            probe.variableError(
              '$unknown "bart", found: { foo: 123, bart: 123 }.',
            ),
          ],
        );
      });
    });

    group('for GraphQLInputObject with default value', () {
      test('no error for no errors for valid input value', () async {
        expect(await probe.valueErrors('sevenDefault', {'foo': 5}), isEmpty);
      });

      test('no error for object with default value', () async {
        expect(
          await probe.valueErrors('sevenDefault', <String, Object?>{}),
          isEmpty,
        );
      });
    });

    group('for GraphQLInputObject that isOneOf', () {
      test('no error for a valid input', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'foo': 123}), isEmpty);
      });

      test('returns error if more than one field is specified', () async {
        expect(
          await oneOfProbe.valueErrors('oneOf', {'foo': 123, 'bar': null}),
          [oneOfProbe.variableError(badOneOf)],
        );
      });

      test('does not count undefined keys as provided', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'foo': 123}), isEmpty);
      });

      test('returns error if the one field is null', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'bar': null}), [
          oneOfProbe.variableError(badOneOf, '.bar'),
        ]);
      });

      test('returns error for an invalid field', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'foo': 1.5}), [
          oneOfProbe.variableError(
            'Int cannot represent non-integer value: 1.5',
            '.foo',
          ),
        ]);
      });

      test('returns multiple errors for multiple invalid fields', () async {
        expect(
          await oneOfProbe.valueErrors('oneOf', {'foo': 'abc', 'bar': 'def'}),
          [
            oneOfProbe.variableError(
              'Int cannot represent non-integer value: "abc"',
              '.foo',
            ),
            oneOfProbe.variableError(
              'Int cannot represent non-integer value: "def"',
              '.bar',
            ),
            oneOfProbe.variableError(badOneOf),
          ],
        );
      });

      test('returns error for an unknown field', () async {
        expect(
          await oneOfProbe.valueErrors('oneOf', {
            'foo': 123,
            'unknownField': 123,
          }),
          [
            oneOfProbe.variableError(
              '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
            ),
          ],
        );
      });

      test('returns error for a misspelled field', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'bart': 123}), [
          oneOfProbe.variableError(
            '$unknown "bart". Did you mean "bar"? Found: { bart: 123 }.',
          ),
          oneOfProbe.variableError(badOneOf),
        ]);
      });

      test('returns error for a misspelled field (no suggestions)', () async {
        expect(
          await oneOfProbe.valueErrors(
            'oneOf',
            {'bart': 123},
            isShowingSuggestions: false,
          ),
          [
            oneOfProbe.variableError(
              '$unknown "bart", found: { bart: 123 }.',
            ),
            oneOfProbe.variableError(badOneOf),
          ],
        );
      });
    });

    group('for GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(await probe.valueErrors('list', [1, 2, 3]), isEmpty);
      });

      test('returns an error for an invalid input', () async {
        expect(await probe.valueErrors('list', [1, 'b', true, 4]), [
          probe.variableError(
            'Int cannot represent non-integer value: "b"',
            '[1]',
          ),
          probe.variableError(
            'Int cannot represent non-integer value: true',
            '[2]',
          ),
        ]);
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.valueErrors('list', 42), isEmpty);
      });

      test('returns an error for a non-list invalid value', () async {
        expect(await probe.valueErrors('list', 'INVALID'), [
          probe.variableError(
            'Int cannot represent non-integer value: "INVALID"',
          ),
        ]);
      });

      test('no error for null for a null value', () async {
        expect(await probe.valueErrors('list', null), isEmpty);
      });
    });

    group('for nested GraphQLList', () {
      test('no error for a valid input', () async {
        expect(
          await probe.valueErrors('nestedList', [
            [1],
            [2, 3],
          ]),
          isEmpty,
        );
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.valueErrors('nestedList', 42), isEmpty);
      });

      test('no error for null for a null value', () async {
        expect(await probe.valueErrors('nestedList', null), isEmpty);
      });

      test('no error for nested lists for nested non-list values', () async {
        expect(await probe.valueErrors('nestedList', [1, 2, 3]), isEmpty);
      });

      test('no error for nested null for nested null values', () async {
        expect(
          await probe.valueErrors('nestedList', [
            42,
            [null],
            null,
          ]),
          isEmpty,
        );
      });
    });
  });
}
