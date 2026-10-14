/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
