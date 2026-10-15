import 'package:typed_graphql/typed_graphql.dart';

import 'field_def.dart';
import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'object_options.dart';
import 'output_ref.dart';

/// An object type whose values are the Dart class [P] (R4.1).
///
/// It is its own output reference. The context type is known only to the
/// builder that made it, which closes over it in the fields thunk.
///
/// {@category builder}
final class ObjectTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
  /// Declares the object type [name].
  ///
  /// [fieldsThunk] runs on first use, so types may refer to each other.
  ObjectTypeDef(
    super.name,
    List<FieldDef<P, Object?>> Function() fieldsThunk, {
    super.description,
    List<InterfaceTypeDef<Object?>> interfaces = const [],
    this.options = const ObjectOptions(),
  }) : _fieldsThunk = fieldsThunk,
       interfaces = List.unmodifiable(interfaces),
       typeRef = NonNullType(NamedType(Name(name)));

  final List<FieldDef<P, Object?>> Function() _fieldsThunk;

  /// The type's own fields, in declaration order.
  // Set on first read, so types that refer to each other can be made before
  // either one's fields are built.
  late final List<FieldDef<P, Object?>> fields = List.unmodifiable(
    _fieldsThunk(),
  );

  /// The interfaces the type implements, as listed (not transitive).
  final List<InterfaceTypeDef<Object?>> interfaces;

  /// The rarer settings.
  final ObjectOptions options;

  /// Whether [value] belongs to this type: [ObjectOptions.isTypeOf] when
  /// given, else `value is P`.
  bool accepts(Object? value) => options.isTypeOf?.call(value) ?? value is P;

  /// The Dart type [P] as written, for messages.
  String get dartTypeName => '$P';

  /// Whether [P] is a subtype of the Dart type of [interface] (`GQL300`).
  bool isDartSubtypeOfInterface(InterfaceTypeDef<Object?> interface) =>
      interface.isSupertypeOf<P>();

  /// Whether [P] is a subtype of the Dart type of [other].
  bool isDartSubtypeOf(ObjectTypeDef<Object?> other) =>
      other._isDartSupertypeOf<P>();

  // Dart has no contravariant type parameter: the test needs the type of the
  // other object as `P`, so it runs inside that object.
  bool _isDartSupertypeOf<X>() => <X>[] is List<P>;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  OutputRef<P?> get nullable => NullableOutputRef(this);
}
