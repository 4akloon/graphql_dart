import 'package:typed_graphql/typed_graphql.dart';

/// `GQL504`: `__schema` and `__type` are not generated yet (`__typename` is).
///
/// The fields are valid at the root of a query, but the planner has no schema
/// type for them: without this rule a document that asks for one would get a
/// class without it.
final class const UnsupportedIntrospectionRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UnsupportedIntrospection(context);
}

final class _UnsupportedIntrospection(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case Field(name: Name(:final value))
        when value == '__schema' || value == '__type') {
      context.report(
        .unsupportedInDocument,
        "The document selects the introspection field '$value', which the "
        'code generator does not support yet.',
        [node],
      );
      return .skip;
    }
    return .next;
  }
}
