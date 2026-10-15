import '../../language/ast/argument.dart';
import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.4.2 "Argument Uniqueness": a field or directive names each
/// argument once (`GQL209`).
///
/// One error per repeated name, pointing at every name written.
///
/// {@category validation}
final class const UniqueArgumentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueArgumentNames(context);
}

final class _UniqueArgumentNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case Field(:final arguments) || Directive(:final arguments):
        _check(arguments);
    }
    return .next;
  }

  void _check(List<Argument> arguments) {
    if (arguments.length < 2) {
      return;
    }
    // A map keeps insertion order, so errors come in order of first use.
    final byName = <String, List<Argument>>{};
    for (final argument in arguments) {
      (byName[argument.name.value] ??= []).add(argument);
    }
    for (final MapEntry(:key, :value) in byName.entries) {
      if (value.length > 1) {
        context.report(
          .uniqueArgumentNames,
          'There can be only one argument named "$key".',
          [for (final argument in value) argument.name],
        );
      }
    }
  }
}
