import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  test('a new token is not cancelled', () {
    final token = CancelToken();
    expect(token.isCancelled, isFalse);
    expect(token.reason, isNull);
  });

  test('cancel keeps the first reason', () {
    final token = CancelToken()
      ..cancel('first')
      ..cancel('second');
    expect(token.isCancelled, isTrue);
    expect(token.reason, 'first');
  });

  test('whenCancelled completes on cancel', () async {
    final token = CancelToken();
    var isDone = false;
    final done = token.whenCancelled.then((_) => isDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(isDone, isFalse);
    token.cancel();
    await done;
    expect(isDone, isTrue);
  });

  test('a listener runs once, at cancel', () {
    final token = CancelToken();
    var calls = 0;
    token.addListener(() => calls++);
    token
      ..cancel()
      ..cancel();
    expect(calls, 1);
  });

  test('a listener added after cancel runs at once', () {
    final token = CancelToken()..cancel();
    var calls = 0;
    token.addListener(() => calls++);
    expect(calls, 1);
  });

  test('a removed listener does not run and is not kept', () {
    final token = CancelToken();
    var calls = 0;
    final remove = token.addListener(() => calls++);
    expect(token.listenerCount, 1);
    remove();
    expect(token.listenerCount, 0);
    token.cancel();
    expect(calls, 0);
  });

  test('whenCancelled of a cancelled token is already complete', () async {
    final token = CancelToken()..cancel();
    await token.whenCancelled.timeout(const Duration(seconds: 1));
  });

  test('a listener removed by another during cancel does not run', () {
    final token = CancelToken();
    late final void Function() removeSecond;
    var secondCalls = 0;
    token.addListener(() => removeSecond());
    removeSecond = token.addListener(() => secondCalls++);
    token.cancel();
    expect(secondCalls, 1, reason: 'listeners are snapshotted at cancel');
  });
}
