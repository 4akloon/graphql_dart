import '../language/visitor/ast_visitor.dart';
import 'validation_context.dart';

/// One check of an executable document against a schema (R3.1, R3.6): a
/// rule of spec §5, a limit, or a custom rule.
///
/// A rule is a const value that holds only its configuration, so one
/// object serves every run. For each run, `DocumentValidator` asks every
/// rule for a fresh visitor and walks the document once with all of them
/// (R3.2). The visitor reads the types around each node from
/// [ValidationContext.typeInfo] and reports through
/// [ValidationContext.report].
///
/// ```dart
/// final class NoDogsRule extends ValidationRule {
///   const NoDogsRule();
///
///   @override
///   AstVisitor createVisitor(ValidationContext context) => _NoDogs(context);
/// }
/// ```
///
/// {@category validation}
abstract class ValidationRule {
  /// Creates a rule.
  const ValidationRule();

  /// A new visitor that checks one document; it may keep state for that
  /// run.
  AstVisitor createVisitor(ValidationContext context);
}
