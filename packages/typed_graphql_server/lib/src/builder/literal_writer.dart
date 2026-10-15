import 'package:typed_graphql/typed_graphql.dart';

import 'enum_type_def.dart';
import 'input_object_def.dart';
import 'named_type_def.dart';

/// Writes a [JsonValue] as a constant language [Value], like graphql-js's
/// `astFromValue`: an enum type gives an enum value, a list a list, an
/// input object an object, a number an `Int` when it is integral.
///
/// One difference: an `ID` default is always written as a string, where
/// graphql-js writes an integer-looking one as an `Int`; both coerce to the
/// same value.
///
/// Guided by the language type and the definitions of the named types it
/// meets. The definitions are used, not the assembled schema types, because
/// default values are part of the schema types being assembled. Recursion
/// depth follows the nesting of a default value written in code.
final class LiteralWriter {
  /// Creates a writer that looks named types up in [definitions].
  LiteralWriter(Iterable<NamedTypeDef> definitions)
    : _definitions = {
        for (final definition in definitions.toList().reversed)
          definition.name: definition,
      };

  // Lookup only: never iterated. Built from the end so the first definition
  // of a name wins, as in the schema.
  final Map<String, NamedTypeDef> _definitions;

  /// Writes [json] as a value of [type]; a null [type] writes the value by
  /// its shape alone.
  Value write(JsonValue json, TypeRef? type) {
    if (json is JsonNull) return const NullValue();
    return switch (type) {
      NonNullType(type: final inner) => write(json, inner),
      ListType(type: final item) => _list(json, item),
      NamedType(:final name) => _named(json, name.value),
      null => _byShape(json),
    };
  }

  Value _list(JsonValue json, TypeRef item) {
    // A single value stands for a list of one (spec 3.11 input coercion).
    if (json is! JsonArray) return write(json, item);
    return ListValue([for (final entry in json.items) write(entry, item)]);
  }

  Value _named(JsonValue json, String name) {
    final definition = _definitions[name];
    if (definition is EnumTypeDef<Enum> && json is JsonString) {
      return EnumValue(json.value);
    }
    if (definition is InputObjectDef<Object> && json is JsonObject) {
      return _object(json, definition);
    }
    return _byShape(json);
  }

  Value _object(JsonObject json, InputObjectDef<Object> definition) {
    final types = {
      for (final field in definition.fields) field.name: field.type.typeRef,
    };
    return ObjectValue([
      for (final MapEntry(:key, :value) in json.fields.entries)
        ObjectField(Name(key), write(value, types[key])),
    ]);
  }

  Value _byShape(JsonValue json) => switch (json) {
    JsonNull() => const NullValue(),
    JsonBool(:final value) => BooleanValue(value),
    JsonNumber() => _number(json),
    JsonString(:final value) => StringValue(value),
    JsonArray(:final items) => ListValue([
      for (final entry in items) _byShape(entry),
    ]),
    JsonObject(:final fields) => ObjectValue([
      for (final MapEntry(:key, :value) in fields.entries)
        ObjectField(Name(key), _byShape(value)),
    ]),
  };

  Value _number(JsonNumber json) {
    final number = json.value;
    if (number is int || json.asInt != null) {
      return IntValue('${number.toInt()}');
    }
    return FloatValue('$number');
  }
}
