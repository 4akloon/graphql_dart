import '../../language/lexer/block_string.dart';
import '../../language/printer/printer.dart';
import '../../language/printer/quoted_string.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';

/// Prints the parts of schema elements as graphql-js's `printSchema`:
/// descriptions, member blocks, arguments and applied directives.
///
/// Values and type references go through the language [Printer], so
/// `ENUM` stays an enum value and `"s"` a string.
final class const MemberPrinter() {
  /// Creates a printer.
  this;

  static const Printer _printer = Printer();

  /// [description] and a line break, as a block string when it can be one
  /// and quoted otherwise, each line after the first indented by
  /// [indentation]; empty without a description.
  ///
  /// A member that is not first in its block ([isFirstInBlock] false)
  /// gets a blank line before its description.
  String description(
    String? description, {
    String indentation = '',
    bool isFirstInBlock = true,
  }) {
    if (description == null) {
      return '';
    }
    final text = const BlockString().isPrintable(description)
        ? const BlockString().print(description)
        : const QuotedString().print(description);
    final prefix = indentation.isNotEmpty && !isFirstInBlock
        ? '\n$indentation'
        : indentation;
    return '$prefix${text.replaceAll('\n', '\n$indentation')}\n';
  }

  /// The applied [directives], each after a space.
  String directives(List<AppliedDirective> directives) => [
    for (final directive in directives)
      ' @${directive.name}${_arguments(directive)}',
  ].join();

  String _arguments(AppliedDirective directive) => directive.arguments.isEmpty
      ? ''
      : '(${directive.arguments.map(_printer.print).join(', ')})';

  /// The fields of an object or interface type as a block.
  String fields(List<SchemaField> fields) => _block([
    for (final (index, field) in fields.indexed)
      '${description(field.description, indentation: '  ', isFirstInBlock: index == 0)}'
          '  ${field.name}${arguments(field.arguments, indentation: '  ')}: '
          '${_printer.print(field.type)}${directives(field.appliedDirectives)}',
  ]);

  /// The fields of an input object type as a block.
  String inputFields(List<InputValue> fields) => _block([
    for (final (index, field) in fields.indexed)
      '${description(field.description, indentation: '  ', isFirstInBlock: index == 0)}'
          '  ${inputValue(field)}',
  ]);

  /// The values of an enum type as a block.
  String enumValues(List<SchemaEnumValue> values) => _block([
    for (final (index, value) in values.indexed)
      '${description(value.description, indentation: '  ', isFirstInBlock: index == 0)}'
          '  ${value.name}${directives(value.appliedDirectives)}',
  ]);

  /// [arguments] in parentheses: on one line, or one per line, indented
  /// by [indentation] and two spaces, when one has a description.
  String arguments(List<InputValue> arguments, {String indentation = ''}) {
    if (arguments.isEmpty) {
      return '';
    }
    if (arguments.every((argument) => argument.description == null)) {
      return '(${arguments.map(inputValue).join(', ')})';
    }
    final lines = [
      for (final (index, argument) in arguments.indexed)
        '${description(argument.description, indentation: '  $indentation', isFirstInBlock: index == 0)}'
            '  $indentation${inputValue(argument)}',
    ];
    return '(\n${lines.join('\n')}\n$indentation)';
  }

  /// An argument or input field: `name: Type = default @directives`.
  String inputValue(InputValue value) {
    final defaultValue = switch (value.defaultValue) {
      final value? => ' = ${_printer.print(value)}',
      null => '',
    };
    return '${value.name}: ${_printer.print(value.type)}$defaultValue'
        '${directives(value.appliedDirectives)}';
  }

  String _block(List<String> items) =>
      items.isEmpty ? '' : ' {\n${items.join('\n')}\n}';
}
