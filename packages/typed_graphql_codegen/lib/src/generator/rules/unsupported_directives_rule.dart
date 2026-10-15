import 'package:typed_graphql/typed_graphql.dart';

/// `GQL504`: `@defer` and `@stream` are not generated yet.
final class const UnsupportedDirectivesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UnsupportedDirectives(context);
}

final class _UnsupportedDirectives(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case Directive(name: Name(:final value))
        when value == 'defer' || value == 'stream') {
      context.report(
        .unsupportedInDocument,
        "The code generator does not support '@$value' yet.",
        [node],
      );
      return .skip;
    }
    return .next;
  }
}
