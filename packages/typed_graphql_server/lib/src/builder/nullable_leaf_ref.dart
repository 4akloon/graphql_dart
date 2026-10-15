import 'package:typed_graphql/typed_graphql.dart';

import 'leaf_ref.dart';
import 'named_type_def.dart';
import 'type_ref_wrapping.dart';

/// The nullable form of a scalar or enum reference.
final class NullableLeafRef<T>(LeafRef<T> inner) implements LeafRef<T?> {
  /// Wraps [inner].
  this;

  final LeafRef<T> _inner = inner;

  @override
  final TypeRef typeRef = inner.typeRef.withoutNonNull;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  LeafRef<T?> get nullable => this;

  @override
  T? adapt(Object? coerced) => coerced == null ? null : _inner.adapt(coerced);

  @override
  JsonValue jsonOf(T? value) =>
      value == null ? const JsonNull() : _inner.jsonOf(value);
}
