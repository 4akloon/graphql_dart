import 'package:typed_graphql/typed_graphql.dart';

/// The defaults of the Boolean variables of an operation, which decide a
/// fragment under `@include` or `@skip` when the variable is not sent
/// (spec §6 "Fragments").
final class FlagDefaults {
  /// Creates the reader.
  const FlagDefaults();

  /// The `true` or `false` default of each `Boolean` or `Boolean!` variable
  /// of [operation] that has one, by variable name, in definition order.
  Map<String, bool> of(OperationDefinition operation) => {
    for (final definition in operation.variableDefinitions)
      if (_isBoolean(definition.type))
        if (definition.defaultValue case BooleanValue(:final value))
          definition.variable.name.value: value,
  };

  bool _isBoolean(TypeRef type) => switch (type) {
    NonNullType(type: final inner) => _isBoolean(inner),
    NamedType(name: Name(value: 'Boolean')) => true,
    ListType() || NamedType() => false,
  };
}
