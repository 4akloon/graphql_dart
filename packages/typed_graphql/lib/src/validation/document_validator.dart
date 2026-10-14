import '../diagnostics/diagnostic_sink.dart';
import '../diagnostics/source.dart';
import '../language/ast/document.dart';
import '../language/visitor/ast_walker.dart';
import '../schema/validation/schema_validation_result.dart';
import 'document_validation_result.dart';
import 'rules/directives_in_valid_locations_rule.dart';
import 'rules/executable_definitions_rule.dart';
import 'rules/fields_on_correct_type_rule.dart';
import 'rules/fragments_on_composite_types_rule.dart';
import 'rules/input_object_field_names_rule.dart';
import 'rules/input_object_required_fields_rule.dart';
import 'rules/known_argument_names_rule.dart';
import 'rules/known_directives_rule.dart';
import 'rules/known_fragment_names_rule.dart';
import 'rules/known_operation_types_rule.dart';
import 'rules/known_type_names_rule.dart';
import 'rules/lone_anonymous_operation_rule.dart';
import 'rules/no_fragment_cycles_rule.dart';
import 'rules/no_unused_fragments_rule.dart';
import 'rules/possible_fragment_spreads_rule.dart';
import 'rules/provided_required_arguments_rule.dart';
import 'rules/scalar_leafs_rule.dart';
import 'rules/single_field_subscriptions_rule.dart';
import 'rules/unique_argument_names_rule.dart';
import 'rules/unique_directives_per_location_rule.dart';
import 'rules/unique_fragment_names_rule.dart';
import 'rules/unique_input_field_names_rule.dart';
import 'rules/unique_operation_names_rule.dart';
import 'rules/values_of_correct_type_rule.dart';
import 'rules/variables_are_input_types_rule.dart';
import 'validation_context.dart';
import 'validation_rule.dart';

/// Checks an executable document against a schema (spec §5; R3.1–R3.4):
/// every rule in one walk, the result a [ValidDocument] or an
/// [InvalidDocument] with every error up to [maxErrors].
///
/// The default rules are [specifiedRules], the 30 rules of spec §5. Add
/// limits or custom rules to a copy of the list:
///
/// ```dart
/// const validator = DocumentValidator(
///   rules: [...DocumentValidator.specifiedRules, NoDogsRule()],
/// );
/// ```
///
/// {@category validation}
final class const DocumentValidator({
  /// The rules each run checks, in the order their visitors are called
  /// at each node.
  final List<ValidationRule> rules = specifiedRules,

  /// The most errors a run reports; the next becomes `GQL000` and stops
  /// the run, as graphql-js's `maxErrors`.
  final int maxErrors = DiagnosticSink.defaultMaxErrors,

  /// Whether messages may suggest names ("Did you mean ..."); a
  /// production server turns them off (R5.15).
  final bool includesSuggestions = true,

  /// The most work a run may do beyond its one walk; see
  /// [ValidationContext.spend].
  final int maxSteps = ValidationContext.defaultMaxSteps,
}) {
  /// Creates a validator.
  this;

  /// The rules of spec §5, in graphql-js's order.
  static const List<ValidationRule> specifiedRules = [
    ExecutableDefinitionsRule(),
    KnownOperationTypesRule(),
    UniqueOperationNamesRule(),
    LoneAnonymousOperationRule(),
    SingleFieldSubscriptionsRule(),
    KnownTypeNamesRule(),
    FragmentsOnCompositeTypesRule(),
    VariablesAreInputTypesRule(),
    ScalarLeafsRule(),
    FieldsOnCorrectTypeRule(),
    UniqueFragmentNamesRule(),
    KnownFragmentNamesRule(),
    NoUnusedFragmentsRule(),
    PossibleFragmentSpreadsRule(),
    NoFragmentCyclesRule(),
    KnownDirectivesRule(),
    DirectivesInValidLocationsRule(),
    UniqueDirectivesPerLocationRule(),
    KnownArgumentNamesRule(),
    UniqueArgumentNamesRule(),
    ValuesOfCorrectTypeRule(),
    InputObjectFieldNamesRule(),
    InputObjectRequiredFieldsRule(),
    ProvidedRequiredArgumentsRule(),
    UniqueInputFieldNamesRule(),
  ];

  /// Validates [document] against [schema]; diagnostics point into
  /// [source] when it is given, the text [document] was parsed from.
  DocumentValidationResult validate(
    ValidSchema schema,
    Document document, {
    Source? source,
  }) {
    final sink = DiagnosticSink(maxErrors: maxErrors);
    final context = ValidationContext(
      schema.schema,
      document,
      sink,
      source: source,
      includesSuggestions: includesSuggestions,
      maxSteps: maxSteps,
    );
    final visitors = [for (final rule in rules) rule.createVisitor(context)];
    const AstWalker().walk(document, context.visitorFor(visitors));
    return sink.hasErrors
        ? InvalidDocument(schema, document, sink.diagnostics)
        : ValidDocument.assumeValid(schema, document);
  }
}
