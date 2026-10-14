import '../ast/executable_definition.dart';
import '../ast/selection.dart';
import '../ast/selection_set.dart';
import '../ast/type_ref.dart';
import '../ast/variable_definition.dart';
import 'print_layout.dart';
import 'value_printer.dart';

/// Prints operations, fragments and selections as graphql-js does.
final class ExecutablePrinter {
  /// Creates a printer that prints values with [values].
  const ExecutablePrinter(this.values);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  static const PrintLayout _layout = PrintLayout();

  /// An operation or a fragment.
  String definition(ExecutableDefinition definition) => switch (definition) {
    OperationDefinition() => _operation(definition),
    FragmentDefinition() => _fragment(definition),
  };

  /// A selection set, one selection per line. An empty one, which only
  /// the working draft parses, prints as `{}` so it parses back.
  String selectionSet(SelectionSet set) => set.selections.isEmpty
      ? '{}'
      : _layout.block(set.selections.map(selection));

  /// A field, a fragment spread or an inline fragment.
  String selection(Selection selection) => switch (selection) {
    Field() => _field(selection),
    FragmentSpread(:final name, :final directives) =>
      '...${name.value}${_layout.wrap(' ', values.directives(directives))}',
    InlineFragment(:final typeCondition, :final directives) => _layout.join([
      '...',
      _layout.wrap('on ', _typeName(typeCondition)),
      values.directives(directives),
      selectionSet(selection.selectionSet),
    ], ' '),
  };

  /// `$name: Type = default @directives`, after its description.
  String variableDefinition(VariableDefinition definition) {
    final description = values.description(definition.description);
    final variable = values.value(definition.variable);
    final type = values.typeRef(definition.type);
    final defaultValue = _layout.wrap(' = ', _defaultValue(definition));
    final directives = values.directives(definition.directives);
    return '$description$variable: $type$defaultValue'
        '${_layout.wrap(' ', directives)}';
  }

  String _operation(OperationDefinition operation) {
    final variables = operation.variableDefinitions
        .map(variableDefinition)
        .toList();
    final variableList = _layout.hasMultilineItems(variables)
        ? _layout.wrap('(\n', _layout.join(variables, '\n'), '\n)')
        : _layout.wrap('(', _layout.join(variables, ', '), ')');
    final prefix =
        values.description(operation.description) +
        _layout.join([
          operation.operation.name,
          _layout.join([operation.name?.value ?? '', variableList]),
          values.directives(operation.directives),
        ], ' ');
    // graphql-js: an anonymous query with nothing else prints as `{ ... }`.
    final head = prefix == 'query' ? '' : '$prefix ';
    return head + selectionSet(operation.selectionSet);
  }

  String _fragment(FragmentDefinition fragment) =>
      '${values.description(fragment.description)}'
      'fragment ${fragment.name.value} '
      'on ${fragment.typeCondition.name.value} '
      '${_layout.wrap('', values.directives(fragment.directives), ' ')}'
      '${selectionSet(fragment.selectionSet)}';

  String _field(Field field) {
    final prefix =
        _layout.wrap('', field.alias?.value, ': ') + field.name.value;
    final arguments = field.arguments.map(values.argument).toList();
    final set = field.selectionSet;
    return _layout.withArguments(prefix, arguments) +
        _layout.wrap(' ', values.directives(field.directives)) +
        (set == null ? '' : ' ${selectionSet(set)}');
  }

  String? _defaultValue(VariableDefinition definition) {
    final value = definition.defaultValue;
    return value == null ? null : values.value(value);
  }

  static String? _typeName(NamedType? type) => type?.name.value;
}
