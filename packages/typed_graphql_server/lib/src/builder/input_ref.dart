import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';

/// A GraphQL input type decoded to the Dart value [T] (spec 3.3).
///
/// Non-null by default; [nullable] gives the nullable form.
///
/// {@category builder}
abstract interface class InputRef<T> {
  /// The type as a language node, such as `NonNullType(NamedType(...))`.
  TypeRef get typeRef;

  /// The named type this reference ends in, through lists and nullability.
  NamedTypeDef get namedType;

  /// This type without the non-null wrapper.
  InputRef<T?> get nullable;

  /// The typed value of [coerced], a value the input coercion produced.
  ///
  /// Lists are rebuilt as a real `List<X>` (generics are reified, so a
  /// `List<Object?>` would not do) and leaves are cast. A value of the wrong
  /// type is a `TypeError`: coercion already checked it, so it is a bug.
  T adapt(Object? coerced);

  /// The JSON form of [value], used to write default values: a leaf goes
  /// through its codec or its enum name, a list becomes an array and null
  /// becomes [JsonNull]. A value the type cannot write is an [ArgumentError]
  /// or a [StateError].
  JsonValue jsonOf(T value);
}
