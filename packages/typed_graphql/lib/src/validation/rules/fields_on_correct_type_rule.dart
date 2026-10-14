import '../../diagnostics/suggestions.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'field_type_suggestions.dart';

/// Spec §5.3.1 "Field Selections": a field is defined by the type whose
/// selection set holds it, or is a meta-field (`GQL205`).
///
/// The message suggests inline fragments on the types that define the
/// field, or else field names close to the one written.
///
/// {@category validation}
final class const FieldsOnCorrectTypeRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _FieldsOnCorrectType(context);
}

final class _FieldsOnCorrectType(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field && context.typeInfo.fieldDefinition == null) {
      if (context.typeInfo.parentType case final parent?) {
        final name = node.name.value;
        context.report(
          .fieldsOnCorrectType,
          'Cannot query field "$name" on type "${parent.name}".'
          '${_suggestion(parent, name)}',
          [node],
        );
      }
    }
    return .next;
  }

  String _suggestion(SchemaType parent, String fieldName) {
    if (!context.includesSuggestions) {
      return '';
    }
    const suggestions = Suggestions();
    final onTypes = suggestions.didYouMean(
      FieldTypeSuggestions(context.schema).namesFor(parent, fieldName),
      subject: 'to use an inline fragment on',
    );
    if (onTypes.isNotEmpty) {
      return onTypes;
    }
    final fieldNames = switch (parent) {
      ObjectType(:final fields) || InterfaceType(:final fields) => [
        for (final field in fields) field.name,
      ],
      _ => const <String>[],
    };
    return suggestions.didYouMean(suggestions.listFor(fieldName, fieldNames));
  }
}
