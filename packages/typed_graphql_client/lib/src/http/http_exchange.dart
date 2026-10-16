import 'dart:async';

import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import '../link/link_result.dart';
import 'http_transport.dart';
import 'response_reader.dart';
import 'transport_request.dart';

/// Runs HTTP requests that have one answer each: sends, reads, applies the
/// timeout and aborts the request when its stream is cancelled (spec
/// section 9).
@internal
final class HttpExchange({
  /// Sends the requests.
  required final HttpTransport transport,

  /// Reads the answers.
  required final ResponseReader reader,

  /// How long one request may take, from sending to the end of the body;
  /// null for no limit.
  final Duration? timeout,
}) {
  /// Creates an exchange.
  this;

  /// The one result of the request [encode] writes, sent when the stream
  /// is listened to; [encode] gets the request's abort trigger.
  Stream<LinkResult> run(
    TransportRequest Function(Future<void> abortTrigger) encode,
  ) {
    final abort = Completer<void>();
    final controller = StreamController<LinkResult>(
      onCancel: () => _release(abort),
    );
    controller.onListen = () => unawaited(
      _attempt(encode, abort).then(
        (result) {
          _release(abort);
          controller.add(result);
          return controller.close();
        },
        onError: (Object error, StackTrace stackTrace) {
          _release(abort);
          controller.addError(error, stackTrace);
          return controller.close();
        },
      ),
    );
    return controller.stream;
  }

  Future<LinkResult> _attempt(
    TransportRequest Function(Future<void> abortTrigger) encode,
    Completer<void> abort,
  ) async {
    final exchange = _exchange(encode(abort.future));
    final limit = timeout;
    if (limit == null) {
      return exchange;
    }
    final timedOut = Completer<LinkResult>();
    final timer = Timer(limit, () {
      _release(abort);
      timedOut.complete(LinkFailure(RequestTimedOut(limit)));
    });
    try {
      return await Future.any([exchange, timedOut.future]);
    } finally {
      timer.cancel();
    }
  }

  Future<LinkResult> _exchange(TransportRequest request) async {
    try {
      return await reader.read(await transport.send(request));
    } on Exception catch (error) {
      return LinkFailure(NetworkFailure(error));
    }
  }

  /// Tells the transport the answer is no longer read; harmless once the
  /// body has ended.
  void _release(Completer<void> abort) {
    if (!abort.isCompleted) {
      abort.complete();
    }
  }
}
