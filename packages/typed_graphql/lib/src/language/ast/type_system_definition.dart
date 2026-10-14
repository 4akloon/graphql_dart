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
import 'type_system_definition_rebuilder.dart';
import 'value.dart';

/// A definition of a schema, a type or a directive (spec §3).
///
/// {@category language}
sealed class TypeSystemDefinition({
  /// The description, if any.
  final StringValue? description,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Definition {
  /// Creates a type system definition.
  this;

  /// The directives, in source order (working draft on a directive).
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  TypeSystemDefinition rebuildFrom(ChildReader read) =>
      const TypeSystemDefinitionRebuilder().rebuild(this, read);
}

/// `"desc" schema @d { query: Query }` (spec §3.3).
///
/// {@category language}
final class SchemaDefinition({
  super.description,
  super.directives,
  List<OperationTypeDefinition> operationTypes = const [],
  super.start,
  super.end,
}) extends TypeSystemDefinition {
  /// Creates a schema definition.
  this;

  /// The root operation types, in source order.
  final List<OperationTypeDefinition> operationTypes = List.unmodifiable(
    operationTypes,
  );

  @override
  List<Node> get children => [?description, ...directives, ...operationTypes];
}

/// `"desc" directive @name(args) @d repeatable on LOCATIONS` (spec §3.13).
///
/// {@category language}
final class DirectiveDefinition(
  /// The directive name, without the `@`.
  final Name name, {
  super.description,
  List<InputValueDefinition> arguments = const [],
  super.directives,

  /// Whether the directive may be applied more than once to one place.
  final bool isRepeatable = false,
  List<Name> locations = const [],
  super.start,
  super.end,
}) extends TypeSystemDefinition {
  /// Creates a directive definition.
  this;

  /// The argument definitions, in source order.
  final List<InputValueDefinition> arguments = List.unmodifiable(arguments);

  /// The locations, such as `FIELD`, in source order.
  final List<Name> locations = List.unmodifiable(locations);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...arguments,
    ...directives,
    ...locations,
  ];

  @override
  List<Object?> get scalars => [isRepeatable];
}

/// A named type definition (spec §3.4).
///
/// {@category language}
sealed class TypeDefinition(
  /// The type name.
  final Name name, {
  super.description,
  super.directives,
  super.start,
  super.end,
}) extends TypeSystemDefinition {
  /// Creates a type definition.
  this;
}

/// `"desc" scalar Name @d` (spec §3.5).
///
/// {@category language}
final class ScalarTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates a scalar type definition.
  this;

  @override
  List<Node> get children => [?description, name, ...directives];
}

/// `"desc" type Name implements I @d { fields }` (spec §3.6).
///
/// {@category language}
final class ObjectTypeDefinition(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an object type definition.
  this;

  /// The interfaces it implements, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...interfaces,
    ...directives,
    ...fields,
  ];
}

/// `"desc" interface Name implements I @d { fields }` (spec §3.7).
///
/// {@category language}
final class InterfaceTypeDefinition(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an interface type definition.
  this;

  /// The interfaces it implements, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...interfaces,
    ...directives,
    ...fields,
  ];
}

/// `"desc" union Name @d = A | B` (spec §3.8).
///
/// {@category language}
final class UnionTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  List<NamedType> types = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates a union type definition.
  this;

  /// The member types, in source order.
  final List<NamedType> types = List.unmodifiable(types);

  @override
  List<Node> get children => [?description, name, ...directives, ...types];
}

/// `"desc" enum Name @d { VALUES }` (spec §3.9).
///
/// {@category language}
final class EnumTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  List<EnumValueDefinition> values = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an enum type definition.
  this;

  /// The values, in source order.
  final List<EnumValueDefinition> values = List.unmodifiable(values);

  @override
  List<Node> get children => [?description, name, ...directives, ...values];
}

/// `"desc" input Name @d { fields }` (spec §3.10).
///
/// {@category language}
final class InputObjectTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  List<InputValueDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an input object type definition.
  this;

  /// The input fields, in source order.
  final List<InputValueDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [?description, name, ...directives, ...fields];
}
