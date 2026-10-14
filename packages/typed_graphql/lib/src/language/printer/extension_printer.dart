import '../ast/type_system_extension.dart';
import 'print_layout.dart';
import 'type_member_printer.dart';
import 'value_printer.dart';

/// Prints schema, type and directive extensions as graphql-js does.
final class ExtensionPrinter {
  /// Creates a printer over [values] and [members].
  const ExtensionPrinter(this.values, this.members);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  /// The shared members of types.
  final TypeMemberPrinter members;

  static const PrintLayout _layout = PrintLayout();

  /// An extension: `extend`, the keyword and the parts it adds.
  String extension(TypeSystemExtension extension) => _layout.join([
    'extend ${_keyword(extension)}',
    ?_name(extension),
    if (extension case ObjectTypeExtension(:final interfaces))
      members.interfaces(interfaces),
    if (extension case InterfaceTypeExtension(:final interfaces))
      members.interfaces(interfaces),
    values.directives(extension.directives),
    _body(extension),
  ], ' ');

  String _body(TypeSystemExtension extension) => switch (extension) {
    SchemaExtension(:final operationTypes) => members.operationTypes(
      operationTypes,
    ),
    ScalarTypeExtension() || DirectiveExtension() => '',
    ObjectTypeExtension(:final fields) => members.fields(fields),
    InterfaceTypeExtension(:final fields) => members.fields(fields),
    UnionTypeExtension(:final types) => members.unionMembers(types),
    EnumTypeExtension(:final values) => members.enumValues(values),
    InputObjectTypeExtension(:final fields) => members.inputFields(fields),
  };

  static String? _name(TypeSystemExtension extension) => switch (extension) {
    SchemaExtension() => null,
    DirectiveExtension(:final name) => '@${name.value}',
    TypeExtension(:final name) => name.value,
  };

  static String _keyword(TypeSystemExtension extension) => switch (extension) {
    SchemaExtension() => 'schema',
    DirectiveExtension() => 'directive',
    ScalarTypeExtension() => 'scalar',
    ObjectTypeExtension() => 'type',
    InterfaceTypeExtension() => 'interface',
    UnionTypeExtension() => 'union',
    EnumTypeExtension() => 'enum',
    InputObjectTypeExtension() => 'input',
  };
}
