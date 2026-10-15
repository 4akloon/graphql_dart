import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'introspection_file_reader.dart';
import 'schema_load_result.dart';

/// Reads the schema file of a project: SDL, or an introspection result when
/// the path ends in `.json`.
///
/// {@category codegen}
final class const SchemaLoader() {
  /// Creates a loader.
  this;

  /// Builds and validates the schema [file] holds; never throws.
  SchemaLoadResult load(ProjectFile file) {
    final source = Source(file.text, name: file.path);
    final built = file.path.endsWith('.json')
        ? const IntrospectionFileReader().read(file.text, source)
        : _fromSdl(source);
    return switch (built) {
      BuildFailure(:final diagnostics) => SchemaNotLoaded(diagnostics),
      BuildSuccess(:final schema) => switch (const SchemaValidator().validate(
        schema,
      )) {
        final ValidSchema valid => SchemaLoaded(valid),
        InvalidSchema(:final diagnostics) => SchemaNotLoaded(diagnostics),
      },
    };
  }

  BuildResult _fromSdl(Source source) {
    // A schema is the developer's own file: only the operation token limit
    // is lifted. `@defer` is known so that the generator's own rule reports
    // it instead of an unknown directive.
    final parsed = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source);
    return switch (parsed) {
      ParseFailure(:final diagnostics) => BuildFailure(Schema(), diagnostics),
      ParseSuccess(:final document) => const SchemaBuilder(
        includesDeferAndStream: true,
      ).fromSdl(document, source: source),
    };
  }
}
