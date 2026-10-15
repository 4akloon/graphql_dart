import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'named_type_def.dart';
import 'nullable_input_ref.dart';
import 'optional.dart';

/// The input reference of an `Arg.optional`: the schema type of [inner],
/// whose Dart value tells a given value from an absent one.
final class OptionalInputRef<T>(InputRef<T> inner)
    implements InputRef<Optional<T>> {
  /// Wraps [inner].
  this;

  final InputRef<T> _inner = inner;

  @override
  final TypeRef typeRef = inner.typeRef;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  InputRef<Optional<T>?> get nullable => NullableInputRef(this);

  @override
  Optional<T> adapt(Object? coerced) => Present(_inner.adapt(coerced));

  @override
  JsonValue jsonOf(Optional<T> value) => switch (value) {
    Present(:final value) => _inner.jsonOf(value),
    Absent() => throw StateError('An absent value has no JSON form.'),
  };
}
