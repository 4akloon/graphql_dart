import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'output_ref.dart';
import 'type_ref_wrapping.dart';

/// A non-null list of items; its Dart value is an [Iterable] of [R].
final class OutputListRef<R>(OutputRef<R> item)
    implements OutputRef<Iterable<R>> {
  /// Makes the list type of [item].
  this;

  @override
  final TypeRef typeRef = item.typeRef.asNonNullList;

  @override
  final NamedTypeDef namedType = item.namedType;

  @override
  OutputRef<Iterable<R>?> get nullable => NullableOutputRef(this);
}
