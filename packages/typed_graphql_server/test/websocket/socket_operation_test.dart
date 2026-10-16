import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/socket_error_reporter.dart';
import 'package:typed_graphql_server/src/websocket/socket_operation.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A [SocketOperation] over a `handle` the test controls.
final class OperationHarness {
  OperationHarness(this.handle) {
    operation = SocketOperation(
      id: '1',
      handle: (_) => handle.future,
      request: ServerRequest(
        params: const GraphQLRequest(query: '{ a }'),
        info: RequestInfo(method: 'POST', uri: Uri.parse('/graphql')),
        cancelSignal: signal,
      ),
      signal: signal,
      send: sent.add,
      onReleased: (_) => released++,
      reporter: SocketErrorReporter((error, _) => errors.add(error)),
    );
  }

  final Completer<ServerResponse> handle;
  final CancelSignal signal = CancelSignal();
  final List<String> sent = [];
  final List<Object> errors = [];
  int released = 0;
  late final SocketOperation operation;
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('cancel', () {
    test('fires the signal of the request', () async {
      final harness = OperationHarness(Completer<ServerResponse>());
      unawaited(harness.operation.run());
      harness.operation.cancel();
      expect(harness.signal.isCancelled, isTrue);
    });

    test('keeps the operation unreleased while the request runs', () async {
      final harness = OperationHarness(Completer<ServerResponse>());
      unawaited(harness.operation.run());
      harness.operation.cancel();
      await settle();
      expect(harness.released, 0);
      harness.handle.complete(
        SingleResponse(ExecutionResult(JsonObject({'a': JsonNumber(1)}))),
      );
      await settle();
      expect([harness.released, harness.sent], [1, isEmpty]);
    });

    test('cancels a stream that arrives after it', () async {
      final harness = OperationHarness(Completer<ServerResponse>());
      var isSourceCancelled = false;
      final source = StreamController<ExecutionResult>(
        onCancel: () => isSourceCancelled = true,
      );
      addTearDown(source.close);
      unawaited(harness.operation.run());
      harness.operation.cancel();
      harness.handle.complete(StreamResponse(source.stream));
      await settle();
      expect(isSourceCancelled, isTrue);
    });
  });

  group('failures', () {
    test('a source that fails after listening sends an error', () async {
      final harness = OperationHarness(Completer<ServerResponse>());
      final run = harness.operation.run();
      harness.handle.complete(
        StreamResponse(Stream<ExecutionResult>.error(StateError('late'))),
      );
      await run;
      await settle();
      expect(harness.sent.single, contains('"type":"error"'));
      expect(harness.sent.single, contains('GQL330'));
      expect(harness.errors.single, isA<StateError>());
      expect(harness.released, 1);
    });

    test('a handle that throws sends a masked error and reports it', () async {
      final harness = OperationHarness(Completer<ServerResponse>());
      final run = harness.operation.run();
      harness.handle.completeError(ArgumentError('bug'));
      await run;
      expect(harness.sent.single, contains('"type":"error"'));
      expect(harness.sent.single, isNot(contains('bug')));
      expect(harness.errors.single, isA<ArgumentError>());
      expect(harness.released, 1);
    });
  });
}
