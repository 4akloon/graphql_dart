import 'package:typed_graphql/typed_graphql.dart';

import 'leaf_ref.dart';
import 'named_type_def.dart';
import 'nullable_leaf_ref.dart';

/// A scalar type: a name, a [ScalarCodec] and the Dart type [T] it holds.
///
/// It is its own output and input reference.
///
/// {@category builder}
final class ScalarTypeDef<T extends Object>(
  super.name,

  /// Reads and writes the values of this scalar.
  final ScalarCodec<T> codec, {
  super.description,

  /// The URL of the scalar's specification, written as `@specifiedBy`.
  final String? specifiedByUrl,
}) extends NamedTypeDef implements LeafRef<T> {
  /// Declares the scalar [name] over [codec].
  this;

  @override
  final TypeRef typeRef = NonNullType(NamedType(Name(name)));

  @override
  NamedTypeDef get namedType => this;

  @override
  LeafRef<T?> get nullable => NullableLeafRef(this);

  @override
  T adapt(Object? coerced) => coerced as T;

  @override
  JsonValue jsonOf(T value) => codec.encode(value);
}
