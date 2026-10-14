import '../../language/visitor/ast_visitor.dart';
import '../../schema/validation/value_problem_kind.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../value_problem_visitor.dart';

/// Spec §5.6.1 "Values of Correct Type": a value literal is of the type
/// expected at its position (`GQL218`).
///
/// It reports a literal that is not a value of its input type, or null where
/// a non-null value is expected, at the node graphql-js's
/// `ValuesOfCorrectTypeRule` points at; the other problems of a value
/// belong to the other value rules.
///
/// {@category validation}
final class const ValuesOfCorrectTypeRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => ValueProblemVisitor(
    context,
    ValueProblemKind.invalid,
    .valuesOfCorrectType,
  );
}
