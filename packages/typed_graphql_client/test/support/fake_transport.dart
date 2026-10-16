import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql_client/typed_graphql_client.dart';

/// An [HttpTransport] for tests: it records every request and its body and
/// answers with the queued answers, first in, first out.
final class FakeTransport implements HttpTransport {
  final List<Future<TransportResponse> Function(TransportRequest request)>
  _answers = [];

  /// Every request received, in order.
  final List<TransportRequest> requests = [];

  /// The body of every request, as UTF-8 text (malformed bytes replaced).
  final List<String> bodies = [];

  /// Queues an answer of [body] with [status] and [contentType].
  void answer(
    String body, {
    int status = 200,
    String contentType = 'application/graphql-response+json',
  }) => answerWith(
    (request) async => TransportResponse(
      statusCode: status,
      headers: {'content-type': contentType},
      body: Stream.value(utf8.encode(body)),
    ),
  );

  /// Queues an answer computed from the request.
  void answerWith(
    Future<TransportResponse> Function(TransportRequest request) answer,
  ) => _answers.add(answer);

  /// Queues an answer that never comes: the request fails with
  /// [TransportAborted] once its abort trigger completes.
  void hang() => answerWith((request) {
    final answer = Completer<TransportResponse>();
    unawaited(
      request.abortTrigger?.then(
        (_) => answer.completeError(const TransportAborted()),
      ),
    );
    return answer.future;
  });

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    final bytes = await (request.body ?? const Stream<List<int>>.empty())
        .expand((chunk) => chunk)
        .toList();
    bodies.add(utf8.decode(bytes, allowMalformed: true));
    if (_answers.isEmpty) {
      throw StateError('FakeTransport has no answer for ${request.uri}.');
    }
    return _answers.removeAt(0)(request);
  }
}

/// What [FakeTransport] throws for an aborted request.
final class TransportAborted implements Exception {
  /// Creates the exception.
  const TransportAborted();

  @override
  String toString() => 'TransportAborted';
}
