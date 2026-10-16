import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/http_response_body.dart';
import '../http/http_response_data.dart';
import '../server/header_names.dart';
import 'event_stream_writer.dart';

/// An event stream: the `200` response that carries a stream of payloads as
/// server-sent events (spec section 10).
///
/// The body is backed by a controller whose pause, resume and cancel are the
/// source's, so a slow client slows the operation down and a client that goes
/// away stops it. The source is not listened to until the host listens to the
/// body.
@internal
final class EventStream {
  /// Creates a stream of the payloads of [source].
  ///
  /// A comment is written every [keepAliveInterval] while the stream is idle,
  /// and a `complete` event follows the last payload.
  EventStream(Stream<JsonValue> source, {required this.keepAliveInterval})
    : _frames = source.map(_writer.next),
      sendsComplete = true;

  /// Creates a stream that writes [frames] as they are, already encoded, and
  /// never ends by itself.
  ///
  /// Single connection mode uses it: its events carry operation ids, and the
  /// stream lasts until the client goes away.
  EventStream.frames(this._frames, {required this.keepAliveInterval})
    : sendsComplete = false;

  /// The headers of an event stream. There is no `connection` header: it is
  /// hop-by-hop and forbidden in HTTP/2 (spec deviation 11).
  static const Map<String, String> headers = {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
  };

  final Stream<List<int>> _frames;

  /// How long the stream may stay silent before a comment is written.
  final Duration keepAliveInterval;

  /// Whether a `complete` event follows the last payload.
  final bool sendsComplete;

  static const EventStreamWriter _writer = EventStreamWriter();

  // Late so that the callbacks can be instance methods.
  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(
        onListen: _start,
        onPause: _pause,
        onResume: _resume,
        onCancel: _stop,
      );

  StreamSubscription<List<int>>? _subscription;
  Timer? _keepAlive;

  /// The `200` response, with [extraHeaders] (such as those of the pipeline's
  /// response) under the event stream's own; it varies on `Accept`, because
  /// the same URL answers JSON to another `Accept`.
  HttpResponseData response({Map<String, String> extraHeaders = const {}}) =>
      HttpResponseData(
        200,
        headers: const HeaderNames().varied(
          const HeaderNames().merged(
            const HeaderNames().lowerCased(extraHeaders),
            headers,
          ),
          'accept',
        ),
        body: StreamedBody(_controller.stream),
      );

  // The first comment flushes the headers through proxies before any
  // operation has produced anything.
  void _start() {
    _write(_writer.comment());
    _subscription = _frames.listen(
      _write,
      // Unreachable today: the pipeline turns a failing source into a `GQL340`
      // result. If one ever fails, the stream ends without `complete`, so the
      // client does not read a clean end.
      onError: (Object _) => _finish(withComplete: false),
      onDone: () => _finish(withComplete: sendsComplete),
      cancelOnError: true,
    );
  }

  void _write(List<int> bytes) {
    if (_controller.isClosed) return;
    _controller.add(bytes);
    _keepAlive?.cancel();
    _keepAlive = Timer(keepAliveInterval, _writeKeepAlive);
  }

  // A paused client already has bytes it has not read: another comment would
  // only grow the buffer.
  void _writeKeepAlive() {
    if (_controller.isPaused) {
      _keepAlive = Timer(keepAliveInterval, _writeKeepAlive);
    } else {
      _write(_writer.comment());
    }
  }

  void _finish({required bool withComplete}) {
    _keepAlive?.cancel();
    if (withComplete) _controller.add(_writer.complete());
    _controller.close().ignore();
  }

  void _pause() => _subscription?.pause();

  void _resume() => _subscription?.resume();

  Future<void> _stop() {
    _keepAlive?.cancel();
    return _subscription?.cancel() ?? Future<void>.value();
  }
}
