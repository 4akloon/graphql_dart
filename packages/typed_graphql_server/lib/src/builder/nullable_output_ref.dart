import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';
import 'output_ref.dart';
import 'type_ref_wrapping.dart';

/// The nullable form of an output reference.
final class NullableOutputRef<R>(OutputRef<R> inner) implements OutputRef<R?> {
  /// Wraps [inner].
  this;

  @override
  final TypeRef typeRef = inner.typeRef.withoutNonNull;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  OutputRef<R?> get nullable => this;
}
