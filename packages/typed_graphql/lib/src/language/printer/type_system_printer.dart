import '../ast/type_system_definition.dart';
import 'print_layout.dart';
import 'type_member_printer.dart';
import 'value_printer.dart';

/// Prints schema, type and directive definitions as graphql-js does.
final class TypeSystemPrinter {
  /// Creates a printer over [values] and [members].
  const TypeSystemPrinter(this.values, this.members);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  /// The shared members of types.
  final TypeMemberPrinter members;

  static const PrintLayout _layout = PrintLayout();

  /// A definition, its description on the line before it.
  String definition(TypeSystemDefinition definition) =>
      values.description(definition.description) +
      switch (definition) {
        SchemaDefinition(:final directives, :final operationTypes) =>
          _layout.join([
            'schema',
            values.directives(directives),
            members.operationTypes(operationTypes),
          ], ' '),
        DirectiveDefinition() => _directive(definition),
        TypeDefinition() => _type(definition),
      };

  String _type(TypeDefinition type) {
    final head = [
      _keyword(type),
      type.name.value,
      if (type case ObjectTypeDefinition(:final interfaces))
        members.interfaces(interfaces),
      if (type case InterfaceTypeDefinition(:final interfaces))
        members.interfaces(interfaces),
      values.directives(type.directives),
    ];
    final body = switch (type) {
      ScalarTypeDefinition() => '',
      ObjectTypeDefinition(:final fields) => members.fields(fields),
      InterfaceTypeDefinition(:final fields) => members.fields(fields),
      UnionTypeDefinition(:final types) => members.unionMembers(types),
      EnumTypeDefinition(:final values) => members.enumValues(values),
      InputObjectTypeDefinition(:final fields) => members.inputFields(fields),
    };
    return _layout.join([...head, body], ' ');
  }

  String _directive(DirectiveDefinition directive) =>
      'directive @${directive.name.value}'
      '${members.argumentDefinitions(directive.arguments)}'
      '${_layout.wrap(' ', values.directives(directive.directives))}'
      '${directive.isRepeatable ? ' repeatable' : ''}'
      ' on ${directive.locations.map((location) => location.value).join(' | ')}';

  static String _keyword(TypeDefinition type) => switch (type) {
    ScalarTypeDefinition() => 'scalar',
    ObjectTypeDefinition() => 'type',
    InterfaceTypeDefinition() => 'interface',
    UnionTypeDefinition() => 'union',
    EnumTypeDefinition() => 'enum',
    InputObjectTypeDefinition() => 'input',
  };
}
