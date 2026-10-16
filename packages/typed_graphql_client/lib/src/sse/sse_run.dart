import 'dart:async';

import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import '../http/http_transport.dart';
import '../http/media_type.dart';
import '../http/redacted_error.dart';
import '../http/response_reader.dart';
import '../http/transport_request.dart';
import '../http/transport_response.dart';
import '../link/http_response_info.dart';
import '../link/link_context.dart';
import '../link/link_result.dart';
import 'event_stream_error.dart';
import 'event_stream_parser.dart';
import 'server_sent_event.dart';

/// One request of `SseLink`: sends it, then relays the answer to
/// the stream of [open] until the server completes, a failure comes or the
/// caller cancels. It ends the connection, through the abort trigger,
/// whenever it stops listening to the answer.
@internal
final class SseRun({
  /// Sends the request.
  required final HttpTransport transport,
  required final ResponseReader reader,
  required final EventStreamParser parser,
}) {
  /// Creates the run of one request.
  this;

  final StreamController<LinkResult> _controller =
      StreamController<LinkResult>();
  final Completer<void> _abort = Completer<void>();
  StreamSubscription<ServerSentEvent>? _events;
  bool _isFinished = false;

  /// The results of the request [encode] writes (given the request's abort
  /// trigger), sent when the stream is listened to. Call it once.
  Stream<LinkResult> open(
    TransportRequest Function(Future<void> abortTrigger) encode,
  ) {
    _controller
      ..onListen = (() => unawaited(_send(encode)))
      ..onPause = (() => _events?.pause())
      ..onResume = (() => _events?.resume())
      ..onCancel = _stop;
    return _controller.stream;
  }

  /// The listener cancelled: ends the connection and the body.
  Future<void> _stop() async {
    _isFinished = true;
    _release();
    await _events?.cancel();
  }

  Future<void> _send(
    TransportRequest Function(Future<void> abortTrigger) encode,
  ) async {
    final TransportResponse response;
    try {
      response = await transport.send(encode(_abort.future));
    } on Exception catch (error) {
      _finish(LinkFailure(NetworkFailure(RedactedError(error))));
      return;
    }
    if (_isFinished) {
      unawaited(response.body.listen((_) {}).cancel());
      return;
    }
    final type = MediaType.parse(response.headers['content-type']);
    final isStream =
        response.statusCode >= 200 &&
        response.statusCode < 300 &&
        type.essence == MediaType.eventStream;
    if (!isStream) {
      await _readSingle(response);
    } else if (!type.isUtf8) {
      _finish(
        LinkFailure(
          ResponseFormatFailure(
            .unsupportedResponseType,
            'The response is in charset "${type.charset}"; only UTF-8 is '
            'read.',
          ),
        ),
      );
    } else {
      _listen(response);
    }
  }

  /// An answer that is not an event stream is one result, read as
  /// `HttpLink` reads it.
  Future<void> _readSingle(TransportResponse response) async {
    try {
      _finish(await reader.read(response));
    } on Exception catch (error) {
      _finish(LinkFailure(NetworkFailure(RedactedError(error))));
    }
  }

  void _listen(TransportResponse response) {
    final context = LinkContext([
      HttpResponseInfo(response.statusCode, headers: response.headers),
    ]);
    _events = parser
        .parse(response.body)
        .listen(
          (event) => _onEvent(event, context),
          onError: _onError,
          onDone: () => _finish(
            const LinkFailure(
              EventStreamFailure(
                'The event stream ended without a complete event.',
              ),
            ),
          ),
          cancelOnError: true,
        );
    // Paused before the answer arrived: there was no body to pause yet.
    if (_controller.isPaused) _events?.pause();
  }

  void _onEvent(ServerSentEvent event, LinkContext context) {
    switch (event.event) {
      case 'next':
        final result = reader.resultOf(event.data, context);
        if (result is LinkFailure) {
          _finish(result);
        } else {
          _controller.add(result);
        }
      case 'complete':
        _finish();
      case final other:
        _finish(
          LinkFailure(
            EventStreamFailure(
              'The event stream sent an event of type "$other", which '
              'graphql-sse does not define.',
            ),
          ),
        );
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    switch (error) {
      case EventStreamTooLarge():
        _finish(
          LinkFailure(
            ResponseFormatFailure(.responseTooLarge, error.toString()),
          ),
        );
      case EventStreamNotUtf8():
        _finish(
          LinkFailure(
            ResponseFormatFailure(.malformedResponse, error.toString()),
          ),
        );
      case Exception():
        _finish(LinkFailure(NetworkFailure(RedactedError(error))));
      default:
        if (!_isFinished) _controller.addError(error, stackTrace);
        _finish();
    }
  }

  /// Ends the run, after [last] if there is one; the first end wins.
  void _finish([LinkResult? last]) {
    if (_isFinished) return;
    _isFinished = true;
    if (last != null) _controller.add(last);
    unawaited(_events?.cancel());
    _release();
    unawaited(_controller.close());
  }

  /// Tells the transport the answer is no longer read; harmless once the
  /// body has ended.
  void _release() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }
}
