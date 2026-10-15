import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'object_type_def.dart';
import 'output_ref.dart';

/// A union type whose members are object types over subtypes of [P] (R4.5).
///
/// {@category builder}
final class UnionTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
  /// Declares the union [name] of [members].
  UnionTypeDef(
    super.name,
    List<ObjectTypeDef<P>> members, {
    super.description,
    this.resolveType,
  }) : members = List.unmodifiable(members),
       typeRef = NonNullType(NamedType(Name(name)));

  /// The member object types, in declaration order.
  final List<ObjectTypeDef<P>> members;

  /// Picks the object type of a value, null for the default (the first
  /// member that accepts it).
  final ObjectTypeDef<Object?> Function(P value)? resolveType;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  OutputRef<P?> get nullable => NullableOutputRef(this);
}
