import '../../language/ast/executable_definition.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../variable_usage.dart';
import 'operation_visitor.dart';

/// Spec §5.8.5 "All Variable Usages Are Allowed": a variable's type fits
/// the position it is used in (`GQL229`).
///
/// A nullable variable may stand where a non-null type is expected when
/// the variable or the position has a default value; a field of a `@oneOf`
/// input object takes only a non-null variable. Reported when the walk
/// leaves the document, operation by operation.
///
/// {@category validation}
final class const VariablesInAllowedPositionRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _VariablesInAllowedPosition(context);
}

final class _VariablesInAllowedPosition(final ValidationContext context)
    extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    // Every report after the error limit or the budget is ignored.
    if (context.isAborted) {
      return;
    }
    // The last definition of a repeated name wins, as graphql-js's map.
    final definitions = {
      for (final definition in operation.variableDefinitions)
        definition.variable.name.value: definition,
    };
    for (final usage in context.recursiveVariableUsages(operation)) {
      if (context.isAborted) {
        return;
      }
      final definition = definitions[usage.node.name.value];
      final position = usage.type;
      if (definition != null && position != null) {
        _checkUsage(definition, usage, position);
      }
    }
  }

  void _checkUsage(
    VariableDefinition definition,
    VariableUsage usage,
    TypeRef position,
  ) {
    final variableType = definition.type;
    // An unknown type is left to KnownTypeNamesRule.
    if (context.schema.namedTypeOf(variableType) == null) {
      return;
    }
    final name = usage.node.name.value;
    final nodes = [definition, usage.node];
    if (!_isAllowed(definition, usage, position)) {
      context.report(
        .variablesInAllowedPosition,
        'Variable "\$$name" of type "${_print(variableType)}" used in '
        'position expecting type "${_print(position)}".',
        nodes,
      );
    }
    if (usage.parentType case final NamedType parent
        when _isOneOf(parent) && variableType is! NonNullType) {
      context.report(
        .variablesInAllowedPosition,
        'Variable "\$$name" is of type "${_print(variableType)}" but must be '
        'non-nullable to be used for OneOf Input Object "${_print(parent)}".',
        nodes,
      );
    }
  }

  // graphql-js's allowedVariableUsage; a @oneOf field is checked apart, for
  // its more descriptive message.
  bool _isAllowed(
    VariableDefinition definition,
    VariableUsage usage,
    TypeRef position,
  ) {
    final variableType = definition.type;
    if (position is NonNullType && variableType is! NonNullType) {
      final hasVariableDefault =
          definition.defaultValue != null &&
          definition.defaultValue is! NullValue;
      if (!hasVariableDefault && usage.defaultValue == null) {
        return false;
      }
      return context.schema.isTypeSubTypeOf(variableType, position.type);
    }
    return context.schema.isTypeSubTypeOf(variableType, position);
  }

  bool _isOneOf(NamedType type) {
    if (context.schema.typeNamed(type.name.value) case InputObjectType(
      :final isOneOf,
    )) {
      return isOneOf;
    }
    return false;
  }

  String _print(TypeRef type) => const Printer().print(type);
}
