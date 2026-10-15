import 'dart_writer.dart';

/// Writes the `toJson` override of a generated class.
///
/// {@category codegen}
final class ToJsonWriter {
  /// Creates the writer.
  const ToJsonWriter();

  static const String _head = 'graphql.JsonObject toJson()';

  /// Writes `toJson` returning an object of the map [entries]: `'key': value`
  /// pairs and `...spreads`.
  ///
  /// One entry may move to the next line; several are written one per line
  /// once they do not fit on the head's line.
  void write(DartWriter writer, List<String> entries) {
    writer.line('@override');
    final String map = '{${entries.join(', ')}}';
    final String single = '$_head => graphql.JsonObject($map);';
    if (writer.fits(single)) {
      writer.line(single);
      return;
    }
    if (entries.length == 1) {
      writer.line('$_head =>');
      writer.indented(
        () => writer.indented(() => writer.line('graphql.JsonObject($map);')),
      );
      return;
    }
    writer.line('$_head => graphql.JsonObject({');
    writer.indented(() {
      for (final String entry in entries) {
        writer.line('$entry,');
      }
    });
    writer.line('});');
  }
}
