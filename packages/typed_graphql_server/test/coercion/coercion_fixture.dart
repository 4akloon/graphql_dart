import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_environment.dart';
import 'package:typed_graphql_server/src/coercion/coercion_problem.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/coercion/input_coercion.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Color { red, green }

final class ComplexScalarCodec implements ScalarCodec<String> {
  const ComplexScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(value: 'ExternalValue') => const DecodeSuccess('InternalValue'),
    _ => const DecodeFailure('ComplexScalar must be ExternalValue'),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}

final class FaultyScalarCodec implements ScalarCodec<String> {
  const FaultyScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) =>
      const DecodeFailure('FaultyScalarErrorMessage');

  @override
  JsonValue encode(String value) => JsonString(value);
}

final class ThrowingScalarCodec implements ScalarCodec<String> {
  const ThrowingScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => throw StateError('codec bug');

  @override
  JsonValue encode(String value) => JsonString(value);
}

/// The schema the coercion tests run against, and parsing helpers.
final class CoercionFixture {
  CoercionFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final complex = b.scalar<String>(
      'ComplexScalar',
      const ComplexScalarCodec(),
    );
    final faulty = b.scalar<String>('FaultyScalar', const FaultyScalarCodec());
    final throwing = b.scalar<String>(
      'ThrowingScalar',
      const ThrowingScalarCodec(),
    );
    final color = b.enumType<Color>(
      'Color',
      Color.values,
      mapping: EnumValueMapping<Color>(nameOf: (value) => value.name),
    );
    final a = Arg('a', b.string.nullable);
    final list = Arg('b', b.inputList(b.string.nullable).nullable);
    final c = Arg('c', b.string);
    final d = Arg('d', complex.nullable);
    final e = Arg('e', faulty.nullable);
    final testInput = b.inputObject<Map<String, Object?>>(
      'TestInputObject',
      fields: () => [a, list, c, d, e],
      decode: (values) => {
        'a': values.get(a),
        'b': values.get(list),
        'c': values.get(c),
        'd': values.get(d),
        'e': values.get(e),
      },
    );
    final na = Arg('na', testInput);
    final nb = Arg('nb', b.string);
    final nested = b.inputObject<List<Object?>>(
      'TestNestedInputObject',
      fields: () => [na, nb],
      decode: (values) => [values.get(na), values.get(nb)],
    );
    final count = Arg('count', b.int, defaultValue: 5);
    final shade = Arg('shade', color, defaultValue: Color.green);
    final tags = Arg('tags', b.inputList(b.string.nullable).nullable);
    final defaulted = b.inputObject<Map<String, Object?>>(
      'Defaulted',
      fields: () => [count, shade, tags],
      decode: (values) => {
        'count': values.get(count),
        'shade': values.get(shade),
        'tags': values.get(tags),
      },
    );
    final lookupId = Arg('id', b.int.nullable);
    final lookupEmail = Arg('email', b.string.nullable);
    final lookup = b.oneOfInputObject<String>(
      'Lookup',
      fields: () => [lookupId, lookupEmail],
      decode: (values) => '${values.get(lookupId)}/${values.get(lookupEmail)}',
    );
    late final InputObjectDef<String> chain;
    chain = b.inputObject<String>(
      'Chain',
      fields: () => [Arg('next', chain.nullable)],
      decode: (values) => 'link',
    );
    final exploding = b.inputObject<String>(
      'Exploding',
      fields: () => [Arg('x', b.int.nullable)],
      decode: (_) => throw GraphQLException(
        'refused',
        extensions: JsonObject({'reason': const JsonString('policy')}),
      ),
    );
    final crashing = b.inputObject<String>(
      'Crashing',
      fields: () => [Arg('x', b.int.nullable)],
      decode: (_) => throw StateError('secret detail'),
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field(
              'probe',
              b.string.nullable,
              args: [
                Arg('input', testInput.nullable),
                Arg('nested', nested.nullable),
                Arg('defaulted', defaulted.nullable),
                Arg('lookup', lookup.nullable),
                Arg('chain', chain.nullable),
              ],
            )
            .resolve((parent, args, context, info) => null),
        t
            .field(
              'typed',
              b.string.nullable,
              args: [
                Arg('req', b.int),
                Arg('opt', b.string.nullable),
                Arg('limit', b.int, defaultValue: 10),
                Arg('ids', b.inputList(b.int).nullable),
                Arg('color', color.nullable),
                Arg('big', complex.nullable),
                Arg('flag', b.boolean.nullable),
              ],
            )
            .resolve((parent, args, context, info) => null),
        t
            .field(
              'more',
              b.string.nullable,
              args: [
                Arg('exploding', exploding.nullable),
                Arg('crashing', crashing.nullable),
                Arg('throwing', throwing.nullable),
              ],
            )
            .resolve((parent, args, context, info) => null),
      ],
    );
    final built = b.build(query: query);
    schema = built.schema.schema;
    environment = CoercionEnvironment(schema, built.bindings);
    coercion = InputCoercion(schema, built.bindings);
    hiddenSuggestions = InputCoercion(
      schema,
      built.bindings,
      includesSuggestions: false,
    );
  }

  late final Schema schema;
  late final CoercionEnvironment environment;
  late final InputCoercion coercion;
  late final InputCoercion hiddenSuggestions;

  TypeRef type(String text) =>
      switch (const Parser().parseTypeRef(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure() => throw ArgumentError('bad type $text'),
      };

  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    DecodeFailure(:final message) => throw ArgumentError(message),
  };

  /// The variable definitions of the only operation of [text].
  List<VariableDefinition> variables(String text) => [
    for (final definition
        in const Parser().parse(Source(text)).requireDocument().definitions)
      if (definition is OperationDefinition) ...definition.variableDefinitions,
  ];

  /// `where: message` of each problem.
  List<String> texts(List<CoercionProblem> problems) => [
    for (final problem in problems) '${problem.where}: ${problem.message}',
  ];

  /// Coerces a `Chain` value nested [depth] levels deep.
  CoercionResult chain(int depth) {
    JsonValue value = JsonObject({});
    for (var i = 0; i < depth; i++) {
      value = JsonObject({'next': value});
    }
    return coercion.coerceValue(value, type('Chain'));
  }
}
