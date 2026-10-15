import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../emit/schema_types_emitter.dart';
import '../emit/type_mapper.dart';
import '../project/project_file.dart';
import 'client_project.dart';
import 'client_project_loader.dart';
import 'client_project_result.dart';
import 'document_libraries.dart';
import 'document_name_checker.dart';
import 'generated_file.dart';
import 'generated_names.dart';
import 'generation_result.dart';
import 'persisted_manifest.dart';
import 'rules/named_operations_rule.dart';
import 'rules/subscription_root_rule.dart';
import 'rules/unsupported_directives_rule.dart';
import 'rules/unsupported_introspection_rule.dart';
import 'schema_type_usage.dart';

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
    UnsupportedIntrospectionRule(),
    SubscriptionRootRule(),
  ];

  /// Checks the schema and the documents as `generate` will read them;
  /// returns every diagnostic, warnings included, in report order.
  ///
  /// This is `generate(...).diagnostics`: it includes the name checks.
  List<Diagnostic> check({
    required ProjectFile schema,
    required List<ProjectFile> documents,
  }) => generate(schema: schema, documents: documents).diagnostics;

  /// Generates the files of the project.
  ///
  /// When the schema cannot be loaded, the documents are only parsed: their
  /// syntax errors come after the schema's, and no validation error is
  /// reported. With any error the result has no files.
  ///
  /// [schema] is the schema file and [documents] the files the configuration's
  /// `documents` globs matched; nothing is written. The files
  /// are the schema-types library at [CodegenConfig.schemaTypes], then a
  /// library per document file, at its path plus `.dart`, sorted by path.
  GenerationResult generate({
    required ProjectFile schema,
    required List<ProjectFile> documents,
  }) {
    final result = ClientProjectLoader(
      config,
      rules,
    ).load(schema: schema, documents: documents);
    return switch (result) {
      ClientProjectFailed(:final diagnostics) => GenerationResult(
        const [],
        diagnostics,
      ),
      ClientProjectLoaded(:final project, :final warnings) => _generate(
        project,
        schema.path,
        warnings,
      ),
    };
  }

  GenerationResult _generate(
    ClientProject project,
    String schemaPath,
    List<Diagnostic> warnings,
  ) {
    final types = SchemaTypeUsage(
      project.schema.schema,
    ).of(project.document.document);
    final names = GeneratedNames(
      mappedCoreTypes: [
        for (final mapping in config.scalars.values)
          if (mapping.type.library == null) mapping.type.name,
      ],
    );
    types.forEach(names.registerSchemaType);
    final mapper = TypeMapper(project.schema.schema, config.scalars);
    final libraries = DocumentLibraries(project, mapper, config.schemaTypes);
    _registerFiles(names, project);
    DocumentNameChecker(project, libraries.planner, names).check();
    final problems = names.diagnostics;
    if (problems.isNotEmpty) {
      return GenerationResult(const [], [...warnings, ...problems]);
    }
    final text = SchemaTypesEmitter(mapper).emit(types, source: schemaPath);
    final manifest = config.persistedOperations;
    return GenerationResult([
      GeneratedFile(config.schemaTypes, text),
      ...libraries.generate(),
      if (manifest != null)
        GeneratedFile(
          manifest,
          PersistedManifest(
            libraries.operationText,
          ).of(project.document.document),
        ),
    ], warnings);
  }

  // Two writers of one path would overwrite each other.
  void _registerFiles(GeneratedNames names, ClientProject project) {
    names.registerFile(config.schemaTypes, 'the schema types', null);
    final map = project.documents.sourceMap;
    final firstDefinitions = <int, SourceSpan>{};
    for (final definition in project.document.document.definitions) {
      firstDefinitions.putIfAbsent(
        map.fileIndexAt(definition.start),
        () => map.translate(
          SourceSpan(map.source, definition.start, definition.end),
        ),
      );
    }
    for (final (index, file) in project.documents.files.indexed) {
      names.registerFile(
        '${file.path}.dart',
        "the document '${file.path}'",
        firstDefinitions[index],
      );
    }
  }
}
