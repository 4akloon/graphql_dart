import 'package:typed_graphql/typed_graphql.dart';

import 'field_def.dart';
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
    this.options = const ObjectOptions(),
  }) : _fieldsThunk = fieldsThunk,
       typeRef = NonNullType(NamedType(Name(name)));

  final List<FieldDef<P, Object?>> Function() _fieldsThunk;

  /// The type's own fields, in declaration order.
  // Set on first read, so types that refer to each other can be made before
  // either one's fields are built.
  late final List<FieldDef<P, Object?>> fields = List.unmodifiable(
    _fieldsThunk(),
  );

  /// The rarer settings.
  final ObjectOptions options;

  /// Whether [value] belongs to this type: [ObjectOptions.isTypeOf] when
  /// given, else `value is P`.
  bool accepts(Object? value) => options.isTypeOf?.call(value) ?? value is P;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  OutputRef<P?> get nullable => NullableOutputRef(this);
}
