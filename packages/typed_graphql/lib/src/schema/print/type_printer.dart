import '../model/named_type_reference.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import 'member_printer.dart';

/// Prints a named type or a directive definition as graphql-js's
/// `printSchema`, with every applied directive as written.
final class const TypePrinter() {
  /// Creates a printer.
  this;

  static const MemberPrinter _members = MemberPrinter();

  /// [type] as SDL, its description first.
  String type(SchemaType type) {
    final directives = _members.directives(type.appliedDirectives);
    final head = '${type.name}$directives';
    final definition = switch (type) {
      ScalarType() => 'scalar $head',
      ObjectType(:final interfaces, :final fields) =>
        'type ${type.name}${_interfaces(interfaces)}$directives'
            '${_members.fields(fields)}',
      InterfaceType(:final interfaces, :final fields) =>
        'interface ${type.name}${_interfaces(interfaces)}$directives'
            '${_members.fields(fields)}',
      UnionType(:final memberTypes) => 'union $head${_union(memberTypes)}',
      EnumType(:final values) => 'enum $head${_members.enumValues(values)}',
      InputObjectType(:final fields) =>
        'input $head${_members.inputFields(fields)}',
    };
    return '${_members.description(type.description)}$definition';
  }

  /// [directive] as SDL, its description first.
  String directive(SchemaDirective directive) =>
      '${_members.description(directive.description)}'
      'directive @${directive.name}${_members.arguments(directive.arguments)}'
      '${_members.directives(directive.appliedDirectives)}'
      '${directive.isRepeatable ? ' repeatable' : ''}'
      ' on ${directive.locations.map((location) => location.spelling).join(' | ')}';

  static String _union(List<NamedTypeReference> memberTypes) =>
      memberTypes.isEmpty ? '' : ' = ${_names(memberTypes, ' | ')}';

  static String _interfaces(List<NamedTypeReference> interfaces) =>
      interfaces.isEmpty ? '' : ' implements ${_names(interfaces, ' & ')}';

  static String _names(List<NamedTypeReference> types, String separator) =>
      types.map((type) => type.name).join(separator);
}
