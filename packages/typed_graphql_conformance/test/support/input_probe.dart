import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_port.dart';
import 'js_inspect.dart';

/// The `TestEnum` of graphql-js's input utility suites: `FOO` stands for the
/// JavaScript string `InternalFoo` and `BAR` for the number `123456789`.
enum ProbeEnum {
  /// `FOO`, whose JavaScript value is the string `InternalFoo`.
  foo('"InternalFoo"'),

  /// `BAR`, whose JavaScript value is the number `123456789`.
  bar('123456789');

  const ProbeEnum(this.shown);

  /// How `inspect` prints the JavaScript value.
  final String shown;

  @override
  String toString() => shown;
}

/// The `TestColor` of `coerceInput-test`: values that Dart enums cannot hold
/// (`null`, `NaN`) print as the JavaScript value would.
enum ProbeColor {
  /// `RED`, the number 1.
  red('1'),

  /// `GREEN`, the number 2.
  green('2'),

  /// `BLUE`, the number 3.
  blue('3'),

  /// `NULL`, whose value is `null`.
  nullValue('null'),

  /// `NAN`, whose value is `NaN`.
  nan('NaN'),

  /// `NO_CUSTOM_VALUE`, whose value is its name.
  noCustomValue('"NO_CUSTOM_VALUE"');

  const ProbeColor(this.shown);

  /// How `inspect` prints the JavaScript value.
  final String shown;

  @override
  String toString() => shown;
}

/// graphql-js's `TestScalar` of the input suites: it takes `{ value: x }` and
/// gives `x`; `{ error: "m" }` fails with `m` and a missing `value` fails.
final class ProbeScalarCodec implements ScalarCodec<JsonValue> {
  /// Creates the codec.
  const ProbeScalarCodec();

  /// The message of an object that has no `value`.
  static const String missingValue = 'TestScalar input has no value.';

  @override
  DecodeResult<JsonValue> decode(JsonValue json) => switch (json) {
    JsonObject(:final fields) => switch ((fields['error'], fields['value'])) {
      (JsonString(:final value), _) => DecodeFailure(value),
      (_, final JsonValue found) => DecodeSuccess(found),
      _ => const DecodeFailure(missingValue),
    },
    _ => const DecodeFailure(missingValue),
  };

  @override
  JsonValue encode(JsonValue value) => value;
}

/// A scalar that refuses every input, graphql-js's `ThrowScalar`.
final class RefusingScalarCodec implements ScalarCodec<JsonValue> {
  /// Creates the codec.
  const RefusingScalarCodec();

  @override
  DecodeResult<JsonValue> decode(JsonValue json) => const DecodeFailure('Test');

  @override
  JsonValue encode(JsonValue value) => value;
}

/// A schema whose query has one field per probed input type; each field
/// takes `input` and answers `inspect(input)`, or null when none was given.
/// This is how the ported `coerceInputValue` and `validateInputValue` suites
/// reach the coercion code: through [execute].
final class InputProbe {
  /// Builds the query type of [builder] from [fields]: a name, the type as
  /// written in a variable definition, and the input type.
  InputProbe(
    ExecutableSchemaBuilder<Object?> builder,
    List<(String, String, InputRef<Object?>)> fields,
  ) : _typeTexts = {for (final (name, text, _) in fields) name: text} {
    schema = builder.build(
      query: builder.object<Object?>(
        'Query',
        fields: (t) => [
          for (final (name, _, type) in fields) _field(builder, t, name, type),
        ],
      ),
    );
  }

  static const ExecutionPort _port = ExecutionPort();
  static const JsInspect _inspect = JsInspect();

  final Map<String, String> _typeTexts;

  /// The executable schema.
  late final ExecutableSchema<Object?> schema; // Set by the constructor body.

  FieldDef<Object?, Object?> _field(
    ExecutableSchemaBuilder<Object?> builder,
    FieldsBuilder<Object?, Object?> t,
    String name,
    InputRef<Object?> type,
  ) {
    final input = Arg.optional<Object?>('input', type);
    return t
        .field(name, builder.string.nullable, args: [input])
        .resolve(
          (_, args, context, info) => switch (args.get(input)) {
            Present(:final value) => _inspect(value),
            _ => null,
          },
        );
  }

  Future<Map<String, Object?>> _run(
    String query,
    Map<String, Object?>? variables,
    bool isShowingSuggestions,
  ) => _port.json(
    schema,
    query,
    variables: variables == null ? null : _port.variablesOf(variables),
    options: ExecutionOptions(
      maskErrors: false,
      includesSuggestions: isShowingSuggestions,
    ),
  );

  /// The message of every error of [response].
  List<String> messagesOf(Map<String, Object?> response) => [
    for (final error in (response['errors'] as List<Object?>? ?? const []))
      (error! as Map<String, Object?>)['message']! as String,
  ];

  String? _answer(Map<String, Object?> response, String field) {
    if (response['errors'] != null) {
      return null;
    }
    return (response['data']! as Map<String, Object?>)[field] as String?;
  }

  /// The variable response of [field] given [json] (nothing when
  /// [isOmitted]).
  Future<Map<String, Object?>> _valueResponse(
    String field,
    Object? json,
    bool isOmitted,
    bool isShowingSuggestions,
  ) => _run(
    'query (\$input: ${_typeTexts[field]}) { $field(input: \$input) }',
    isOmitted ? <String, Object?>{} : {'input': json},
    isShowingSuggestions,
  );

  /// `inspect` of what [field] received for the variable [json], or null when
  /// coercion failed (graphql-js's `undefined`).
  Future<String?> value(
    String field,
    Object? json, {
    bool isOmitted = false,
  }) async =>
      _answer(await _valueResponse(field, json, isOmitted, true), field);

  /// The errors of coercing the variable [json] for [field].
  Future<List<String>> valueErrors(
    String field,
    Object? json, {
    bool isOmitted = false,
    bool isShowingSuggestions = true,
  }) async => messagesOf(
    await _valueResponse(field, json, isOmitted, isShowingSuggestions),
  );

  Future<Map<String, Object?>> _literalResponse(
    String field,
    String literal,
    String definitions,
    Map<String, Object?>? variables,
    bool isShowingSuggestions,
  ) => _run(
    'query $definitions { $field(input: $literal) }',
    variables,
    isShowingSuggestions,
  );

  /// `inspect` of what [field] received for the [literal], or null when
  /// coercion failed. [definitions] is a variable definition list such as
  /// `($var: Int)`.
  Future<String?> literal(
    String field,
    String literal, {
    String definitions = '',
    Map<String, Object?> variables = const {},
  }) async => _answer(
    await _literalResponse(field, literal, definitions, variables, true),
    field,
  );

  /// The errors of coercing the [literal] for [field].
  Future<List<String>> literalErrors(
    String field,
    String literal, {
    String definitions = '',
    Map<String, Object?> variables = const {},
    bool isShowingSuggestions = true,
  }) async => messagesOf(
    await _literalResponse(
      field,
      literal,
      definitions,
      variables,
      isShowingSuggestions,
    ),
  );

  /// The message of a variable `$input` that has an invalid value at [path].
  String variableError(String message, [String path = '']) {
    final where = path.isEmpty ? '' : ' at $path';
    return 'Variable "\$input" has invalid value$where: $message';
  }

  /// The message of an argument `input` of [field] with an invalid value at
  /// [path].
  String argumentError(String field, String message, [String path = '']) {
    final where = path.isEmpty ? '' : ' at $path';
    return 'Argument "Query.$field(input:)" has invalid value$where: $message';
  }
}
