import '../../language/visitor/ast_visitor.dart';
import '../../schema/validation/value_problem_kind.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../value_problem_visitor.dart';

/// Spec §5.6.4 "Input Object Required Fields": an input object literal gives
/// every required field (`GQL221`).
///
/// It reports a required field of the input object type that the literal
/// omits, at the node graphql-js's
/// `ValuesOfCorrectTypeRule` points at; the other problems of a value
/// belong to the other value rules.
///
/// {@category validation}
final class const InputObjectRequiredFieldsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => ValueProblemVisitor(
    context,
    ValueProblemKind.missingField,
    .inputObjectRequiredFields,
  );
}
