import '../ast/argument.dart';
import '../ast/definition.dart';
import '../ast/directive.dart';
import '../ast/document.dart';
import '../ast/enum_value_definition.dart';
import '../ast/executable_definition.dart';
import '../ast/field_definition.dart';
import '../ast/input_value_definition.dart';
import '../ast/name.dart';
import '../ast/node.dart';
import '../ast/object_field.dart';
import '../ast/operation_type_definition.dart';
import '../ast/schema_coordinate.dart';
import '../ast/selection.dart';
import '../ast/selection_set.dart';
import '../ast/type_ref.dart';
import '../ast/type_system_definition.dart';
import '../ast/type_system_extension.dart';
import '../ast/value.dart';
import '../ast/variable_definition.dart';
import 'executable_printer.dart';
import 'extension_printer.dart';
import 'minifier.dart';
import 'type_member_printer.dart';
import 'type_system_printer.dart';
import 'value_printer.dart';

/// Prints a syntax tree as GraphQL text (R1.10): canonically, character for
/// character as graphql-js's `print`, or minified, with no insignificant
/// characters, for the wire and for persisted-query hashes.
///
/// Parsing the output gives a tree equivalent to the input.
final class Printer {
  /// Creates a printer; [isMinified] selects the minified form.
  const Printer({this.isMinified = false});

  /// Whether the output has no insignificant characters.
  final bool isMinified;

  static const ValuePrinter _values = ValuePrinter();
  static const ExecutablePrinter _executable = ExecutablePrinter(_values);
  static const TypeMemberPrinter _members = TypeMemberPrinter(_values);
  static const TypeSystemPrinter _typeSystem = TypeSystemPrinter(
    _values,
    _members,
  );
  static const ExtensionPrinter _extensions = ExtensionPrinter(
    _values,
    _members,
  );

  /// [node] as GraphQL text. Throws an [ArgumentError] for a [Node]
  /// subclass this library does not define.
  String print(Node node) {
    final canonical = _canonical(node);
    // A coordinate has no ignored characters, and the document lexer of
    // the minifier would reject its `.`.
    final isDocumentText = node is! SchemaCoordinate;
    return isMinified && isDocumentText
        ? const Minifier().minify(canonical)
        : canonical;
  }

  String _canonical(Node node) => switch (node) {
    Document(:final definitions) => definitions.map(_definition).join('\n\n'),
    Definition() => _definition(node),
    SelectionSet() => _executable.selectionSet(node),
    Selection() => _executable.selection(node),
    VariableDefinition() => _executable.variableDefinition(node),
    Value() => _values.value(node),
    TypeRef() => _values.typeRef(node),
    Argument() => _values.argument(node),
    ObjectField() => _values.objectField(node),
    Directive() => _values.directive(node),
    Name(:final value) => value,
    FieldDefinition() => _members.field(node),
    InputValueDefinition() => _members.inputValue(node),
    EnumValueDefinition() => _members.enumValue(node),
    OperationTypeDefinition() => _members.operationType(node),
    SchemaCoordinate() => _coordinate(node),
    _ => throw ArgumentError.value(node, 'node', 'is not a GraphQL node'),
  };

  /// graphql-js's `print` of a coordinate, with no space anywhere.
  static String _coordinate(SchemaCoordinate coordinate) =>
      switch (coordinate) {
        TypeCoordinate(:final name) => name.value,
        MemberCoordinate(:final name, :final memberName) =>
          '${name.value}.${memberName.value}',
        ArgumentCoordinate(
          :final name,
          :final fieldName,
          :final argumentName,
        ) =>
          '${name.value}.${fieldName.value}(${argumentName.value}:)',
        DirectiveCoordinate(:final name) => '@${name.value}',
        DirectiveArgumentCoordinate(:final name, :final argumentName) =>
          '@${name.value}(${argumentName.value}:)',
      };

  String _definition(Definition definition) => switch (definition) {
    ExecutableDefinition() => _executable.definition(definition),
    TypeSystemDefinition() => _typeSystem.definition(definition),
    TypeSystemExtension() => _extensions.extension(definition),
    _ => throw ArgumentError.value(
      definition,
      'definition',
      'is not a GraphQL definition',
    ),
  };
}
