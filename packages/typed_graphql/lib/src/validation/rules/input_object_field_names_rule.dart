import '../../language/visitor/ast_visitor.dart';
import '../../schema/validation/value_problem_kind.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../value_problem_visitor.dart';

/// Spec §5.6.2 "Input Object Field Names": an input object literal gives
/// only fields its type defines (`GQL219`).
///
/// It reports a field the input object type does not define, at the node
/// graphql-js's
/// `ValuesOfCorrectTypeRule` points at; the other problems of a value
/// belong to the other value rules.
///
/// {@category validation}
final class const InputObjectFieldNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => ValueProblemVisitor(
    context,
    ValueProblemKind.unknownField,
    .inputObjectFieldNames,
  );
}
