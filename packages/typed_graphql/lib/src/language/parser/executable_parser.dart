import '../ast/executable_definition.dart';
import '../ast/variable_definition.dart';
import 'directive_parser.dart';
import 'selection_parser.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses operations and fragment definitions (spec §2.3, §2.8), with
/// the descriptions September2025 allows on them.
final class ExecutableParser {
  /// Creates a parser reading from [cursor].
  ExecutableParser(this.cursor, this.values, this.directives, this.selections);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The selection productions.
  final SelectionParser selections;

  /// `OperationDefinition`: a shorthand query `{ ... }` or a described,
  /// typed, optionally named operation.
  OperationDefinition operation() {
    final start = cursor.token.start;
    if (cursor.peek(.braceLeft)) {
      final selectionSet = selections.selectionSet();
      return OperationDefinition(
        .query,
        selectionSet,
        start: start,
        end: cursor.lastEnd,
      );
    }
    final description = values.description();
    final operation = values.operationType();
    final name = cursor.peek(.name) ? cursor.name() : null;
    final variables = cursor.optionalMany(
      .parenLeft,
      _variableDefinition,
      .parenRight,
    );
    final directiveList = directives.directives(isConst: false);
    final selectionSet = selections.selectionSet();
    return OperationDefinition(
      operation,
      selectionSet,
      description: description,
      name: name,
      variableDefinitions: variables,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// `FragmentDefinition`: `fragment Name on Type { ... }`.
  FragmentDefinition fragment() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('fragment');
    final name = selections.fragmentName();
    cursor.expectKeyword('on');
    final typeCondition = values.namedType();
    final directiveList = directives.directives(isConst: false);
    final selectionSet = selections.selectionSet();
    return FragmentDefinition(
      name,
      typeCondition,
      selectionSet,
      description: description,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  VariableDefinition _variableDefinition() {
    final start = cursor.token.start;
    final description = values.description();
    final variable = values.variable();
    cursor.expect(.colon);
    final type = values.typeRef();
    final defaultValue = cursor.expectOptional(.equals)
        ? values.value(isConst: true)
        : null;
    final directiveList = directives.directives(isConst: true);
    return VariableDefinition(
      variable,
      type,
      description: description,
      defaultValue: defaultValue,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }
}
