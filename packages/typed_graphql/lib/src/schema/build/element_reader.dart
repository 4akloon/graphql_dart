import '../../language/ast/directive.dart';
import '../../language/ast/directive_location.dart';
import '../../language/ast/enum_value_definition.dart';
import '../../language/ast/field_definition.dart';
import '../../language/ast/input_value_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/type_system_definition.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import 'node_spans.dart';

/// Reads the members of type-system definitions into schema elements:
/// fields, input values, enum values, applied directives and directive
/// definitions, each with its span.
final class const ElementReader(
  /// Gives each element the span of its node.
  final NodeSpans spans,
) {
  /// Creates a reader.
  this;

  /// A field definition, with its arguments.
  SchemaField field(FieldDefinition node) => SchemaField(
    node.name.value,
    node.type,
    description: node.description?.value,
    arguments: node.arguments.map(inputValue).toList(),
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );

  /// An argument or input field definition.
  InputValue inputValue(InputValueDefinition node) => InputValue(
    node.name.value,
    node.type,
    description: node.description?.value,
    defaultValue: node.defaultValue,
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );

  /// An enum value definition.
  SchemaEnumValue enumValue(EnumValueDefinition node) => SchemaEnumValue(
    node.name.value,
    description: node.description?.value,
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );

  /// The directives applied to an element, in order.
  List<AppliedDirective> appliedAll(List<Directive> nodes) => [
    for (final node in nodes)
      AppliedDirective(
        node.name.value,
        arguments: node.arguments,
        span: spans.of(node),
      ),
  ];

  /// A directive definition, with its arguments and locations.
  SchemaDirective directive(DirectiveDefinition node) => SchemaDirective(
    node.name.value,
    description: node.description?.value,
    arguments: node.arguments.map(inputValue).toList(),
    isRepeatable: node.isRepeatable,
    locations: node.locations.map(_location).toList(),
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );

  /// The location [name] spells. The parser accepts no other name, so an
  /// unknown one comes from a document built in code: a programmer error.
  static DirectiveLocation _location(Name name) =>
      DirectiveLocation.named(name.value) ??
      (throw ArgumentError.value(
        name.value,
        'locations',
        'Not a directive location',
      ));
}
