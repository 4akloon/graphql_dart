import '../schema.dart';
import 'applied_directive_rules.dart';
import 'cost_directive_rules.dart';
import 'directive_definition_rules.dart';
import 'root_type_rules.dart';
import 'schema_validation_result.dart';
import 'type_rules.dart';
import 'validation_report.dart';

/// Checks a schema against the type-system rules of the specification
/// (spec §7; R2.3, R2.4) in one pass, in graphql-js's order: roots,
/// the directives applied to the schema, directive definitions, then types
/// in declaration order.
///
/// Each rule family is a class in `schema/validation/`. A schema with no
/// error is a [ValidSchema]; otherwise the result is an [InvalidSchema]
/// with every error, up to the sink's limit. Nothing throws.
///
/// {@category schema}
final class const SchemaValidator() {
  /// Creates a validator.
  this;

  /// Validates [schema].
  SchemaValidationResult validate(Schema schema) {
    final report = ValidationReport();
    RootTypeRules(report, schema).check();
    AppliedDirectiveRules(
      report,
      schema,
    ).check(schema.appliedDirectives, .schema);
    DirectiveDefinitionRules(report, schema).check();
    TypeRules(report, schema).check();
    if (schema.includesCostDirectives) {
      CostDirectiveRules(report, schema).check();
    }
    return report.hasErrors
        ? InvalidSchema(schema, report.diagnostics)
        : ValidSchema.assumeValid(schema);
  }
}
