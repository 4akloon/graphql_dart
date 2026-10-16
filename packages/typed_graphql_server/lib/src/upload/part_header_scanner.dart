import 'dart:convert';

import 'package:meta/meta.dart';

import 'sequence_matcher.dart';

/// Measures the headers of the parts of a multipart body as its bytes go by,
/// so that a header of any size is refused before `package:mime` buffers it.
///
/// It follows the framing only: a delimiter line starts the headers of a
/// part, a blank line ends them, and the closing delimiter ends the scan.
/// A byte count is all it keeps, so it costs nothing per part. Where it and
/// the parser disagree on a malformed body, the parser still decides what the
/// body means; the scanner only bounds the bytes a header may take.
@internal
final class PartHeaderScanner {
  /// Creates a scanner for a body whose parts are separated by [boundary],
  /// allowing [maxHeaderBytes] bytes for the headers of each part.
  PartHeaderScanner(String boundary, this.maxHeaderBytes)
    : _delimiter = SequenceMatcher(utf8.encode('\r\n--$boundary')),
      _headerEnd = SequenceMatcher(const [13, 10, 13, 10]) {
    _startLine();
  }

  /// The most bytes the headers of one part may take, delimiter line
  /// excluded.
  final int maxHeaderBytes;

  final SequenceMatcher _delimiter;
  final SequenceMatcher _headerEnd;
  bool _isInHeaders = false;
  bool _isClosed = false;
  bool _hasStarted = false;
  int _headerBytes = 0;
  int _previousByte = 0;

  /// Whether a delimiter has begun a part and the closing delimiter has not
  /// come: a body that ends now is cut.
  bool get isCut => _hasStarted && !_isClosed;

  /// Reads [chunk] and tells whether no header passed [maxHeaderBytes].
  bool admits(List<int> chunk) {
    for (final byte in chunk) {
      if (_isClosed) return true;
      final isWithin = _isInHeaders ? _admitHeaderByte(byte) : _skipBody(byte);
      if (!isWithin) return false;
    }
    return true;
  }

  bool _skipBody(int byte) {
    if (_delimiter.feed(byte)) {
      _hasStarted = true;
      _isInHeaders = true;
      _headerBytes = 0;
      _headerEnd.reset();
    }
    return true;
  }

  bool _admitHeaderByte(int byte) {
    _headerBytes++;
    // `--` straight after the delimiter is the closing delimiter.
    if (_headerBytes == 2 && _previousByte == 0x2d && byte == 0x2d) {
      _isClosed = true;
      return true;
    }
    _previousByte = byte;
    if (_headerEnd.feed(byte)) {
      _isInHeaders = false;
      _startLine();
      return true;
    }
    return _headerBytes <= maxHeaderBytes;
  }

  // The blank line that ends the headers also ends a line, so a delimiter
  // may follow it at once (the same for the start of the body).
  void _startLine() {
    _delimiter
      ..reset()
      ..feed(13)
      ..feed(10);
  }
}
