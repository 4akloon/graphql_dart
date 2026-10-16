import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_graphql_server/src/http/body_read_result.dart';
import 'package:typed_graphql_server/src/http/body_reader.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const reader = BodyReader(4, Duration(milliseconds: 50));

  test('joins several chunks', () async {
    final result = await reader.read(
      Stream.fromIterable([
        [1, 2],
        [3],
      ]),
    );
    expect((result as BodyBytes).bytes, [1, 2, 3]);
  });

  test('accepts a body of exactly maxBytes', () async {
    final result = await reader.read(Stream.value([1, 2, 3, 4]));
    expect((result as BodyBytes).bytes, [1, 2, 3, 4]);
  });

  test('refuses a body one byte longer and cancels the source', () async {
    var isCancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => isCancelled = true,
    );
    addTearDown(controller.close);
    controller.add([1, 2, 3]);
    controller.add([4, 5]);
    final result = await reader.read(controller.stream);
    expect(result, isA<BodyTooLarge>());
    expect(isCancelled, isTrue);
  });

  test('times out on a stream that never ends and cancels it', () async {
    var isCancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => isCancelled = true,
    );
    addTearDown(controller.close);
    final result = await reader.read(controller.stream);
    expect(result, isA<BodyTimedOut>());
    expect(isCancelled, isTrue);
  });

  test('times out on a stream that trickles bytes', () async {
    const patient = BodyReader(1000000, Duration(milliseconds: 30));
    final trickle = Stream<List<int>>.periodic(
      const Duration(milliseconds: 1),
      (_) => [1],
    );
    expect(await patient.read(trickle), isA<BodyTimedOut>());
  });

  test('reports an error of the stream as BodyFailed', () async {
    var isCancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => isCancelled = true,
    );
    addTearDown(controller.close);
    controller.addError(StateError('connection reset'));
    expect(await reader.read(controller.stream), isA<BodyFailed>());
    expect(isCancelled, isTrue);
  });

  test('reads an empty stream as empty bytes', () async {
    final result = await reader.read(const Stream<List<int>>.empty());
    expect((result as BodyBytes).bytes, isEmpty);
  });

  test('is not timed out by a body that arrives in time', () async {
    final result = await reader.read(Stream.value([1]));
    expect(result, isA<BodyBytes>());
  });

  test('does not leave its timer running when the stream cannot be '
      'listened to', () async {
    const quick = BodyReader(4, Duration(milliseconds: 1));
    final stream = StreamController<List<int>>().stream..listen(null);
    expect(() => quick.read(stream), throwsStateError);
    // A timer left running would fire here and read an unset subscription,
    // which the test runner reports as an uncaught error.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test(
    'copies chunks, so a host that reuses its buffer is read right',
    () async {
      final buffer = Uint8List(2);
      Stream<List<int>> reused() async* {
        for (final value in [1, 2, 3]) {
          buffer.fillRange(0, 2, value);
          yield buffer;
        }
      }

      final result = await const BodyReader(10, Duration(seconds: 5)).read(
        reused(),
      );
      expect((result as BodyBytes).bytes, [1, 1, 2, 2, 3, 3]);
    },
  );

  test('stops reading when the cancel signal fires', () async {
    var isCancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => isCancelled = true,
    );
    addTearDown(controller.close);
    final signal = CancelSignal();
    final pending = const BodyReader(
      10,
      Duration(seconds: 5),
    ).read(controller.stream, cancelSignal: signal);
    signal.cancel();
    expect(await pending, isA<BodyFailed>());
    expect(isCancelled, isTrue);
  });

  test('is failed at once by a signal that is already cancelled', () async {
    final signal = CancelSignal()..cancel();
    final result = await reader.read(
      Stream.value([1]),
      cancelSignal: signal,
    );
    expect(result, isA<BodyFailed>());
  });
}
