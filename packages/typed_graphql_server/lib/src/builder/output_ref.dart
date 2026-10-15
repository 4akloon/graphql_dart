import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';

/// A GraphQL output type whose Dart value is [R] (spec 3.3).
///
/// Non-null by default; [nullable] gives the nullable form. Implemented by
/// the type definitions and by the wrappers `ExecutableSchemaBuilder.list`
/// and [nullable] make.
///
/// {@category builder}
abstract interface class OutputRef<R> {
  /// The type as a language node, such as `NonNullType(NamedType(...))`.
  TypeRef get typeRef;

  /// The named type this reference ends in, through lists and nullability.
  NamedTypeDef get namedType;

  /// This type without the non-null wrapper.
  OutputRef<R?> get nullable;
}
