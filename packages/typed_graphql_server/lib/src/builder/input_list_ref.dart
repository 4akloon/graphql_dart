import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'named_type_def.dart';
import 'nullable_input_ref.dart';
import 'type_ref_wrapping.dart';

/// A non-null list of items; its Dart value is a `List<T>`.
final class InputListRef<T>(InputRef<T> item) implements InputRef<List<T>> {
  /// Makes the list type of [item].
  this;

  final InputRef<T> _item = item;

  @override
  final TypeRef typeRef = item.typeRef.asNonNullList;

  @override
  final NamedTypeDef namedType = item.namedType;

  @override
  InputRef<List<T>?> get nullable => NullableInputRef(this);

  @override
  List<T> adapt(Object? coerced) {
    // The coercion wraps a single value where a list is expected (spec
    // 3.11), so only a real list reaches this method.
    final items = coerced as List<Object?>;
    return <T>[for (final element in items) _item.adapt(element)];
  }

  @override
  JsonValue jsonOf(List<T> value) =>
      JsonArray([for (final element in value) _item.jsonOf(element)]);
}
