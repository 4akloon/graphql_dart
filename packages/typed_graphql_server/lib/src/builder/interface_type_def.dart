import 'package:typed_graphql/typed_graphql.dart';

import 'field_def.dart';
import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'object_type_def.dart';
import 'output_ref.dart';

/// An interface type whose implementing values are subtypes of [P] (R4.5).
///
/// {@category builder}
final class InterfaceTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
  /// Declares the interface [name].
  ///
  /// [fieldsThunk] runs on first use, so types may refer to each other.
  InterfaceTypeDef(
    super.name,
    List<FieldDef<P, Object?>> Function() fieldsThunk, {
    List<InterfaceTypeDef<Object?>> interfaces = const [],
    super.description,
    this.resolveType,
  }) : _fieldsThunk = fieldsThunk,
       interfaces = List.unmodifiable(interfaces),
       typeRef = NonNullType(NamedType(Name(name)));

  final List<FieldDef<P, Object?>> Function() _fieldsThunk;

  /// The interface's own fields, in declaration order.
  // Set on first read, so types that refer to each other can be made before
  // either one's fields are built.
  late final List<FieldDef<P, Object?>> fields = List.unmodifiable(
    _fieldsThunk(),
  );

  /// The interfaces this one implements, as listed (not transitive).
  final List<InterfaceTypeDef<Object?>> interfaces;

  /// Picks the object type of a value, null for the default (the first
  /// possible type that accepts it).
  final ObjectTypeDef<Object?> Function(P value)? resolveType;

  /// Whether [resolveType] is given.
  bool get hasResolveType => resolveType != null;

  /// [resolveType] taking any value: the cast to [P] is made here, where
  /// [P] is known, because reading [resolveType] through a supertype
  /// instance fails its function-type check. Null without [resolveType].
  ObjectTypeDef<Object?> Function(Object? value)? get untypedResolveType {
    final resolve = resolveType;
    return resolve == null ? null : (value) => resolve(value as P);
  }

  /// Whether a value of Dart type [X] is a value of this interface.
  ///
  /// Dart has no contravariant type parameter, so `GQL300` is checked at
  /// build with this test.
  bool isSupertypeOf<X>() => <X>[] is List<P>;

  /// The Dart type [P] as written, for messages.
  String get dartTypeName => '$P';

  /// Whether [P] is a subtype of the Dart type of [other] (`GQL300`).
  bool isDartSubtypeOf(InterfaceTypeDef<Object?> other) =>
      other.isSupertypeOf<P>();

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  OutputRef<P?> get nullable => NullableOutputRef(this);
}
