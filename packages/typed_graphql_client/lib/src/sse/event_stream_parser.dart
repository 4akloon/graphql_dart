import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'event_assembler.dart';
import 'event_stream_error.dart';
import 'server_sent_event.dart';

/// Reads an event stream from bytes as WHATWG HTML's "Interpreting an
/// event stream" describes, in bounded memory (spec section 9, R8.4).
///
/// The bytes are decoded as strict UTF-8 across chunk boundaries. The
/// stream of events fails with an [EventStreamError] for hostile input:
/// bytes that are not UTF-8 or an event longer than `maxEventBytes`; either
/// way the body is cancelled. An `Exception` of the body stream passes on
/// unchanged. An event the body ends in the middle of is dropped, as in a
/// browser.
@internal
final class const EventStreamParser({
  /// The most bytes one event, or the line being read, may hold.
  required final int maxEventBytes,
}) {
  /// Creates a parser.
  this;

  /// The events of [bytes], in order. The returned stream listens to
  /// [bytes] when it is listened to and cancels it when it is cancelled.
  Stream<ServerSentEvent> parse(Stream<List<int>> bytes) {
    final assembler = EventAssembler(maxEventBytes: maxEventBytes);
    final collector = _TextCollector();
    final decoder = utf8.decoder.startChunkedConversion(collector);
    return bytes.transform(
      StreamTransformer<List<int>, ServerSentEvent>.fromHandlers(
        handleData: (chunk, sink) {
          final events = <ServerSentEvent>[];
          final failure = _read(chunk, (decoder, collector, assembler), events);
          events.forEach(sink.add);
          if (failure != null) throw failure;
        },
        handleDone: (sink) {
          try {
            decoder.close();
          } on FormatException {
            sink.addError(const EventStreamNotUtf8());
          }
          sink.close();
        },
      ),
    );
  }

  String _validPrefix(List<int> chunk) {
    final text = const Utf8Decoder(allowMalformed: true).convert(chunk);
    final end = text.indexOf('\u{FFFD}');
    return end < 0 ? text : text.substring(0, end);
  }

  /// Feeds [chunk] through the decoder and the assembler, adding every event
  /// completed before a failure to [events]; the failure, if any, is
  /// returned so that the events are delivered first.
  EventStreamError? _read(
    List<int> chunk,
    (Sink<List<int>>, _TextCollector, EventAssembler) parts,
    List<ServerSentEvent> events,
  ) {
    final (decoder, collector, assembler) = parts;
    EventStreamError? failure;
    try {
      decoder.add(chunk);
    } on FormatException {
      failure = const EventStreamNotUtf8();
      // The strict decoder yields nothing for a failed chunk: read the text
      // before the first replacement character, so that the events
      // completed before the bad bytes are not lost.
      collector.add(_validPrefix(chunk));
    }
    try {
      assembler.add(collector.take(), events);
    } on EventStreamTooLarge catch (error) {
      failure = error;
    }
    return failure;
  }
}

/// The text the decoder has produced since the last [take].
final class _TextCollector implements Sink<String> {
  final StringBuffer _text = StringBuffer();

  @override
  void add(String data) => _text.write(data);

  @override
  void close() {}

  String take() {
    final text = _text.toString();
    _text.clear();
    return text;
  }
}
