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

  /// Writes `toJson` returning the deep merge of the JSON of [merged] (such
  /// as `fragments.toJson()`) and an object of the map [entries].
  ///
  /// Shallow `...spreads` would let one side's value for a response name
  /// replace the other's, losing the sub-fields it selected; `JsonMerger`
  /// merges them. Without [entries] and with one expression, it is that
  /// expression.
  void writeMerged(
    DartWriter writer,
    List<String> merged, {
    List<String> entries = const [],
  }) {
    writer.line('@override');
    final parts = [
      ...merged,
      if (entries.isNotEmpty) 'graphql.JsonObject({${entries.join(', ')}})',
    ];
    if (parts.length == 1) {
      writer.arrow(_head, parts.single);
      return;
    }
    const String call = 'const client.JsonMerger().merge(';
    final String single = '$_head => $call[${parts.join(', ')}]);';
    if (writer.fits(single)) {
      writer.line(single);
      return;
    }
    writer.line('$_head => $call[');
    writer.indented(() {
      for (final String expression in merged) {
        writer.line('$expression,');
      }
      if (entries.isNotEmpty) {
        writer.items('graphql.JsonObject({', entries, '}),');
      }
    });
    writer.line(']);');
  }
}
