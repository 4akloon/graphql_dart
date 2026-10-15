import 'package:typed_graphql/typed_graphql.dart';

import 'dart_writer.dart';

/// Writes the static `decode` of an operation's data class, the entry point
/// for the `data` of a response.
///
/// {@category codegen}
final class OperationDecodeWriter {
  /// Creates the writer.
  const OperationDecodeWriter();

  /// Writes `decode` for the class [className], the data of [operation]; a
  /// non-empty [flagDefaults] is passed to the context.
  void write(
    DartWriter writer,
    String className,
    OperationDefinition operation,
    Map<String, bool> flagDefaults,
  ) {
    final String context = flagDefaults.isEmpty
        ? 'client.DataContext(variables)'
        : 'client.DataContext(variables, _flagDefaults)';
    writer
      ..doc(
        'Reads [json], the `data` of a response to the '
        '${operation.operation.name} sent with\n[variables].',
      )
      ..line('static graphql.DecodeResult<$className> decode(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json, {')
          ..line('graphql.JsonObject? variables,');
      })
      ..line('}) => codec.decode(json, $context);');
  }
}
