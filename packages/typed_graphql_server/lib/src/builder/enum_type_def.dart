import 'package:typed_graphql/typed_graphql.dart';

import 'enum_value_def.dart';
import 'leaf_ref.dart';
import 'named_type_def.dart';
import 'nullable_leaf_ref.dart';

/// An enum type that maps the Dart enum [E] to GraphQL value names and back.
///
/// It is its own output and input reference. The coerced value of an enum
/// input is the Dart value itself.
///
/// {@category builder}
final class EnumTypeDef<E extends Enum> extends NamedTypeDef
    implements LeafRef<E> {
  /// Declares the enum [name] with [values], in declaration order.
  EnumTypeDef(super.name, List<EnumValueDef<E>> values, {super.description})
    : values = List.unmodifiable(values),
      _namesByValue = {for (final entry in values) entry.value: entry.name},
      _valuesByName = {for (final entry in values) entry.name: entry.value},
      typeRef = NonNullType(NamedType(Name(name)));

  /// The values in declaration order (the order the schema lists them).
  final List<EnumValueDef<E>> values;

  // Lookup only: output follows [values], never these maps.
  final Map<E, String> _namesByValue;
  final Map<String, E> _valuesByName;

  /// The schema name of [value]; an [ArgumentError] when this enum does not
  /// declare it.
  String nameOf(E value) =>
      _namesByValue[value] ??
      (throw ArgumentError.value(value, 'value', 'is not a value of $name'));

  /// The value named [valueName] in the schema; null when there is none.
  E? valueNamed(String valueName) => _valuesByName[valueName];

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  LeafRef<E?> get nullable => NullableLeafRef(this);

  @override
  E adapt(Object? coerced) => coerced as E;

  @override
  JsonValue jsonOf(E value) => JsonString(nameOf(value));
}
