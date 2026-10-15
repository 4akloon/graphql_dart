import 'dart_writer.dart';

/// Writes the static `decode` of a fragment class, the entry point for a
/// fragment read outside an operation.
///
/// {@category codegen}
final class FragmentDecodeWriter {
  /// Creates the writer.
  const FragmentDecodeWriter();

  /// Writes `decode` for the class [className].
  void write(DartWriter writer, String className) {
    writer
      ..doc(
        'Reads [json], an object the fragment was spread on, in the response\n'
        'to an operation sent with [variables].',
      )
      ..line('static graphql.DecodeResult<$className> decode(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json, {')
          ..line('graphql.JsonObject? variables,');
      })
      ..line('}) => codec.decode(json, client.DataContext(variables));');
  }
}
