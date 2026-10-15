import 'enum_value_def.dart';

/// How the values of a Dart enum appear in the schema: their names,
/// descriptions and deprecations.
///
/// Passed to `ExecutableSchemaBuilder.enumType`; the defaults are
/// [Enum.name] and no description or deprecation.
///
/// {@category builder}
final class const EnumValueMapping<E extends Enum>({
  /// The schema name of a value; null means [Enum.name].
  final String Function(E value)? nameOf,

  /// The description of a value, null for none.
  final String? Function(E value)? descriptionOf,

  /// The deprecation reason of a value, null when it is not deprecated.
  final String? Function(E value)? deprecationReasonOf,
}) {
  /// Describes how enum values appear in the schema.
  this;

  /// The definition of [value] under this mapping.
  EnumValueDef<E> define(E value) => EnumValueDef(
    value,
    nameOf == null ? value.name : nameOf!(value),
    description: descriptionOf?.call(value),
    deprecationReason: deprecationReasonOf?.call(value),
  );
}
