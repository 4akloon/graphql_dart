import 'dart:async';
import 'dart:collection';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A map whose lookup of one key throws.
final class ThrowingLookup extends MapBase<int, int> {
  ThrowingLookup(this.inner, this.badKey);

  final Map<int, int> inner;
  final int badKey;

  @override
  int? operator [](Object? key) {
    if (key == badKey) {
      throw StateError('bad lookup');
    }
    return inner[key];
  }

  @override
  void operator []=(int key, int value) => inner[key] = value;

  @override
  void clear() => inner.clear();

  @override
  Iterable<int> get keys => inner.keys;

  @override
  int? remove(Object? key) => inner.remove(key);
}

/// Test helpers that run loaders and collect what they report.
final class Probe {
  const Probe();

  /// Runs [body] in a guarded zone, lets the event loop run and returns the
  /// uncaught errors.
  Future<List<Object>> uncaughtErrorsOf(
    Future<void> Function() body,
  ) async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      await body();
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }, (error, stackTrace) => uncaught.add(error));
    return uncaught;
  }

  /// The value or the error of each load, in key order.
  Future<List<Object?>> settle(
    BatchLoader<int, int> loader,
    List<int> keys,
  ) async {
    final results = <Object?>[];
    final futures = [
      for (final key in keys)
        loader.load(key).then<void>(results.add, onError: results.add),
    ];
    await Future.wait(futures);
    return results;
  }
}

void main() {
  const probe = Probe();

  group('uncaught errors', () {
    test('a dropped failing future is not uncaught without a cache', () async {
      final uncaught = await probe.uncaughtErrorsOf(() async {
        final loader = BatchLoader<int, int>(
          (keys) => throw StateError('down'),
          cachesValues: false,
        );
        loader.load(1);
        loader.load(2);
      });
      expect(uncaught, isEmpty);
    });

    test('a dropped key whose lookup throws is not uncaught', () async {
      final uncaught = await probe.uncaughtErrorsOf(() async {
        final loader = BatchLoader<int, int>(
          (keys) => ThrowingLookup({for (final k in keys) k: k}, 2),
        );
        loader.load(1);
        loader.load(2);
      });
      expect(uncaught, isEmpty);
    });
  });

  group('completing a chunk', () {
    test('a throwing lookup fails only its own key', () async {
      final loader = BatchLoader<int, int>(
        (keys) => ThrowingLookup({for (final k in keys) k: k * 10}, 2),
      );
      expect(await probe.settle(loader, [1, 2, 3]), [
        10,
        isA<StateError>(),
        30,
      ]);
    });

    test('a value that is not an R fails only its own key', () async {
      final loader = BatchLoader<int, int>(
        (keys) => <int, Object?>{
          for (final k in keys) k: k == 2 ? 'x' : k,
        }.cast<int, int>(),
      );
      expect(await probe.settle(loader, [1, 2, 3]), [1, isA<TypeError>(), 3]);
    });

    test('a key the batch left out fails with the missing error', () async {
      final loader = BatchLoader<int, int>((keys) => {});
      await expectLater(loader.load(4), throwsA(isA<MissingValueException>()));
    });

    test('keys beyond those asked are ignored', () async {
      var calls = 0;
      final loader = BatchLoader<int, int>((keys) {
        calls++;
        return {for (final key in keys) key: key, 99: 99};
      });
      expect(await loader.load(1), 1);
      expect(await loader.load(99), 99);
      expect(calls, 2);
    });

    test('prime and clear during a batch complete every key once', () async {
      final uncaught = await probe.uncaughtErrorsOf(() async {
        final loader = BatchLoader<int, int>(
          (keys) => {for (final key in keys) key: key},
        );
        final first = loader.load(1);
        final second = loader.load(2);
        loader.prime(3, 30);
        loader.clear(1);
        loader.clearAll();
        loader.prime(2, 20);
        expect(await Future.wait([first, second]), [1, 2]);
      });
      expect(uncaught, isEmpty);
    });
  });

  group('maxBatchSize', () {
    test('a failing chunk fails only its own keys', () async {
      final loader = BatchLoader<int, int>((keys) {
        if (keys.contains(3)) {
          throw StateError('down');
        }
        return {for (final key in keys) key: key};
      }, maxBatchSize: 2);
      expect(await probe.settle(loader, [1, 2, 3, 4]), [
        1,
        2,
        isA<StateError>(),
        isA<StateError>(),
      ]);
    });
  });

  group('the cache and a pending key', () {
    test('a pending key cleared and loaded again is cached again', () async {
      var calls = 0;
      final loader = BatchLoader<int, int>((keys) {
        calls++;
        return {for (final key in keys) key: key};
      });
      final first = loader.load(1);
      loader.clear(1);
      final second = loader.load(1);
      await Future.wait([first, second]);
      await loader.load(1);
      expect(calls, 1);
    });

    test('an old failure does not evict a primed replacement', () async {
      final loader = BatchLoader<int, int>((keys) => throw StateError('down'));
      final failing = loader.load(1);
      loader.clear(1);
      loader.prime(1, 5);
      await expectLater(failing, throwsStateError);
      expect(await loader.load(1), 5);
    });

    test('an old failure does not evict a reloaded entry', () async {
      var calls = 0;
      final oldFailure = Completer<Map<int, int>>();
      final loader = BatchLoader<int, int>((keys) {
        calls++;
        return calls == 1
            ? oldFailure.future
            : {for (final key in keys) key: key};
      });
      final failing = loader.load(1);
      final failed = expectLater(failing, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      loader.clear(1);
      expect(await loader.load(1), 1);
      oldFailure.completeError(StateError('down'));
      await failed;
      expect(await loader.load(1), 1);
      expect(calls, 2);
    });
  });
}
