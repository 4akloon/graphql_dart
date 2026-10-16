import 'package:meta/meta.dart';

/// One event of an event stream: its type and its data lines joined with
/// line feeds (WHATWG HTML, "Interpreting an event stream").
@internal
final class const ServerSentEvent({
  /// The `event` field, or `message` when the stream gave none.
  required final String event,

  /// The `data` lines, joined with `\n`; empty when there were none.
  required final String data,
}) {
  /// Creates an event.
  this;

  @override
  String toString() => 'ServerSentEvent($event, $data)';
}
