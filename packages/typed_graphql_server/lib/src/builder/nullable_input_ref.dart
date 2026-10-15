import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'named_type_def.dart';
import 'type_ref_wrapping.dart';

/// The nullable form of an input reference.
final class NullableInputRef<T>(InputRef<T> inner) implements InputRef<T?> {
  /// Wraps [inner].
  this;

  final InputRef<T> _inner = inner;

  @override
  final TypeRef typeRef = inner.typeRef.withoutNonNull;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  InputRef<T?> get nullable => this;

  @override
  T? adapt(Object? coerced) => coerced == null ? null : _inner.adapt(coerced);

  @override
  JsonValue jsonOf(T? value) =>
      value == null ? const JsonNull() : _inner.jsonOf(value);
}
