/// The typed_graphql code generator and its CLI: Dart client code from .graphql
/// operations and SDL-first server code, without the analyzer.
///
/// Under construction: so far the package reads `typed_graphql.yaml`
/// ([CodegenConfig]) and [ClientGenerator] writes the Dart enums and input
/// objects of the schema; see the package README.
library;

export 'src/cli/codegen_command.dart';
export 'src/cli/codegen_command_line.dart';
export 'src/cli/command_line_result.dart';
export 'src/cli/diagnostic_printer.dart';
export 'src/cli/output_writer.dart';
export 'src/cli/project_read_result.dart';
export 'src/cli/project_reader.dart';
export 'src/config/codegen_config.dart';
export 'src/config/config_result.dart';
export 'src/config/dart_reference.dart';
export 'src/config/scalar_mapping.dart';
export 'src/config/schema_location.dart';
export 'src/generator/client_generator.dart';
export 'src/generator/generated_file.dart';
export 'src/generator/generation_result.dart';
export 'src/project/project_file.dart';
export 'src/schema/schema_load_result.dart';
export 'src/schema/schema_loader.dart';
