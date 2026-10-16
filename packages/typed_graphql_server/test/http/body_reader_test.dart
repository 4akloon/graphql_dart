import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/src/http/body_read_result.dart';
import 'package:typed_graphql_server/src/http/body_reader.dart';

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
    final stopwatch = Stopwatch()..start();
    final result = await reader.read(controller.stream);
    expect(result, isA<BodyTimedOut>());
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
    expect(isCancelled, isTrue);
  });

  test('times out on a stream that trickles bytes', () async {
    const patient = BodyReader(1000, Duration(milliseconds: 100));
    final trickle = Stream<List<int>>.periodic(
      const Duration(milliseconds: 20),
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
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
}
