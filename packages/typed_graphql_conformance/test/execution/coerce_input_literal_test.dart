import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/coerceInputValue-test.ts
// (coerceInputLiteral); each case writes the literal as the argument of a
// field and reads what the field received. mapping/execution.csv says which
// tests are adapted or skipped, and why.
void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final anyScalar = b.scalar<JsonValue>('AnyScalar', const JsonScalarCodec());
  final refusing = b.scalar<JsonValue>(
    'ThrowScalar',
    const RefusingScalarCodec(),
  );
  final color = b.enumType<ProbeColor>(
    'TestColor',
    ProbeColor.values,
    mapping: EnumValueMapping<ProbeColor>(
      nameOf: (value) => switch (value) {
        ProbeColor.red => 'RED',
        ProbeColor.green => 'GREEN',
        ProbeColor.blue => 'BLUE',
        ProbeColor.nullValue => 'NULL',
        ProbeColor.nan => 'NAN',
        ProbeColor.noCustomValue => 'NO_CUSTOM_VALUE',
      },
    ),
  );
  final defaultInt = Arg('int', b.int.nullable, defaultValue: 42);
  final defaultFloat = Arg('float', b.float.nullable, defaultValue: 3.14);
  final defaults = b.inputObject<Map<String, Object?>>(
    'TestDefaults',
    fields: () => [defaultInt, defaultFloat],
    decode: (v) => {
      'int': v.get(defaultInt),
      'float': v.get(defaultFloat),
    },
  );
  final intField = Arg('int', b.int.nullable, defaultValue: 42);
  final boolField = Arg.optional('bool', b.boolean.nullable);
  final requiredBool = Arg('requiredBool', b.boolean);
  final testInput = b.inputObject<Map<String, Object?>>(
    'TestInput',
    fields: () => [intField, boolField, requiredBool],
    decode: (v) => {
      'int': v.get(intField),
      if (v.get(boolField) case Present(:final value)) 'bool': value,
      'requiredBool': v.get(requiredBool),
    },
  );
  final a = Arg.optional('a', b.string.nullable);
  final bString = Arg.optional('b', b.string.nullable);
  final oneOf = b.oneOfInputObject<Map<String, Object?>>(
    'TestOneOfInput',
    fields: () => [a, bString],
    decode: (v) => {
      if (v.get(a) case Present(:final value)) 'a': value,
      if (v.get(bString) case Present(:final value)) 'b': value,
    },
  );
  final probe = InputProbe(b, [
    ('bool', 'Boolean', b.boolean.nullable),
    ('int', 'Int', b.int.nullable),
    ('float', 'Float', b.float.nullable),
    ('string', 'String', b.string.nullable),
    ('id', 'ID', b.id.nullable),
    ('anyScalar', 'AnyScalar', anyScalar.nullable),
    ('throwScalar', 'ThrowScalar', refusing.nullable),
    ('color', 'TestColor', color.nullable),
    ('colorNonNull', 'TestColor!', color),
    ('nonNullBool', 'Boolean!', b.boolean),
    ('listOfBool', '[Boolean]', b.inputList(b.boolean.nullable).nullable),
    ('listOfNonNullBool', '[Boolean!]', b.inputList(b.boolean).nullable),
    ('nonNullListOfBool', '[Boolean]!', b.inputList(b.boolean.nullable)),
    ('nonNullListOfNonNullBool', '[Boolean!]!', b.inputList(b.boolean)),
    ('defaults', 'TestDefaults', defaults.nullable),
    ('testInput', 'TestInput', testInput.nullable),
    ('oneOf', 'TestOneOfInput', oneOf.nullable),
  ]);

  group('coerceInputLiteral', () {
    test('converts according to input coercion rules', () async {
      expect(await probe.literal('bool', 'true'), 'true');
      expect(await probe.literal('bool', 'false'), 'false');
      expect(await probe.literal('int', '123'), '123');
      expect(await probe.literal('float', '123'), '123');
      expect(await probe.literal('float', '123.456'), '123.456');
      expect(await probe.literal('string', '"abc123"'), '"abc123"');
      expect(await probe.literal('id', '123456'), '"123456"');
      expect(await probe.literal('id', '"123456"'), '"123456"');
    });

    test('does not convert when input coercion rules reject a value', () async {
      expect(await probe.literal('bool', '123'), isNull);
      expect(await probe.literal('int', '123.456'), isNull);
      expect(await probe.literal('int', 'true'), isNull);
      expect(await probe.literal('int', '"123"'), isNull);
      expect(await probe.literal('float', '"123"'), isNull);
      expect(await probe.literal('string', '123'), isNull);
      expect(await probe.literal('string', 'true'), isNull);
      expect(await probe.literal('string', '123.456'), isNull);
      expect(await probe.literal('id', '123.456'), isNull);
    });

    test(
      'convert using coerceInputLiteral from a custom scalar type',
      () async {
        expect(await probe.literal('anyScalar', '"value"'), '"value"');
        expect(
          await probe.literal(
            'anyScalar',
            r'{ field: $var }',
            definitions: r'($var: String)',
            variables: {'var': 'value'},
          ),
          '{ field: "value" }',
        );
        expect(await probe.literal('throwScalar', 'value'), isNull);
      },
    );

    test('converts enum values according to input coercion rules', () async {
      expect(await probe.literal('color', 'RED'), '1');
      expect(await probe.literal('color', 'BLUE'), '3');
      expect(await probe.literal('color', '3'), isNull);
      expect(await probe.literal('color', '"BLUE"'), isNull);
      expect(await probe.literal('color', 'null'), 'null');
      expect(await probe.literal('color', 'NULL'), 'null');
      expect(await probe.literal('colorNonNull', 'NULL'), 'null');
      expect(await probe.literal('color', 'NAN'), 'NaN');
      expect(
        await probe.literal('color', 'NO_CUSTOM_VALUE'),
        '"NO_CUSTOM_VALUE"',
      );
    });

    test('coerces to null unless non-null', () async {
      expect(await probe.literal('bool', 'null'), 'null');
      expect(await probe.literal('nonNullBool', 'null'), isNull);
    });

    test('coerces lists of values', () async {
      expect(await probe.literal('listOfBool', 'true'), '[true]');
      expect(await probe.literal('listOfBool', '123'), isNull);
      expect(await probe.literal('listOfBool', 'null'), 'null');
      expect(
        await probe.literal('listOfBool', '[true, false]'),
        '[true, false]',
      );
      expect(await probe.literal('listOfBool', '[true, 123]'), isNull);
      expect(
        await probe.literal('listOfBool', '[true, null]'),
        '[true, null]',
      );
      expect(await probe.literal('listOfBool', '{ true: true }'), isNull);
    });

    test('coerces non-null lists of values', () async {
      const field = 'nonNullListOfBool';
      expect(await probe.literal(field, 'true'), '[true]');
      expect(await probe.literal(field, '123'), isNull);
      expect(await probe.literal(field, 'null'), isNull);
      expect(await probe.literal(field, '[true, false]'), '[true, false]');
      expect(await probe.literal(field, '[true, 123]'), isNull);
      expect(await probe.literal(field, '[true, null]'), '[true, null]');
    });

    test('coerces lists of non-null values', () async {
      const field = 'listOfNonNullBool';
      expect(await probe.literal(field, 'true'), '[true]');
      expect(await probe.literal(field, '123'), isNull);
      expect(await probe.literal(field, 'null'), 'null');
      expect(await probe.literal(field, '[true, false]'), '[true, false]');
      expect(await probe.literal(field, '[true, 123]'), isNull);
      expect(await probe.literal(field, '[true, null]'), isNull);
    });

    test('coerces non-null lists of non-null values', () async {
      const field = 'nonNullListOfNonNullBool';
      expect(await probe.literal(field, 'true'), '[true]');
      expect(await probe.literal(field, '123'), isNull);
      expect(await probe.literal(field, 'null'), isNull);
      expect(await probe.literal(field, '[true, false]'), '[true, false]');
      expect(await probe.literal(field, '[true, 123]'), isNull);
      expect(await probe.literal(field, '[true, null]'), isNull);
    });

    test('uses default values for unprovided fields', () async {
      expect(
        await probe.literal('defaults', '{}'),
        '{ int: 42, float: 3.14 }',
      );
    });

    test('coerces input objects according to input coercion rules', () async {
      Future<String?> input(String text) => probe.literal('testInput', text);
      Future<String?> oneOf(String text) => probe.literal('oneOf', text);

      expect(await input('null'), 'null');
      expect(await input('123'), isNull);
      expect(await input('[]'), isNull);
      expect(
        await input('{ requiredBool: true }'),
        '{ int: 42, requiredBool: true }',
      );
      expect(
        await input('{ int: null, requiredBool: true }'),
        '{ int: null, requiredBool: true }',
      );
      expect(
        await input('{ int: 123, requiredBool: false }'),
        '{ int: 123, requiredBool: false }',
      );
      expect(
        await input('{ bool: true, requiredBool: false }'),
        '{ int: 42, bool: true, requiredBool: false }',
      );
      expect(await input('{ int: true, requiredBool: true }'), isNull);
      expect(await input('{ requiredBool: null }'), isNull);
      expect(await input('{ bool: true }'), isNull);
      expect(await input('{ requiredBool: true, unknown: 123 }'), isNull);
      expect(await oneOf('{ a: "abc" }'), '{ a: "abc" }');
      expect(await oneOf('{ b: "def" }'), '{ b: "def" }');
      expect(await oneOf('{ a: "abc", b: null }'), isNull);
      expect(await oneOf('{ a: null }'), isNull);
      expect(await oneOf('{ a: 1 }'), isNull);
      expect(await oneOf('{ a: "abc", b: "def" }'), isNull);
      expect(await oneOf('{ a: "abc", c: "def" }'), isNull);
      expect(await oneOf('{}'), isNull);
      expect(await oneOf('{ c: "abc" }'), isNull);
    });

    test('accepts variable values assuming already coerced', () async {
      expect(await probe.literal('bool', r'$var'), isNull);
      expect(
        await probe.literal(
          'bool',
          r'$var',
          definitions: r'($var: Boolean)',
          variables: {'var': true},
        ),
        'true',
      );
      expect(
        await probe.literal(
          'bool',
          r'$var',
          definitions: r'($var: Boolean)',
          variables: {'var': null},
        ),
        'null',
      );
      expect(
        await probe.literal(
          'nonNullBool',
          r'$var',
          definitions: r'($var: Boolean)',
          variables: {'var': null},
        ),
        isNull,
      );
    });

    test('asserts variables are provided as items in lists', () async {
      expect(
        await probe.literal('listOfBool', r'[ $foo ]'),
        '[null]',
      );
      expect(await probe.literal('listOfNonNullBool', r'[ $foo ]'), isNull);
      expect(
        await probe.literal(
          'listOfNonNullBool',
          r'[ $foo ]',
          definitions: r'($foo: Boolean)',
          variables: {'foo': true},
        ),
        '[true]',
      );
      expect(
        await probe.literal(
          'listOfNonNullBool',
          r'$foo',
          definitions: r'($foo: Boolean)',
          variables: {'foo': true},
        ),
        // graphql-js returns the variable's value as it is; the executor
        // refuses a Boolean variable where a list is expected.
        isNull,
      );
      expect(
        await probe.literal(
          'listOfNonNullBool',
          r'$foo',
          definitions: r'($foo: [Boolean])',
          variables: {
            'foo': [true],
          },
        ),
        '[true]',
      );
    });

    test('omits input object fields for unprovided variables', () async {
      expect(
        await probe.literal(
          'testInput',
          r'{ int: $foo, bool: $foo, requiredBool: true }',
        ),
        '{ int: 42, requiredBool: true }',
      );
      expect(
        await probe.literal('testInput', r'{ requiredBool: $foo }'),
        isNull,
      );
      expect(
        await probe.literal(
          'testInput',
          r'{ requiredBool: $foo }',
          definitions: r'($foo: Boolean)',
          variables: {'foo': true},
        ),
        '{ int: 42, requiredBool: true }',
      );
    });

    test(
      'rejects multiple oneOf fields when one variable is unprovided',
      () async {
        expect(
          await probe.literal(
            'oneOf',
            r'{ a: $a, b: $b }',
            definitions: r'($a: String, $b: String)',
            variables: {'a': 'abc'},
          ),
          isNull,
        );
      },
    );

    test('rejects oneOf field when variable is null', () async {
      expect(
        await probe.literal(
          'oneOf',
          r'{ a: $a }',
          definitions: r'($a: String)',
          variables: {'a': null},
        ),
        isNull,
      );
    });

    test('preserves explicit null variables in input object fields', () async {
      expect(
        await probe.literal(
          'testInput',
          r'{ int: $foo, requiredBool: true }',
          definitions: r'($foo: Boolean)',
          variables: {'foo': null},
        ),
        '{ int: null, requiredBool: true }',
      );
    });
  });
}
