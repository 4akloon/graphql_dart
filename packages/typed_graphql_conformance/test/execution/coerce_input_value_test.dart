import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/coerceInputValue-test.ts
// (coerceInputValue); each case sends the value as a variable and reads what
// the field received. mapping/execution.csv says which tests are adapted or
// skipped, and why.
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
  final nested = Arg.optional('nestedObject', b.int.nullable);
  final testObject = b.inputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [foo, bar, nested],
    decode: (v) => {
      'foo': v.get(foo),
      if (v.get(bar) case Present(:final value)) 'bar': value,
      if (v.get(nested) case Present(:final value)) 'nestedObject': value,
    },
  );
  final oneOfFoo = Arg.optional('foo', b.int.nullable);
  final oneOfBar = Arg.optional('bar', b.int.nullable);
  final oneOf = b.oneOfInputObject<Map<String, Object?>>(
    'TestOneOfObject',
    fields: () => [oneOfFoo, oneOfBar],
    decode: (v) => {
      if (v.get(oneOfFoo) case Present(:final value)) 'foo': value,
      if (v.get(oneOfBar) case Present(:final value)) 'bar': value,
    },
  );
  final sevenFoo = Arg('foo', anyScalar, defaultValue: JsonNumber(7));
  final seven = b.inputObject<Map<String, Object?>>(
    'DefaultSevenObject',
    fields: () => [sevenFoo],
    decode: (v) => {'foo': v.get(sevenFoo)},
  );
  final length = Arg.optional('length', b.int.nullable);
  final listItem = b.inputObject<Map<String, Object?>>(
    'ListItemObject',
    fields: () => [length],
    decode: (v) => {
      if (v.get(length) case Present(:final value)) 'length': value,
    },
  );
  final probe = InputProbe(b, [
    ('nonNull', 'Int!', b.int),
    ('scalar', 'TestScalar', testScalar.nullable),
    ('enumValue', 'TestEnum', testEnum.nullable),
    ('object', 'TestInputObject', testObject.nullable),
    ('oneOf', 'TestOneOfObject', oneOf.nullable),
    ('sevenDefault', 'DefaultSevenObject', seven.nullable),
    ('list', '[Int]', b.inputList(b.int.nullable).nullable),
    ('objectList', '[ListItemObject]', b.inputList(listItem).nullable),
    (
      'nestedList',
      '[[Int]]',
      b.inputList(b.inputList(b.int.nullable).nullable).nullable,
    ),
  ]);

  group('coerceInputValue', () {
    group('for GraphQLNonNull', () {
      test('returns for a non-null value', () async {
        expect(await probe.value('nonNull', 1), '1');
      });

      test('invalid for undefined value', () async {
        expect(await probe.value('nonNull', null, isOmitted: true), isNull);
      });

      test('invalid for null value', () async {
        expect(await probe.value('nonNull', null), isNull);
      });
    });

    group('for GraphQLScalar', () {
      test('returns for valid input', () async {
        expect(
          await probe.value('scalar', {'value': 1}),
          '1',
        );
      });

      test('returns for null result', () async {
        expect(await probe.value('scalar', {'value': null}), 'null');
      });

      test('invalid for undefined result', () async {
        expect(await probe.value('scalar', <String, Object?>{}), isNull);
      });

      test('invalid for undefined result', () async {
        expect(
          await probe.value('scalar', {'error': 'Some error message'}),
          isNull,
        );
      });
    });

    group('for GraphQLEnum', () {
      test('returns no error for a known enum name', () async {
        expect(await probe.value('enumValue', 'FOO'), '"InternalFoo"');
        expect(await probe.value('enumValue', 'BAR'), '123456789');
      });

      test('invalid for misspelled enum value', () async {
        expect(await probe.value('enumValue', 'foo'), isNull);
      });

      test('invalid for incorrect value type', () async {
        expect(await probe.value('enumValue', 123), isNull);
        expect(await probe.value('enumValue', {'field': 'value'}), isNull);
      });
    });

    group('for GraphQLInputObject', () {
      test('returns no error for a valid input', () async {
        expect(await probe.value('object', {'foo': 123}), '{ foo: 123 }');
      });

      test('invalid for a non-object type', () async {
        expect(await probe.value('object', 123), isNull);
      });

      test('invalid for an invalid field', () async {
        expect(await probe.value('object', {'foo': 1.5}), isNull);
      });

      test('invalid for multiple invalid fields', () async {
        expect(
          await probe.value('object', {'foo': 'abc', 'bar': 'def'}),
          isNull,
        );
      });

      test('invalid for a missing required field', () async {
        expect(await probe.value('object', {'bar': 123}), isNull);
      });

      test('invalid for an unknown field', () async {
        expect(
          await probe.value('object', {'foo': 123, 'unknownField': 123}),
          isNull,
        );
      });

      test('ignores unknown fields with undefined values', () async {
        expect(await probe.value('object', {'foo': 123}), '{ foo: 123 }');
      });

      test('invalid when supplied with an array', () async {
        expect(
          await probe.value('object', [
            {'foo': 123},
            {'bar': 456},
          ]),
          isNull,
        );
      });

      test(
        'invalid when a nested input object is supplied with an array',
        () async {
          expect(
            await probe.value('object', {
              'foo': 123,
              'nested': [
                {'foo': 123},
                {'bar': 456},
              ],
            }),
            isNull,
          );
        },
      );
    });

    group('for GraphQLInputObject that isOneOf', () {
      test('returns for valid input', () async {
        expect(await probe.value('oneOf', {'foo': 123}), '{ foo: 123 }');
      });

      test('invalid if more than one field is specified', () async {
        expect(await probe.value('oneOf', {'foo': 123, 'bar': null}), isNull);
      });

      test('invalid if the one field is null', () async {
        expect(await probe.value('oneOf', {'bar': null}), isNull);
      });

      test('invalid for an invalid field', () async {
        expect(await probe.value('oneOf', {'foo': 1.5}), isNull);
      });

      test('invalid for an unknown field', () async {
        expect(
          await probe.value('oneOf', {'foo': 123, 'unknownField': 123}),
          isNull,
        );
      });
    });

    group('for GraphQLInputObject with default value', () {
      test('returns no errors for valid input value', () async {
        expect(await probe.value('sevenDefault', {'foo': 5}), '{ foo: 5 }');
      });

      test('returns object with default value', () async {
        expect(
          await probe.value('sevenDefault', <String, Object?>{}),
          '{ foo: 7 }',
        );
      });
    });

    group('for GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(await probe.value('list', [1, 2, 3]), '[1, 2, 3]');
      });

      test('invalid for an invalid input', () async {
        expect(await probe.value('list', [1, 'b', true, 4]), isNull);
      });

      test('returns a list for a non-list value', () async {
        expect(await probe.value('list', 42), '[42]');
      });

      test('returns a list for a non-list object value', () async {
        expect(
          await probe.value('objectList', {'length': 100500}),
          '[{ length: 100500 }]',
        );
      });

      test('invalid for a non-list invalid value', () async {
        expect(await probe.value('list', 'INVALID'), isNull);
      });

      test('returns null for a null value', () async {
        expect(await probe.value('list', null), 'null');
      });
    });

    group('for nested GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(
          await probe.value('nestedList', [
            [1],
            [2, 3],
          ]),
          '[[1], [2, 3]]',
        );
      });

      test('returns a list for a non-list value', () async {
        expect(await probe.value('nestedList', 42), '[[42]]');
      });

      test('returns null for a null value', () async {
        expect(await probe.value('nestedList', null), 'null');
      });

      test('returns nested lists for nested non-list values', () async {
        expect(await probe.value('nestedList', [1, 2, 3]), '[[1], [2], [3]]');
      });

      test('returns nested null for nested null values', () async {
        expect(
          await probe.value('nestedList', [
            42,
            [null],
            null,
          ]),
          '[[42], [null], null]',
        );
      });
    });
  });
}
