import 'package:typed_graphql/typed_graphql.dart';

/// The wrapping the refs apply to language type nodes.
extension TypeRefWrapping on TypeRef {
  /// This type without its non-null wrapper.
  TypeRef get withoutNonNull => switch (this) {
    NonNullType(:final type) => type,
    _ => this,
  };

  /// The non-null list whose items are this type.
  TypeRef get asNonNullList => NonNullType(ListType(this));
}
