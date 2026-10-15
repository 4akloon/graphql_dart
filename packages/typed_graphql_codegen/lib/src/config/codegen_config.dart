import 'package:typed_graphql/typed_graphql.dart';

import 'config_reader.dart';
import 'config_result.dart';
import 'scalar_mapping.dart';
import 'schema_location.dart';

/// The settings of `typed_graphql.yaml` (R7.1), read by [parse].
///
/// {@category codegen}
final class CodegenConfig {
  /// Creates a configuration; every argument but [schema] has the default the
  /// file's missing key has.
  const CodegenConfig({
    required this.schema,
    this.documents = const ['lib/**.graphql'],
    this.schemaTypes = 'lib/schema.graphql.dart',
    this.persistedOperations,
    this.scalars = const {},
    this.headers = const {},
  });

  /// Reads the text of the configuration file at [path].
  ///
  /// Bad input never throws: a YAML syntax error is one `GQL500`, every other
  /// problem a `GQL501`, all in a [ConfigFailure]. [path] only names the file
  /// in the diagnostics.
  static ConfigResult parse(String text, {required String path}) =>
      ConfigReader(Source(text, name: path)).read(text);

  /// Where the schema is: a file or an endpoint.
  final SchemaLocation schema;

  /// The globs, relative to the configuration file, of the `.graphql`
  /// operation documents.
  final List<String> documents;

  /// The path of the generated schema types file, ending with `.dart`.
  final String schemaTypes;

  /// The path of the persisted operations manifest, ending with `.json`; null
  /// when none is written.
  final String? persistedOperations;

  /// The custom scalar mappings by scalar name, sorted by name.
  final Map<String, ScalarMapping> scalars;

  /// The HTTP headers of the introspection request by name, sorted by name;
  /// values are raw, `${NAME}` is not expanded.
  final Map<String, String> headers;
}
