import 'package:yaml/yaml.dart';

import 'codegen_config.dart';
import 'scalar_mapping.dart';
import 'schema_location.dart';

/// The values read so far from a configuration, with the defaults of the keys
/// not met yet.
final class ConfigDraft {
  /// The location of the schema; null until a valid `schema` is read.
  SchemaLocation? schema;

  /// The `documents` globs.
  List<String> documents = CodegenConfig.defaultDocuments;

  /// The `schema_types` path.
  String schemaTypes = CodegenConfig.defaultSchemaTypes;

  /// The `persisted_operations` path, if any.
  String? persistedOperations;

  /// The `scalars` mappings.
  Map<String, ScalarMapping> scalars = const {};

  /// The `headers`.
  Map<String, String> headers = const {};

  /// The `headers` key, when the file has one.
  YamlNode? headersKey;

  /// The configuration, or null when [schema] was not read.
  CodegenConfig? build() {
    final location = schema;
    if (location == null) return null;
    return CodegenConfig(
      schema: location,
      documents: List.unmodifiable(documents),
      schemaTypes: schemaTypes,
      persistedOperations: persistedOperations,
      scalars: Map.unmodifiable(scalars),
      headers: Map.unmodifiable(headers),
    );
  }
}
