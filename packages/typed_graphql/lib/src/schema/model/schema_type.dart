import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';
import 'input_value.dart';
import 'schema_enum_value.dart';
import 'schema_field.dart';

/// A named type of a schema (spec §3.4): the sealed family of named
/// types (R2.1).
///
/// The language node `NamedType` is a reference to a type by name; this
/// is the type itself. References between types are names, so a cyclic
/// schema needs no `late`.
///
/// {@category schema}
sealed class SchemaType(
  /// The type name.
  final String name, {

  /// The description, if any.
  final String? description,
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL. An
  /// extension does not move it.
  final SourceSpan? span,
}) {
  /// Creates a named type.
  this;

  /// The directives applied to it, its extensions' included, in the order
  /// written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The field of [fields] named [name], for object and interface types.
  static SchemaField? _fieldIn(List<SchemaField> fields, String name) {
    for (final field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }
}

/// A scalar type, `scalar Name @specifiedBy(url: "...")` (spec §3.5).
///
/// {@category schema}
final class ScalarType(
  super.name, {
  super.description,
  super.appliedDirectives,
  super.span,
}) extends SchemaType {
  /// Creates a scalar type.
  this;

  /// The `url` of `@specifiedBy`; null without one.
  String? get specifiedByUrl =>
      AppliedDirectives(appliedDirectives).specifiedByUrl;
}

/// An object type, `type Name implements I { fields }` (spec §3.6).
///
/// {@category schema}
final class ObjectType(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.appliedDirectives,
  List<SchemaField> fields = const [],
  super.span,
}) extends SchemaType {
  /// Creates an object type.
  this;

  /// The interfaces it implements, by name, in declaration order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in declaration order.
  final List<SchemaField> fields = List.unmodifiable(fields);

  /// The field named [name]; null when there is none.
  SchemaField? fieldNamed(String name) => SchemaType._fieldIn(fields, name);
}

/// An interface type, `interface Name implements I { fields }` (spec
/// §3.7).
///
/// {@category schema}
final class InterfaceType(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.appliedDirectives,
  List<SchemaField> fields = const [],
  super.span,
}) extends SchemaType {
  /// Creates an interface type.
  this;

  /// The interfaces it implements, by name, in declaration order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in declaration order.
  final List<SchemaField> fields = List.unmodifiable(fields);

  /// The field named [name]; null when there is none.
  SchemaField? fieldNamed(String name) => SchemaType._fieldIn(fields, name);
}

/// A union type, `union Name = A | B` (spec §3.8).
///
/// {@category schema}
final class UnionType(
  super.name, {
  super.description,
  super.appliedDirectives,
  List<NamedType> memberTypes = const [],
  super.span,
}) extends SchemaType {
  /// Creates a union type.
  this;

  /// The member types, by name, in declaration order; a repeated member
  /// is kept for schema validation to report.
  final List<NamedType> memberTypes = List.unmodifiable(memberTypes);
}

/// An enum type, `enum Name { VALUES }` (spec §3.9).
///
/// {@category schema}
final class EnumType(
  super.name, {
  super.description,
  super.appliedDirectives,
  List<SchemaEnumValue> values = const [],
  super.span,
}) extends SchemaType {
  /// Creates an enum type.
  this;

  /// The values, in declaration order.
  final List<SchemaEnumValue> values = List.unmodifiable(values);

  /// The value named [name]; null when there is none.
  SchemaEnumValue? valueNamed(String name) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }
}

/// An input object type, `input Name @oneOf { fields }` (spec §3.10).
///
/// {@category schema}
final class InputObjectType(
  super.name, {
  super.description,
  super.appliedDirectives,
  List<InputValue> fields = const [],
  super.span,
}) extends SchemaType {
  /// Creates an input object type.
  this;

  /// The input fields, in declaration order.
  final List<InputValue> fields = List.unmodifiable(fields);

  /// Whether `@oneOf` is applied: exactly one field must be given (spec
  /// §3.10.1).
  bool get isOneOf => AppliedDirectives(appliedDirectives).isOneOf;

  /// The input field named [name]; null when there is none.
  InputValue? fieldNamed(String name) {
    for (final field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }
}
