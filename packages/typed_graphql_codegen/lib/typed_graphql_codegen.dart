/// The typed_graphql code generator and its CLI: Dart client code from .graphql
/// operations and SDL-first server code, without the analyzer.
///
/// Under construction: so far the package reads `typed_graphql.yaml`
/// ([CodegenConfig]); see the package README.
library;

export 'src/config/codegen_config.dart';
export 'src/config/config_result.dart';
export 'src/config/dart_reference.dart';
export 'src/config/scalar_mapping.dart';
export 'src/config/schema_location.dart';
export 'src/project/project_file.dart';
export 'src/schema/schema_load_result.dart';
export 'src/schema/schema_loader.dart';
