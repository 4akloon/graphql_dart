import 'source_location.dart';

/// The text of a GraphQL document and the name diagnostics show for it.
///
/// Offsets into [body] count UTF-16 code units, as `String.codeUnitAt`
/// does. [locationOf] turns an offset into a line and a column; the table of
/// line starts it needs is built on the first call, so a document that
/// reports no location is scanned only by the lexer.
///
/// {@category diagnostics}
final class Source(
  /// The document text.
  final String body, {

  /// The name diagnostics show: a file path, or `GraphQL request` (the
  /// name graphql-js uses) for a document that came over the wire.
  final String name = 'GraphQL request',
}) {
  /// Creates a source for [body].
  this;

  static const int _lineFeed = 0x0A;
  static const int _carriageReturn = 0x0D;

  // `late`: built on the first [locationOf] call and never before; most
  // documents never need a line or a column (spec §2).
  late final List<int> _lineStarts = _scanLineStarts();

  /// The line and column of [offset], both 1-based, the column in UTF-16
  /// code units.
  ///
  /// A line ends with `\r\n`, `\n` or a lone `\r` (spec §2.1.3,
  /// "LineTerminator"), as graphql-js `getLocation` counts them. [offset]
  /// may equal the length of [body], the end of the document; outside
  /// `0..body.length` it is a [RangeError].
  SourceLocation locationOf(int offset) {
    RangeError.checkValueInInterval(offset, 0, body.length, 'offset');
    final line = _lineIndexOf(offset);
    return SourceLocation(line + 1, offset - _lineStarts[line] + 1);
  }

  /// The index in [_lineStarts] of the last line that starts at or before
  /// [offset]: a binary search, since the starts ascend.
  int _lineIndexOf(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_lineStarts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The offset where each line starts: 0, then the offset after every line
  /// terminator. A `\r` directly before a `\n` is part of that terminator.
  List<int> _scanLineStarts() {
    final starts = [0];
    for (var i = 0; i < body.length; i++) {
      final unit = body.codeUnitAt(i);
      if (unit == _carriageReturn && _isLineFeedAt(i + 1)) {
        continue;
      }
      if (unit == _lineFeed || unit == _carriageReturn) {
        starts.add(i + 1);
      }
    }
    return List.unmodifiable(starts);
  }

  /// Whether the code unit at [offset] exists and is `\n`.
  bool _isLineFeedAt(int offset) =>
      offset < body.length && body.codeUnitAt(offset) == _lineFeed;
}
