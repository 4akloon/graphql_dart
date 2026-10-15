import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_port.dart';
import 'js_inspect.dart';

/// The values of graphql-js's `TestEnum`, which has JavaScript values that
/// Dart enums cannot hold (`null`, `NaN`, `false`): each prints as the
/// JavaScript value would.
enum TestEnumValue {
  /// `NULL`, whose JavaScript value is `null`.
  nullValue('null'),

  /// `NAN`, whose JavaScript value is `NaN`.
  nan('NaN'),

  /// `FALSE`, whose JavaScript value is `false`.
  falseValue('false'),

  /// `CUSTOM`, whose JavaScript value is the string `custom value`.
  custom('"custom value"'),

  /// `DEFAULT_VALUE`, which has no value of its own: its name is the value.
  defaultValue('"DEFAULT_VALUE"');

  const TestEnumValue(this.shown);

  /// How `inspect` prints the JavaScript value.
  final String shown;

  @override
  String toString() => shown;
}

/// Any JSON, the codec of graphql-js's `JSONScalar`.
final class JsonScalarCodec implements ScalarCodec<JsonValue> {
  /// Creates the codec.
  const JsonScalarCodec();

  @override
  DecodeResult<JsonValue> decode(JsonValue json) => DecodeSuccess(json);

  @override
  JsonValue encode(JsonValue value) => value;
}

/// graphql-js's `ComplexScalar`: only `ExternalValue` is a value, and it
/// becomes `InternalValue`.
final class ComplexScalarCodec implements ScalarCodec<String> {
  /// Creates the codec.
  const ComplexScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(value: 'ExternalValue') => const DecodeSuccess('InternalValue'),
    _ => const DecodeFailure('ComplexScalar must be ExternalValue'),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}

/// graphql-js's `FaultyScalar`: every input is refused with one message.
final class FaultyScalarCodec implements ScalarCodec<String> {
  /// Creates the codec.
  const FaultyScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) =>
      const DecodeFailure('FaultyScalarErrorMessage');

  @override
  JsonValue encode(String value) => JsonString(value);
}

/// The `TestType` schema of graphql-js's `variables-test.ts`: every field
/// answers `inspect(args.input)`, or null when `input` was not given.
final class VariablesSchema {
  /// Builds the schema.
  VariablesSchema() {
    final b = _builder;
    final complex = b.scalar<String>(
      'ComplexScalar',
      const ComplexScalarCodec(),
    );
    final faulty = b.scalar<String>('FaultyScalar', const FaultyScalarCodec());
    final json = b.scalar<JsonValue>('JSONScalar', const JsonScalarCodec());
    final testEnum = b.enumType<TestEnumValue>(
      'TestEnum',
      TestEnumValue.values,
      mapping: EnumValueMapping<TestEnumValue>(
        nameOf: (value) => switch (value) {
          TestEnumValue.nullValue => 'NULL',
          TestEnumValue.nan => 'NAN',
          TestEnumValue.falseValue => 'FALSE',
          TestEnumValue.custom => 'CUSTOM',
          TestEnumValue.defaultValue => 'DEFAULT_VALUE',
        },
      ),
    );
    final objectA = Arg.optional('a', b.string.nullable);
    final objectB = Arg.optional(
      'b',
      b.inputList(b.string.nullable).nullable,
    );
    final objectC = Arg('c', b.string);
    final objectD = Arg.optional('d', complex.nullable);
    final objectE = Arg.optional('e', faulty.nullable);
    final testInput = b.inputObject<Map<String, Object?>>(
      'TestInputObject',
      fields: () => [objectA, objectB, objectC, objectD, objectE],
      decode: (values) => {
        if (values.get(objectA) case Present(:final value)) 'a': value,
        if (values.get(objectB) case Present(:final value)) 'b': value,
        'c': values.get(objectC),
        if (values.get(objectD) case Present(:final value)) 'd': value,
        if (values.get(objectE) case Present(:final value)) 'e': value,
      },
    );
    final oneOfA = Arg.optional('a', b.string.nullable);
    final oneOfB = Arg.optional('b', b.string.nullable);
    final testOneOf = b.oneOfInputObject<Map<String, Object?>>(
      'TestOneOfInputObject',
      fields: () => [oneOfA, oneOfB],
      decode: (values) => {
        if (values.get(oneOfA) case Present(:final value)) 'a': value,
        if (values.get(oneOfB) case Present(:final value)) 'b': value,
      },
    );
    final nestedNa = Arg('na', testInput);
    final nestedNb = Arg('nb', b.string);
    final testNested = b.inputObject<Map<String, Object?>>(
      'TestNestedInputObject',
      fields: () => [nestedNa, nestedNb],
      decode: (values) => {
        'na': values.get(nestedNa),
        'nb': values.get(nestedNb),
      },
    );
    final nestedType = b.object<Object?>(
      'NestedType',
      fields: (t) => [echo(t, 'echo', b.string.nullable)],
    );
    final nonNullString = Arg('input', b.string);
    final prototypeArg = Arg.optional('toString', b.string.nullable);
    final defaulted = Arg(
      'input',
      b.string.nullable,
      defaultValue: 'Hello World',
    );
    final nonNullDefaulted = Arg(
      'input',
      b.string,
      defaultValue: 'Hello World',
    );
    final testType = b.object<Object?>(
      'TestType',
      fields: (t) => [
        echo(t, 'fieldWithEnumInput', testEnum.nullable),
        echo(t, 'fieldWithNonNullableEnumInput', testEnum),
        echo(t, 'fieldWithObjectInput', testInput.nullable),
        echo(t, 'fieldWithOneOfObjectInput', testOneOf.nullable),
        echo(t, 'fieldWithNullableStringInput', b.string.nullable),
        t
            .field(
              'fieldWithNonNullableStringInput',
              b.string.nullable,
              args: [nonNullString],
            )
            .resolve(
              (_, args, context, info) => inspect(args.get(nonNullString)),
            ),
        t
            .field(
              'fieldWithDefaultArgumentValue',
              b.string.nullable,
              args: [defaulted],
            )
            .resolve((_, args, context, info) => inspect(args.get(defaulted))),
        t
            .field(
              'fieldWithNonNullableStringInputAndDefaultArgumentValue',
              b.string.nullable,
              args: [nonNullDefaulted],
            )
            .resolve(
              (_, args, context, info) => inspect(args.get(nonNullDefaulted)),
            ),
        echo(t, 'fieldWithNestedInputObject', testNested.nullable),
        echo(t, 'fieldWithJSONScalarInput', json.nullable),
        t
            .field(
              'fieldWithPrototypeNamedArgument',
              b.string.nullable,
              args: [prototypeArg],
            )
            .resolve(
              (_, args, context, info) => switch (args.get(prototypeArg)) {
                Present(:final value) => inspect(value),
                _ => 'missing',
              },
            ),
        echo(t, 'list', b.inputList(b.string.nullable).nullable),
        t.field('nested', nestedType).pure((_) => Object()),
        echo(t, 'nnList', b.inputList(b.string.nullable)),
        echo(t, 'listNN', b.inputList(b.string).nullable),
        echo(t, 'nnListNN', b.inputList(b.string)),
      ],
    );
    schema = b.build(query: testType);
  }

  static const ExecutionPort _port = ExecutionPort();

  /// graphql-js's `inspect`, which the fields print their input with.
  static const JsInspect inspect = JsInspect();

  final ExecutableSchemaBuilder<Object?> _builder =
      ExecutableSchemaBuilder<Object?>();

  /// The executable schema.
  late final ExecutableSchema<Object?> schema;

  /// graphql-js's `executeSync` of [query] with [variables] (the object
  /// `jsonDecode` would give), as response JSON.
  Future<Map<String, Object?>> execute(
    String query, {
    Map<String, Object?>? variables,
    ExecutionOptions options = ExecutionPort.unmasked,
  }) => _port.json(
    schema,
    query,
    variables: variables == null ? null : _port.variablesOf(variables),
    options: options,
  );

  /// A field `name` with one optional argument `input` of [type], which
  /// answers `inspect(input)` or null when `input` was not given.
  FieldDef<Object?, Object?> echo(
    FieldsBuilder<Object?, Object?> t,
    String name,
    InputRef<Object?> type,
  ) {
    final input = Arg.optional<Object?>('input', type);
    return t
        .field(name, _builder.string.nullable, args: [input])
        .resolve(
          (_, args, context, info) => switch (args.get(input)) {
            Present(:final value) => inspect(value),
            _ => null,
          },
        );
  }
}
