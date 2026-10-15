import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A batch function that gives key `n` the list `[n, n]` and records calls.
final class Recorder {
  final List<List<int>> calls = [];

  Map<int, List<int>> pairs(List<int> keys) {
    calls.add(keys);
    return {
      for (final key in keys) key: [key, key],
    };
  }
}

void main() {
  test('loads of one synchronous pass make one call', () async {
    final recorder = Recorder();
    final loader = GroupedLoader<int, int>(recorder.pairs);
    final results = await Future.wait([loader.load(2), loader.load(1)]);
    expect(recorder.calls, [
      [2, 1],
    ]);
    expect(results, [
      [2, 2],
      [1, 1],
    ]);
  });

  test('a key the batch function leaves out is an empty list', () async {
    final loader = GroupedLoader<int, int>(
      (keys) => {
        1: [1],
      },
    );
    expect(await loader.load(2), isEmpty);
  });

  test('the returned list is unmodifiable', () async {
    final loader = GroupedLoader<int, int>(Recorder().pairs);
    final values = await loader.load(1);
    expect(() => values.add(3), throwsUnsupportedError);
  });

  test('changing the list of the map later keeps the cached value', () async {
    final source = [1];
    final loader = GroupedLoader<int, int>((keys) => {1: source});
    await loader.load(1);
    source.add(2);
    expect(await loader.load(1), [1]);
  });

  test('an asynchronous batch function is supported', () async {
    final loader = GroupedLoader<int, int>(
      (keys) async => {
        for (final key in keys) key: [key],
      },
    );
    expect(await loader.load(5), [5]);
  });

  test('a loaded key is served from the cache', () async {
    final recorder = Recorder();
    final loader = GroupedLoader<int, int>(recorder.pairs);
    await loader.load(1);
    await loader.load(1);
    expect(recorder.calls, hasLength(1));
  });

  test('a primed list is returned without a call', () async {
    final recorder = Recorder();
    final loader = GroupedLoader<int, int>(recorder.pairs)..prime(1, [9]);
    expect(await loader.load(1), [9]);
    expect(recorder.calls, isEmpty);
  });

  test('a primed list is unmodifiable', () async {
    final loader = GroupedLoader<int, int>(Recorder().pairs)..prime(1, [9]);
    final values = await loader.load(1);
    expect(() => values.add(1), throwsUnsupportedError);
  });

  test('clear makes the next load call the function again', () async {
    final recorder = Recorder();
    final loader = GroupedLoader<int, int>(recorder.pairs);
    await loader.load(1);
    loader.clear(1);
    await loader.load(1);
    expect(recorder.calls, hasLength(2));
  });

  test('a failing batch fails every key and is retried', () async {
    var isDown = true;
    final loader = GroupedLoader<int, int>((keys) {
      if (isDown) {
        throw StateError('down');
      }
      return {
        for (final key in keys) key: [key],
      };
    });
    await Future.wait([
      expectLater(loader.load(1), throwsStateError),
      expectLater(loader.load(2), throwsStateError),
    ]);
    isDown = false;
    expect(await loader.loadMany([1, 2]), [
      [1],
      [2],
    ]);
  });

  test('loadMany returns the lists in the order given', () async {
    final loader = GroupedLoader<int, int>(Recorder().pairs);
    expect(await loader.loadMany([3, 1]), [
      [3, 3],
      [1, 1],
    ]);
  });
}
