import 'package:meta/meta.dart';

import 'event_stream_error.dart';
import 'server_sent_event.dart';

/// Splits decoded event-stream text into lines and lines into events,
/// counting the bytes it holds so a hostile stream cannot grow it (R0.3).
///
/// Only the lines that build the event (`data` and `event`) and the line
/// being read count; comments and ignored fields are dropped as soon as
/// their line ends, so a stream of them runs forever in constant memory.
@internal
final class EventAssembler({
  /// The most bytes one event, with the line being read, may hold.
  required final int maxEventBytes,
}) {
  /// Creates an assembler for one stream.
  this;

  static const int _lineFeed = 0x0A;
  static const int _carriageReturn = 0x0D;
  static const int _byteOrderMark = 0xFEFF;

  final StringBuffer _line = StringBuffer();
  final StringBuffer _data = StringBuffer();
  String? _type;
  bool _hasData = false;
  bool _isAtStart = true;
  bool _skipsLineFeed = false;
  int _lineBytes = 0;
  int _eventBytes = 0;

  /// Reads [text], the next piece of the stream, and adds the events it
  /// completes to [events]. Throws [EventStreamTooLarge] past the limit,
  /// after adding the events completed before the line that passed it.
  void add(String text, List<ServerSentEvent> events) {
    for (final unit in text.codeUnits) {
      if (_isAtStart) {
        _isAtStart = false;
        if (unit == _byteOrderMark) continue;
      }
      if (_skipsLineFeed) {
        _skipsLineFeed = false;
        if (unit == _lineFeed) continue;
      }
      switch (unit) {
        case _carriageReturn:
          _skipsLineFeed = true;
          _endLine(events);
        case _lineFeed:
          _endLine(events);
        default:
          _append(unit);
      }
    }
  }

  void _append(int unit) {
    _line.writeCharCode(unit);
    _lineBytes += _utf8Length(unit);
    if (_eventBytes + _lineBytes > maxEventBytes) {
      throw EventStreamTooLarge(maxEventBytes);
    }
  }

  /// The bytes a UTF-16 code unit takes in UTF-8; a surrogate pair is two
  /// units of two bytes, four in all.
  int _utf8Length(int unit) => switch (unit) {
    < 0x80 => 1,
    < 0x800 => 2,
    >= 0xD800 && <= 0xDFFF => 2,
    _ => 3,
  };

  void _endLine(List<ServerSentEvent> events) {
    final line = _line.toString();
    final bytes = _lineBytes;
    _line.clear();
    _lineBytes = 0;
    if (line.isEmpty) {
      _dispatch(events);
    } else if (!line.startsWith(':')) {
      _readField(line, bytes);
    }
  }

  void _readField(String line, int bytes) {
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    switch (field) {
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'event':
        _type = value;
      default:
        return;
    }
    _eventBytes += bytes + 1;
    if (_eventBytes > maxEventBytes) {
      throw EventStreamTooLarge(maxEventBytes);
    }
  }

  /// A blank line ends the event. It is dispatched when it has a type or
  /// data, which WHATWG does not do for an empty data buffer: graphql-sse's
  /// `complete` carries a type and no data. An empty `data:` line alone
  /// dispatches nothing.
  void _dispatch(List<ServerSentEvent> events) {
    final type = _type;
    final data = _data.toString();
    if ((type != null && type.isNotEmpty) || data.isNotEmpty) {
      events.add(
        ServerSentEvent(
          event: type == null || type.isEmpty ? 'message' : type,
          data: data,
        ),
      );
    }
    _type = null;
    _data.clear();
    _hasData = false;
    _eventBytes = 0;
  }
}
