import 'package:typed_graphql/typed_graphql.dart';

import '../execution/executable_schema.dart';
import 'build_options.dart';
import 'builder_checks.dart';
import 'input_value_assembler.dart';
import 'literal_writer.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'possible_types.dart';
import 'schema_bindings_assembler.dart';
import 'schema_build_error.dart';
import 'type_assembler.dart';

/// One run of `ExecutableSchemaBuilder.build`: definitions to a core schema,
/// the builder's checks, the core validator, then the binding tables.
final class ExecutableSchemaAssembly<C> {
  /// Prepares a run over [definitions] with the given root types.
  ExecutableSchemaAssembly({
    required this.definitions,
    required this.query,
    required this.mutation,
    required this.subscription,
    required this.options,
  });

  /// The definitions, in creation order.
  final List<NamedTypeDef> definitions;

  /// The query root.
  final ObjectTypeDef<Object?> query;

  /// The mutation root, null when there is none.
  final ObjectTypeDef<Object?>? mutation;

  /// The subscription root, null when there is none.
  final ObjectTypeDef<Object?>? subscription;

  /// The other settings.
  final BuildOptions options;

  /// Assembles the schema; throws [SchemaBuildError] on any problem.
  ExecutableSchema<C> assemble() {
    final problems = <Diagnostic>[];
    final possibleTypes = PossibleTypes(definitions);
    BuilderChecks(problems).check(definitions, possibleTypes);
    final schema = _schemaOf(problems);
    final result = const SchemaValidator().validate(schema);
    if (result case InvalidSchema(:final diagnostics)) {
      problems.addAll(diagnostics);
    }
    if (problems.any((problem) => problem.isError)) {
      throw SchemaBuildError(problems);
    }
    return ExecutableSchema(
      ValidSchema.assumeValid(schema),
      SchemaBindingsAssembler().assemble(definitions, possibleTypes),
      planCacheSize: options.planCacheSize,
    );
  }

  Schema _schemaOf(List<Diagnostic> problems) {
    final assembler = TypeAssembler(
      InputValueAssembler(LiteralWriter(definitions), problems),
    );
    return Schema(
      types: [
        for (final definition in definitions) assembler.assemble(definition),
      ],
      directives: options.directives,
      queryTypeName: query.name,
      mutationTypeName: mutation?.name,
      subscriptionTypeName: subscription?.name,
      description: options.description,
      includesDeferAndStream: options.includesDeferAndStream,
    );
  }
}
