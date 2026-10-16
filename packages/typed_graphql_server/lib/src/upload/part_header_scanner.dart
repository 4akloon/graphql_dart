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
  ///
  /// [boundary] is restricted to ASCII by the caller, so its bytes are its
  /// code units, as `package:mime` reads it.
  PartHeaderScanner(String boundary, this.maxHeaderBytes)
    : _delimiter = SequenceMatcher(utf8.encode('\r\n--$boundary')),
      _headerEnd = SequenceMatcher(const [13, 10, 13, 10]) {
    // The parser starts as if a CRLF had come before the body, so the first
    // delimiter is `--boundary` at byte 0 or after a CRLF, never in the
    // middle of a preamble line.
    _delimiter
      ..feed(13)
      ..feed(10);
  }

  /// The most bytes the headers of one part may take, delimiter line
  /// excluded.
  final int maxHeaderBytes;

  // After a part's headers it needs the whole `CRLF--boundary`, because the
  // blank line's CRLF is the end of the headers, not the start of the
  // delimiter.
  final SequenceMatcher _delimiter;
  final SequenceMatcher _headerEnd;
  bool _isInHeaders = false;
  bool _isClosed = false;
  bool _hasStarted = false;
  bool _isOnDelimiterLine = false;
  int _dashes = 0;
  int _headerBytes = 0;

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
      _isOnDelimiterLine = true;
      _dashes = 0;
      _headerBytes = 0;
      _headerEnd.reset();
    }
    return true;
  }

  bool _admitHeaderByte(int byte) {
    _headerBytes++;
    if (_isOnDelimiterLine && _closesAt(byte)) {
      _isClosed = true;
      return true;
    }
    if (_headerBytes > maxHeaderBytes) return false;
    if (_headerEnd.feed(byte)) {
      _isInHeaders = false;
      _delimiter.reset();
    }
    return true;
  }

  // The parser allows spaces and tabs (transport padding) after a delimiter,
  // so `--` after them is the closing delimiter.
  bool _closesAt(int byte) {
    if (_dashes == 0 && (byte == 0x20 || byte == 0x09)) return false;
    if (byte == 0x2d && ++_dashes == 2) return true;
    if (byte != 0x2d) _isOnDelimiterLine = false;
    return false;
  }
}
