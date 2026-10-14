import 'child_reader.dart';
import 'definition.dart';
import 'directive.dart';
import 'enum_value_definition.dart';
import 'field_definition.dart';
import 'input_value_definition.dart';
import 'name.dart';
import 'node.dart';
import 'operation_type_definition.dart';
import 'type_ref.dart';
import 'type_system_extension_rebuilder.dart';

/// An extension of a schema, a type or a directive (spec §3.3.2, §3.4.3;
/// the directive extension is a working-draft option).
///
/// {@category language}
sealed class TypeSystemExtension({
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Definition {
  /// Creates a type system extension.
  this;

  /// The directives the extension adds, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  TypeSystemExtension rebuildFrom(ChildReader read) =>
      const TypeSystemExtensionRebuilder().rebuild(this, read);
}

/// `extend schema @d { query: Query }` (spec §3.3.2).
///
/// {@category language}
final class SchemaExtension({
  super.directives,
  List<OperationTypeDefinition> operationTypes = const [],
  super.start,
  super.end,
}) extends TypeSystemExtension {
  /// Creates a schema extension.
  this;

  /// The root operation types it adds, in source order.
  final List<OperationTypeDefinition> operationTypes = List.unmodifiable(
    operationTypes,
  );

  @override
  List<Node> get children => [...directives, ...operationTypes];
}

/// `extend directive @name @d` (working draft, behind
/// `ParserOptions.allowDirectiveExtensions`).
///
/// {@category language}
final class DirectiveExtension(
  /// The directive name, without the `@`.
  final Name name, {
  super.directives,
  super.start,
  super.end,
}) extends TypeSystemExtension {
  /// Creates a directive extension.
  this;

  @override
  List<Node> get children => [name, ...directives];
}

/// An extension of a named type (spec §3.4.3).
///
/// {@category language}
sealed class TypeExtension(
  /// The name of the type it extends.
  final Name name, {
  super.directives,
  super.start,
  super.end,
}) extends TypeSystemExtension {
  /// Creates a type extension.
  this;
}

/// `extend scalar Name @d` (spec §3.5.1).
///
/// {@category language}
final class ScalarTypeExtension(
  super.name, {
  super.directives,
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates a scalar type extension.
  this;

  @override
  List<Node> get children => [name, ...directives];
}

/// `extend type Name implements I @d { fields }` (spec §3.6.3).
///
/// {@category language}
final class ObjectTypeExtension(
  super.name, {
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an object type extension.
  this;

  /// The interfaces it adds, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields it adds, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [name, ...interfaces, ...directives, ...fields];
}

/// `extend interface Name implements I @d { fields }` (spec §3.7.1).
///
/// {@category language}
final class InterfaceTypeExtension(
  super.name, {
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an interface type extension.
  this;

  /// The interfaces it adds, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields it adds, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [name, ...interfaces, ...directives, ...fields];
}

/// `extend union Name @d = A | B` (spec §3.8.1).
///
/// {@category language}
final class UnionTypeExtension(
  super.name, {
  super.directives,
  List<NamedType> types = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates a union type extension.
  this;

  /// The member types it adds, in source order.
  final List<NamedType> types = List.unmodifiable(types);

  @override
  List<Node> get children => [name, ...directives, ...types];
}

/// `extend enum Name @d { VALUES }` (spec §3.9.1).
///
/// {@category language}
final class EnumTypeExtension(
  super.name, {
  super.directives,
  List<EnumValueDefinition> values = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an enum type extension.
  this;

  /// The values it adds, in source order.
  final List<EnumValueDefinition> values = List.unmodifiable(values);

  @override
  List<Node> get children => [name, ...directives, ...values];
}

/// `extend input Name @d { fields }` (spec §3.10.1).
///
/// {@category language}
final class InputObjectTypeExtension(
  super.name, {
  super.directives,
  List<InputValueDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an input object type extension.
  this;

  /// The input fields it adds, in source order.
  final List<InputValueDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [name, ...directives, ...fields];
}
