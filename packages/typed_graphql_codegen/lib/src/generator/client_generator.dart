import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../project/project_file.dart';
import 'client_project_loader.dart';
import 'client_project_result.dart';
import 'rules/named_operations_rule.dart';
import 'rules/unsupported_directives_rule.dart';

/// Generates typed Dart client code from a schema and `.graphql` documents.
///
/// {@category codegen}
final class const ClientGenerator(final CodegenConfig config) {
  /// Creates a generator for [config].
  this;

  /// The rules the project's documents are validated with.
  ///
  /// [DocumentValidator.specifiedRules] without [NoUnusedFragmentsRule] (a
  /// fragment may exist for the application's own reads) and
  /// [LoneAnonymousOperationRule] (operations must be named anyway), then the
  /// generator's own rules.
  static const List<ValidationRule> rules = [
    ExecutableDefinitionsRule(),
    KnownOperationTypesRule(),
    UniqueOperationNamesRule(),
    SingleFieldSubscriptionsRule(),
    KnownTypeNamesRule(),
    FragmentsOnCompositeTypesRule(),
    VariablesAreInputTypesRule(),
    ScalarLeafsRule(),
    FieldsOnCorrectTypeRule(),
    UniqueFragmentNamesRule(),
    KnownFragmentNamesRule(),
    PossibleFragmentSpreadsRule(),
    NoFragmentCyclesRule(),
    UniqueVariableNamesRule(),
    NoUndefinedVariablesRule(),
    NoUnusedVariablesRule(),
    KnownDirectivesRule(),
    DirectivesInValidLocationsRule(),
    UniqueDirectivesPerLocationRule(),
    KnownArgumentNamesRule(),
    UniqueArgumentNamesRule(),
    ValuesOfCorrectTypeRule(),
    InputObjectFieldNamesRule(),
    InputObjectRequiredFieldsRule(),
    ProvidedRequiredArgumentsRule(),
    VariablesInAllowedPositionRule(),
    OverlappingFieldsCanBeMergedRule(),
    UniqueInputFieldNamesRule(),
    NamedOperationsRule(),
    UnsupportedDirectivesRule(),
  ];

  /// Checks the schema and the documents as `generate` will read them;
  /// returns every diagnostic, warnings included, in report order.
  ///
  /// [schema] is the schema file and [documents] the files the configuration's
  /// `documents` globs matched; nothing is written.
  List<Diagnostic> check({
    required ProjectFile schema,
    required List<ProjectFile> documents,
  }) {
    final result = ClientProjectLoader(
      config,
    ).load(schema: schema, documents: documents);
    return switch (result) {
      ClientProjectLoaded(:final warnings) => warnings,
      ClientProjectFailed(:final diagnostics) => diagnostics,
    };
  }
}
