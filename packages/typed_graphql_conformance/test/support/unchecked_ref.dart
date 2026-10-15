import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A reference with the GraphQL type [typeRef] whatever the Dart value is:
/// graphql-js's tests make a non-null field return `null`, which a typed
/// resolver cannot do.
final class UncheckedRef implements OutputRef<Object?> {
  /// A reference of GraphQL type [typeRef] over the named type [namedType].
  UncheckedRef(this.typeRef, this.namedType);

  @override
  final TypeRef typeRef;

  @override
  final NamedTypeDef namedType;

  @override
  OutputRef<Object?> get nullable => throw UnimplementedError();
}
