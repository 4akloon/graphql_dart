import 'package:typed_graphql/typed_graphql.dart';

/// The validator the hostile operation fuzzers run: every specified rule
/// and every opt-in rule, with small limits so that the limit rules fire.
final class HostileRules {
  const HostileRules._();

  /// The rules of one run.
  static const List<ValidationRule> all = [
    ...DocumentValidator.recommendedRules,
    MaxDepthRule(maxDepth: 5),
    MaxAliasesRule(maxAliases: 5),
    MaxDirectivesRule(maxDirectives: 5),
    NoIntrospectionRule(),
    SlicingArgumentsRule(),
    MaxCostRule(maxCost: 100),
  ];

  /// The most errors a run reports.
  static const int maxErrors = 20;

  /// A validator over [all] with [maxErrors].
  static const DocumentValidator validator = DocumentValidator(
    rules: all,
    maxErrors: maxErrors,
  );
}
