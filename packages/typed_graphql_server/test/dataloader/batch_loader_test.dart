import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A batch function that doubles its keys and records each call.
final class Recorder {
  final List<List<int>> calls = [];

  Map<int, int> doubled(List<int> keys) {
    calls.add(keys);
    return {for (final key in keys) key: key * 2};
  }
}

void main() {
  group('batching', () {
    test(
      'loads of one synchronous pass make one call in first-call order',
      () async {
        final recorder = Recorder();
        final loader = BatchLoader<int, int>(recorder.doubled);
        final results = await Future.wait([
          loader.load(3),
          loader.load(1),
          loader.load(3),
          loader.load(2),
        ]);
        expect(recorder.calls, [
          [3, 1, 2],
        ]);
        expect(results, [6, 2, 6, 4]);
      },
    );

    test(
      'loads after awaits of completed futures still share a batch',
      () async {
        final recorder = Recorder();
        final loader = BatchLoader<int, int>(recorder.doubled);
        Future<int> after(int awaits, int key) async {
          for (var i = 0; i < awaits; i++) {
            await Future<void>.value();
          }
          return loader.load(key);
        }

        await Future.wait([after(0, 1), after(1, 2), after(5, 3)]);
        expect(recorder.calls, [
          [1, 2, 3],
        ]);
      },
    );

    test('a load after the dispatch starts a second batch', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(recorder.doubled);
      await loader.load(1);
      await loader.load(2);
      expect(recorder.calls, [
        [1],
        [2],
      ]);
    });

    test('maxBatchSize splits the keys into ordered calls', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(recorder.doubled, maxBatchSize: 2);
      await loader.loadMany([1, 2, 3, 4, 5]);
      expect(recorder.calls, [
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('maxBatchSize below one is an ArgumentError', () {
      expect(
        () => BatchLoader<int, int>(Recorder().doubled, maxBatchSize: 0),
        throwsArgumentError,
      );
    });

    test('the batch function gets an unmodifiable list', () async {
      late List<int> received;
      final loader = BatchLoader<int, int>((keys) {
        received = keys;
        return {for (final key in keys) key: key};
      });
      await loader.load(1);
      expect(() => received.add(2), throwsUnsupportedError);
    });

    test('an asynchronous batch function works', () async {
      final loader = BatchLoader<int, int>(
        (keys) async => {for (final key in keys) key: key + 1},
      );
      expect(await loader.load(1), 2);
    });
  });

  group('cache', () {
    test('a loaded key is not loaded again', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(recorder.doubled);
      final first = await loader.load(1);
      final second = await loader.load(1);
      expect(second, first);
      expect(recorder.calls, hasLength(1));
    });

    test('without cachesValues a loaded key is loaded again', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(
        recorder.doubled,
        cachesValues: false,
      );
      await loader.load(1);
      await loader.load(1);
      expect(recorder.calls, hasLength(2));
    });

    test(
      'without cachesValues a key asked twice in a batch is sent once',
      () async {
        final recorder = Recorder();
        final loader = BatchLoader<int, int>(
          recorder.doubled,
          cachesValues: false,
        );
        await Future.wait([loader.load(1), loader.load(1)]);
        expect(recorder.calls, [
          [1],
        ]);
      },
    );

    test('a primed key is served without a call', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(recorder.doubled)..prime(1, 100);
      expect(await loader.load(1), 100);
      expect(recorder.calls, isEmpty);
    });

    test('prime does not overwrite a cached key', () async {
      final loader = BatchLoader<int, int>(Recorder().doubled)..prime(1, 100);
      loader.prime(1, 200);
      expect(await loader.load(1), 100);
    });

    test('prime does nothing without cachesValues', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(
        recorder.doubled,
        cachesValues: false,
      )..prime(1, 100);
      expect(await loader.load(1), 2);
    });

    test('clear makes the next load call the batch function', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(recorder.doubled);
      await loader.load(1);
      loader.clear(1);
      await loader.load(1);
      expect(recorder.calls, hasLength(2));
    });

    test('clearAll makes every next load call the batch function', () async {
      final recorder = Recorder();
      final loader = BatchLoader<int, int>(recorder.doubled);
      await loader.loadMany([1, 2]);
      loader.clearAll();
      await loader.loadMany([1, 2]);
      expect(recorder.calls, [
        [1, 2],
        [1, 2],
      ]);
    });

    test('a future handed out before clear still completes', () async {
      final loader = BatchLoader<int, int>(Recorder().doubled);
      final pending = loader.load(1);
      loader.clearAll();
      expect(await pending, 2);
    });
  });

  group('missing keys', () {
    test('a nullable value type completes with null', () async {
      final loader = BatchLoader<int, String?>((keys) => {});
      expect(await loader.load(1), isNull);
    });

    test('a non-null value type fails with MissingValueException', () async {
      final loader = BatchLoader<int, String>((keys) => {});
      await expectLater(
        loader.load(7),
        throwsA(
          isA<MissingValueException>().having((e) => e.key, 'key', 7),
        ),
      );
    });

    test('the message names the key', () {
      expect(
        const MissingValueException(7).toString(),
        'MissingValueException: the batch function returned no value for key 7',
      );
    });
  });

  group('failures', () {
    test('a throwing batch function fails every key', () async {
      final loader = BatchLoader<int, int>((keys) => throw StateError('down'));
      final first = expectLater(loader.load(1), throwsStateError);
      final second = expectLater(loader.load(2), throwsStateError);
      await Future.wait([first, second]);
    });

    test('a failed batch future fails every key', () async {
      final loader = BatchLoader<int, int>(
        (keys) => Future<Map<int, int>>.error(StateError('down')),
      );
      await expectLater(loader.loadMany([1, 2]), throwsStateError);
    });

    test('failed keys are loaded again by the next load', () async {
      var shouldFail = true;
      final loader = BatchLoader<int, int>((keys) {
        if (shouldFail) {
          throw StateError('down');
        }
        return {for (final key in keys) key: key};
      });
      await expectLater(loader.load(1), throwsStateError);
      shouldFail = false;
      expect(await loader.load(1), 1);
    });

    test(
      'a dropped failing future reports no uncaught error when cached',
      () async {
        final uncaught = <Object>[];
        await runZonedGuarded(
          () async {
            BatchLoader<int, int>((keys) => throw StateError('down')).load(1);
            await Future<void>.delayed(Duration.zero);
            await Future<void>.delayed(Duration.zero);
          },
          (error, stackTrace) => uncaught.add(error),
        );
        expect(uncaught, isEmpty);
      },
    );
  });

  group('loadMany', () {
    test('returns the values in the order given', () async {
      final loader = BatchLoader<int, int>(Recorder().doubled);
      expect(await loader.loadMany([3, 1, 2]), [6, 2, 4]);
    });

    test('fails when one key fails', () async {
      final loader = BatchLoader<int, int>(
        (keys) => {
          for (final key in keys)
            if (key != 2) key: key,
        },
      );
      await expectLater(
        loader.loadMany([1, 2, 3]),
        throwsA(isA<MissingValueException>()),
      );
    });
  });
}
