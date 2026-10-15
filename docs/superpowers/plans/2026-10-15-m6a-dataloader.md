# M6a DataLoader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first part of stage M6 of `typed_graphql_server` (R4.15): request-scoped batching and caching of loads. `BatchLoader<K, V>` (one batch function from a list of keys to a map, de-duplication, a per-loader cache, `prime`, `clear`, `clearAll`, `maxBatchSize`), `GroupedLoader<K, V>` (the list of children of a key, in one batch), `MissingValueException`, and the DataLoader guide.

**Architecture:** `BatchLoader` and `GroupedLoader` are thin public faces over one internal `LoaderQueue`. A load returns the cached future of its key or queues the key; the first queued key schedules a dispatch with a zero-duration timer, so the batch runs after the microtask queue has drained, which is when every resolver of one level of the executor has asked. The dispatch splits the keys into chunks of `maxBatchSize`, calls the batch function per chunk and completes every key exactly once (a value, a missing-value error, or the batch function's error). A failed key is evicted from the cache by identity, so a later `clear` or `prime` of the same key survives. Every future the queue creates has a listener, so a load nobody reads never reports an unhandled error. Loaders hold request state, so the application's context factory creates them for each request.

**Tech Stack:** Dart 3.13 (formatted with 3.13.5), `package:test`, `package:meta`. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-15-m6-server-pipeline-design.md` (section 13, DataLoader), `docs/requirements.md` R4.15.

**Base:** `faf6ca5` (M5 merged into main). This plan is generated from the commits that implemented it: `6d3c7d2` (BatchLoader), `f78eee8` (GroupedLoader), `164c2ae` (queue hardening after review), `3262abd` (GroupedLoader tests after review) and `ac3fdee` (stage documents). The code below is the end state at `HEAD`.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, never catch `Error`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too.
- `lib/` imports no platform library but `dart:async`, `dart:collection`, `dart:core` and `dart:math`.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and the server suite green.
- **Memory and time limits.** Run every `dart` command as `flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 <cmd> )'`: one heavy Dart process at a time, no Chrome runs, filter the output with `| tail`.
- Format with the newer SDK (3.13.1's formatter crashes): `/home/genius/fvm/versions/3.47.6/bin/dart format packages test`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen`.
- Commits use Conventional Commits, one per task, with the message given in the task and a trailer naming the real model of the implementer (for example `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Run every command from the repository root unless a step says otherwise.
- Changes to existing files are unified diffs against the tree the earlier tasks leave. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- Tests never read git-ignored or untracked files.
- Bad input never throws (R0.3): a key the batch function leaves out is a `MissingValueException` future error (a `BatchLoader`) or an empty list (a `GroupedLoader`), and a failing batch function fails the futures of its keys; only programmer errors throw.

## Review Focus

1. A batch is dispatched once, after the microtask queue drains, with the distinct keys in first-load order; `maxBatchSize` splits it. Task 1 (`loader_queue_test.dart`, `batch_loader_test.dart`).
2. Every key completes exactly once, including when the batch function throws or returns a partial map. Task 1 (`loader_queue_test.dart`).
3. A failed key is evicted from the cache by identity: a `clear` or `prime` of the same key made while the batch was in flight survives. Task 1.
4. No unhandled error escapes from a load nobody awaited. Task 1.
5. `GroupedLoader` hands out unmodifiable lists and an empty list for a missing key. Task 2.
6. Under the executor, the loads of sibling fields run in one batch. Tasks 1 and 2 (`dataloader_execution_test.dart`, `grouped_execution_test.dart`).

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql_server/lib/src/dataloader/loader_queue.dart` | Create | 1 |
| `packages/typed_graphql_server/lib/src/dataloader/batch_loader.dart` | Create | 1 |
| `packages/typed_graphql_server/lib/src/dataloader/missing_value_exception.dart` | Create | 1 |
| `packages/typed_graphql_server/test/dataloader/loader_queue_test.dart` | Create | 1 |
| `packages/typed_graphql_server/test/dataloader/batch_loader_test.dart` | Create | 1 |
| `packages/typed_graphql_server/test/dataloader/dataloader_execution_test.dart` | Create | 1 |
| `packages/typed_graphql_server/lib/src/dataloader/grouped_loader.dart` | Create | 2 |
| `packages/typed_graphql_server/test/dataloader/grouped_loader_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/dataloader/grouped_execution_test.dart` | Create | 2 |
| `packages/typed_graphql_server/doc/dataloader.md` | Create | 3 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Modify | 3 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 1, 2, 3 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 3 |
| `packages/typed_graphql_server/README.md` | Modify | 3 |
| `README.md` | Modify | 3 |
| `CLAUDE.md` | Modify | 3 |
| `llms.txt` | Modify | 3 |
| `docs/discovery.md` | Modify | 3 |

## Review fixes folded in

Task 1 folds `164c2ae` (queue hardening after review: eviction of a failed key by identity, a listener on every future, exactly-once completion; it adds `loader_queue_test.dart` and changes `loader_queue.dart`, `batch_loader.dart` and `batch_loader_test.dart`). Task 2 folds `3262abd` (the `GroupedLoader` copy and option tests, and a small change to `grouped_loader.dart`). Every file below is the final text at `HEAD`, so the plan reproduces the end state, not the intermediate commits.

## The green check

Every task ends with this check. "Green" means each command exits 0 and prints no failure:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart pub get )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format --output=none --set-exit-if-changed packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )' | tail -30
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )' | tail -30
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' | tail -30
```

### Task 1: BatchLoader

`BatchLoader<K, V>`, its internal `LoaderQueue` and `MissingValueException`, exported from the barrel. Tests: the queue (dispatch timing, chunking, exactly-once completion, eviction by identity, no unhandled errors), the loader (de-duplication, cache, `prime`, `clear`, `clearAll`, missing keys, errors) and an execution test with sibling fields sharing one batch.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/dataloader/loader_queue.dart`, `packages/typed_graphql_server/lib/src/dataloader/batch_loader.dart`, `packages/typed_graphql_server/lib/src/dataloader/missing_value_exception.dart`
- Modify: `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Test: `packages/typed_graphql_server/test/dataloader/loader_queue_test.dart`, `packages/typed_graphql_server/test/dataloader/batch_loader_test.dart`, `packages/typed_graphql_server/test/dataloader/dataloader_execution_test.dart`

**Interfaces:**
- Consumes: the server as left by M5 (`ExecutableSchema`, the builder, `ExecutionOptions`).
- Produces: `BatchLoader<K, V>` (`load`, `loadMany`, `prime`, `clear`, `clearAll`, option `maxBatchSize`), `MissingValueException`, and the internal `LoaderQueue` (not exported). The exact signatures are in the code below.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql_server/test/dataloader/loader_queue_test.dart`:

```dart
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
```

Create `packages/typed_graphql_server/test/dataloader/batch_loader_test.dart`:

```dart
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
```

Create `packages/typed_graphql_server/test/dataloader/dataloader_execution_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Ctx {
  Ctx(this.names);

  final BatchLoader<int, String> names;
}

void main() {
  test('a list of users loads its names in one batch', () async {
    final calls = <List<int>>[];
    final b = ExecutableSchemaBuilder<Ctx>();
    final user = b.object<int>(
      'User',
      fields: (t) => [
        t
            .field('name', b.string)
            .resolve(
              (parent, args, context, info) => context.names.load(parent),
            ),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('users', b.list(user)).pure((_) => const [1, 2, 3]),
      ],
    );
    final schema = b.build(query: query);
    final document = ValidDocument.assumeValid(
      schema.schema,
      const Parser().parse(Source('{ users { name } }')).requireDocument(),
    );
    final context = Ctx(
      BatchLoader<int, String>((keys) {
        calls.add(keys);
        return {for (final key in keys) key: 'user $key'};
      }),
    );

    final result = await schema.execute(document, context: context);

    expect(calls, [
      [1, 2, 3],
    ]);
    expect((result as ExecutionResult).toJson().toJson(), {
      'data': {
        'users': [
          {'name': 'user 1'},
          {'name': 'user 2'},
          {'name': 'user 3'},
        ],
      },
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test test/dataloader" )' | tail -40
```

Expected: the three files fail to compile, because `BatchLoader` and `MissingValueException` are undefined.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/dataloader/missing_value_exception.dart`:

```dart
/// Thrown into the future of a key that the batch function left out and whose
/// value type cannot be null.
///
/// A resolver that lets it escape is masked like any other resolver error.
///
/// {@category dataloader}
final class MissingValueException implements Exception {
  /// Creates the exception for [key].
  const MissingValueException(this.key);

  /// The key the batch function returned no value for.
  final Object? key;

  @override
  String toString() =>
      'MissingValueException: the batch function returned no value for key '
      '$key';
}
```

Create `packages/typed_graphql_server/lib/src/dataloader/loader_queue.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';

/// The batching and caching shared by the public loaders: it collects the keys
/// of one batch, dispatches them after the microtask queue has drained and
/// completes one future per distinct key.
///
/// The timer, not a microtask, is the dispatch point so that resolvers that
/// `await` already completed futures before they call `load` still land in
/// the same batch (spec M6 section 15 item 5).
@internal
final class LoaderQueue<K, R> {
  /// Creates a queue that sends keys to [_batch], at most [maxBatchSize] per
  /// call, and asks [missing] for the result of a key the call left out.
  LoaderQueue(
    this._batch, {
    required this.missing,
    this.maxBatchSize,
    this.cachesValues = true,
  }) {
    final size = maxBatchSize;
    if (size != null && size < 1) {
      throw ArgumentError.value(size, 'maxBatchSize', 'must be at least 1');
    }
  }

  final FutureOr<Map<K, R>> Function(List<K> keys) _batch;

  /// The result of a key the batch function left out; it may throw.
  final R Function(K key) missing;

  /// The most keys one call of the batch function gets, null for no limit.
  final int? maxBatchSize;

  /// Whether a loaded, pending or primed value is reused.
  final bool cachesValues;

  // Dart's default map keeps insertion order, which is the call order.
  Map<K, Completer<R>> _pending = {};
  final Map<K, Future<R>> _cache = {};

  /// The result for [key]: the cached future, or one that completes when the
  /// batch it joins is dispatched.
  Future<R> load(K key) {
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    final queued = _pending[key];
    if (queued != null) {
      // A clear while the key was pending dropped it from the cache.
      if (cachesValues) {
        _cache[key] = queued.future;
      }
      return queued.future;
    }
    if (_pending.isEmpty) {
      Timer.run(_dispatch);
    }
    final completer = Completer<R>();
    _pending[key] = completer;
    final future = completer.future;
    if (cachesValues) {
      _cache[key] = future;
    }
    // A failure is not cached, and this listener also keeps the future from
    // being an uncaught error when no caller listens, cached or not.
    future.then<void>((_) {}, onError: (Object _) => _evict(key, future));
    return future;
  }

  /// Caches [value] for [key] unless the key is already cached.
  void prime(K key, R value) {
    if (cachesValues && !_cache.containsKey(key)) {
      _cache[key] = Future<R>.value(value);
    }
  }

  /// Forgets the cached result of [key].
  void clear(K key) => _cache.remove(key);

  /// Forgets every cached result.
  void clearAll() => _cache.clear();

  void _evict(K key, Future<R> future) {
    if (identical(_cache[key], future)) {
      _cache.remove(key);
    }
  }

  void _dispatch() {
    final batch = _pending;
    _pending = {};
    final keys = batch.keys.toList();
    final size = maxBatchSize ?? keys.length;
    for (var start = 0; start < keys.length; start += size) {
      final end = start + size < keys.length ? start + size : keys.length;
      _runChunk(List<K>.unmodifiable(keys.sublist(start, end)), batch);
    }
  }

  void _runChunk(List<K> chunk, Map<K, Completer<R>> batch) {
    Future<Map<K, R>>.sync(() => _batch(chunk)).then<void>(
      (values) {
        for (final key in chunk) {
          _complete(batch[key]!, key, values);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        for (final key in chunk) {
          batch[key]!.completeError(error, stackTrace);
        }
      },
    );
  }

  // Each key completes exactly once, whatever the returned map or `missing`
  // does, so no caller waits forever.
  void _complete(Completer<R> completer, K key, Map<K, R> values) {
    try {
      completer.complete(
        values.containsKey(key) ? values[key] as R : missing(key),
      );
    } on Object catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }
}
```

Create `packages/typed_graphql_server/lib/src/dataloader/batch_loader.dart`:

```dart
import 'dart:async';

import 'loader_queue.dart';
import 'missing_value_exception.dart';

/// Loads values by key in batches, so that N resolvers asking for one value
/// each cause one call to a function that fetches many.
///
/// Without it, a list of 100 users that each load their company is 100
/// queries (the N+1 problem). The first [load] of a batch schedules its
/// dispatch for when the microtask queue has drained, so every resolver of one
/// level, also one that `await`s a completed future before it calls [load],
/// joins the same call. A key asked twice in a batch is sent once.
///
/// A loader belongs to one request: create it in the code that makes the
/// request's context, so its cache and its batches never cross requests. With
/// `cachesValues` (the default) a loaded, pending or primed value is reused
/// for the loader's lifetime; call [clear] or [clearAll] after a mutation. A
/// failed batch is not cached: every key of it fails with the error and is
/// loaded again by the next [load].
///
/// {@category dataloader}
final class BatchLoader<K, V> {
  /// Creates a loader that fetches keys with [load], at most `maxBatchSize`
  /// per call (no limit when null; a larger batch is split into several
  /// calls). With `cachesValues` off nothing is reused across batches.
  ///
  /// The function runs in the zone of the first [BatchLoader.load] of its
  /// batch.
  ///
  /// [load] gets the distinct keys of a batch in the order they were asked
  /// and returns a map; a key it leaves out completes with `null` when [V] is
  /// nullable and fails with [MissingValueException] otherwise. Throws an
  /// [ArgumentError] when `maxBatchSize` is less than 1.
  BatchLoader(
    FutureOr<Map<K, V>> Function(List<K> keys) load, {
    int? maxBatchSize,
    bool cachesValues = true,
  }) : _queue = LoaderQueue<K, V>(
         load,
         maxBatchSize: maxBatchSize,
         cachesValues: cachesValues,
         missing: (key) {
           if (null is V) {
             return null as V;
           }
           throw MissingValueException(key);
         },
       );

  final LoaderQueue<K, V> _queue;

  /// The value for [key]; the cached future when there is one.
  Future<V> load(K key) => _queue.load(key);

  /// The values for [keys], in the order given; fails when any key fails.
  Future<List<V>> loadMany(Iterable<K> keys) =>
      Future.wait([for (final key in keys) _queue.load(key)]);

  /// Caches [value] for [key] unless the key is already cached.
  ///
  /// Does nothing when the loader does not cache.
  void prime(K key, V value) => _queue.prime(key, value);

  /// Forgets the cached value of [key]; futures already handed out still
  /// complete.
  void clear(K key) => _queue.clear(key);

  /// Forgets every cached value.
  void clearAll() => _queue.clearAll();
}
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, export the new files (the `GroupedLoader` export arrives in Task 2). Apply this change:

```diff
@@ -36,6 +36,8 @@ export 'src/builder/scalar_type_def.dart';
 export 'src/builder/schema_build_error.dart';
 export 'src/builder/union_type_def.dart';
 export 'src/cancellation/cancel_signal.dart';
+export 'src/dataloader/batch_loader.dart';
+export 'src/dataloader/missing_value_exception.dart';
 export 'src/execution/directive_middleware.dart';
 export 'src/execution/error_behavior.dart';
 export 'src/execution/error_hook.dart';
```

- [ ] **Step 4: Run the tests**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test test/dataloader" )' | tail -40
```

Expected: every test passes.

- [ ] **Step 5: Run the green check**

Run the green check above. Self-review: `wc -l` of the files touched (`loader_queue.dart` stays under 300 lines, the longest method under 40).

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server
git commit -m "feat(typed_graphql_server): add BatchLoader" -m "Co-Authored-By: <your model trailer>"
```

Use the trailer of the model that ran the task. (Original history: `6d3c7d2` plus the hardening of `164c2ae`.)

### Task 2: GroupedLoader

`GroupedLoader<K, V>` loads the list of children of a key (posts by author id) in one batch over the same `LoaderQueue`: a missing key is an empty list and the lists handed out are unmodifiable.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/dataloader/grouped_loader.dart`
- Modify: `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Test: `packages/typed_graphql_server/test/dataloader/grouped_loader_test.dart`, `packages/typed_graphql_server/test/dataloader/grouped_execution_test.dart`

**Interfaces:**
- Consumes: Task 1 (`LoaderQueue`).
- Produces: `GroupedLoader<K, V>` with `load`, `loadMany`, `prime`, `clear`, `clearAll` as `BatchLoader`, its values being `List<V>`. The exact signatures are in the code below.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql_server/test/dataloader/grouped_loader_test.dart`:

```dart
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
    final values = await loader.load(2);
    expect(values, isEmpty);
    expect(() => values.add(1), throwsUnsupportedError);
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

  test(
    'changing the list of an async batch later keeps the cached value',
    () async {
      final source = [1];
      final loader = GroupedLoader<int, int>((keys) async => {1: source});
      final values = await loader.load(1);
      source.add(2);
      expect(await loader.load(1), [1]);
      expect(() => values.add(3), throwsUnsupportedError);
    },
  );

  test('changing a primed list later keeps the cached value', () async {
    final source = [9];
    final loader = GroupedLoader<int, int>(Recorder().pairs)..prime(1, source);
    source.add(8);
    expect(await loader.load(1), [9]);
  });

  test('maxBatchSize splits one pass into chunks', () async {
    final recorder = Recorder();
    final loader = GroupedLoader<int, int>(recorder.pairs, maxBatchSize: 2);
    await loader.loadMany([1, 2, 3]);
    expect(recorder.calls, [
      [1, 2],
      [3],
    ]);
  });

  test('a maxBatchSize below 1 is an ArgumentError', () {
    expect(
      () => GroupedLoader<int, int>(Recorder().pairs, maxBatchSize: 0),
      throwsArgumentError,
    );
  });

  test('a loader that does not cache calls the function again', () async {
    final recorder = Recorder();
    final loader = GroupedLoader<int, int>(
      recorder.pairs,
      cachesValues: false,
    );
    await loader.load(1);
    await loader.load(1);
    expect(recorder.calls, hasLength(2));
  });
}
```

Create `packages/typed_graphql_server/test/dataloader/grouped_execution_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Ctx {
  Ctx(this.posts);

  final GroupedLoader<int, String> posts;
}

void main() {
  test('a list of authors loads its posts in one batch', () async {
    final calls = <List<int>>[];
    final b = ExecutableSchemaBuilder<Ctx>();
    final author = b.object<int>(
      'Author',
      fields: (t) => [
        t
            .field('posts', b.list(b.string))
            .resolve(
              (parent, args, context, info) => context.posts.load(parent),
            ),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('authors', b.list(author)).pure((_) => const [1, 2, 3]),
      ],
    );
    final schema = b.build(query: query);
    final document = ValidDocument.assumeValid(
      schema.schema,
      const Parser().parse(Source('{ authors { posts } }')).requireDocument(),
    );
    final context = Ctx(
      GroupedLoader<int, String>((keys) {
        calls.add(keys);
        return {
          for (final key in keys.where((key) => key != 3))
            key: ['post $key a', 'post $key b'],
        };
      }),
    );

    final result = await schema.execute(document, context: context);

    expect(calls, [
      [1, 2, 3],
    ]);
    expect((result as ExecutionResult).toJson().toJson(), {
      'data': {
        'authors': [
          {
            'posts': ['post 1 a', 'post 1 b'],
          },
          {
            'posts': ['post 2 a', 'post 2 b'],
          },
          {'posts': <Object?>[]},
        ],
      },
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test test/dataloader/grouped_loader_test.dart test/dataloader/grouped_execution_test.dart" )' | tail -40
```

Expected: compile errors, `GroupedLoader` is undefined.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/dataloader/grouped_loader.dart`:

```dart
import 'dart:async';

import 'batch_loader.dart';
import 'loader_queue.dart';

/// Loads the list of values that belong to a key, in batches: one parent, many
/// children.
///
/// Where a [BatchLoader] maps a key to one value, a `GroupedLoader` maps it to
/// a list, for example the posts of an author. Without it, the `posts` of 50
/// authors are 50 queries; with it, the resolvers of one level ask for their
/// author's id and one function fetches the posts of all of them, for example
/// with `WHERE author_id IN (...)`. Batching, de-duplication, the per-request
/// cache and the handling of failures are those of [BatchLoader].
///
/// The lists a loader hands out are unmodifiable copies of what the batch
/// function returned, so a resolver cannot change the value another field
/// reads from the cache.
///
/// {@category dataloader}
final class GroupedLoader<K, V> {
  /// Creates a loader that fetches keys with [load], at most `maxBatchSize`
  /// per call (no limit when null). With `cachesValues` off nothing is reused
  /// across batches.
  ///
  /// [load] gets the distinct keys of a batch in the order they were asked
  /// and returns a map; a key it leaves out has an empty list. Throws an
  /// [ArgumentError] when `maxBatchSize` is less than 1.
  GroupedLoader(
    FutureOr<Map<K, List<V>>> Function(List<K> keys) load, {
    int? maxBatchSize,
    bool cachesValues = true,
  }) : _queue = LoaderQueue<K, List<V>>(
         (keys) {
           final result = load(keys);
           return result is Future<Map<K, List<V>>>
               ? result.then(_freeze<K, V>)
               : _freeze<K, V>(result);
         },
         maxBatchSize: maxBatchSize,
         cachesValues: cachesValues,
         missing: (_) => List<V>.unmodifiable(<V>[]),
       );

  final LoaderQueue<K, List<V>> _queue;

  static Map<K, List<V>> _freeze<K, V>(Map<K, List<V>> groups) => {
    for (final entry in groups.entries)
      entry.key: List<V>.unmodifiable(entry.value),
  };

  /// The values for [key]; the cached future when there is one.
  Future<List<V>> load(K key) => _queue.load(key);

  /// The lists for [keys], in the order given; fails when any key fails.
  Future<List<List<V>>> loadMany(Iterable<K> keys) =>
      Future.wait([for (final key in keys) _queue.load(key)]);

  /// Caches a copy of [values] for [key] unless the key is already cached.
  ///
  /// Does nothing when the loader does not cache.
  void prime(K key, List<V> values) =>
      _queue.prime(key, List<V>.unmodifiable(values));

  /// Forgets the cached list of [key]; futures already handed out still
  /// complete.
  void clear(K key) => _queue.clear(key);

  /// Forgets every cached list.
  void clearAll() => _queue.clearAll();
}
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change:

```diff
@@ -37,6 +37,7 @@ export 'src/builder/schema_build_error.dart';
 export 'src/builder/union_type_def.dart';
 export 'src/cancellation/cancel_signal.dart';
 export 'src/dataloader/batch_loader.dart';
+export 'src/dataloader/grouped_loader.dart';
 export 'src/dataloader/missing_value_exception.dart';
 export 'src/execution/directive_middleware.dart';
 export 'src/execution/error_behavior.dart';
```

- [ ] **Step 4: Run the tests**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test test/dataloader" )' | tail -40
```

Expected: every test passes.

- [ ] **Step 5: Run the green check**

Run the green check above.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server
git commit -m "feat(typed_graphql_server): add GroupedLoader" -m "Co-Authored-By: <your model trailer>"
```

(Original history: `f78eee8`, with the test additions of `3262abd` folded in.)

### Task 3: The DataLoader documentation

The DataLoader guide (`doc/dataloader.md`, whose programs the documentation suite runs and compares with the output the guide shows), its dartdoc category, and the stage documents. R4.15.

**Files:**
- Create: `packages/typed_graphql_server/doc/dataloader.md`
- Modify: `packages/typed_graphql_server/dartdoc_options.yaml`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/README.md`, `README.md`, `CLAUDE.md`, `llms.txt`, `docs/discovery.md`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: the guide and the category `dataloader`; the discovery query `dataloader dart graphql`.

- [ ] **Step 1: Write the guide**

Create `packages/typed_graphql_server/doc/dataloader.md`:

````markdown
# DataLoader

A list of 100 users where each user shows its company is 101 queries if every
`company` resolver asks the database for its own row: one for the list and one
per user (the N+1 problem). A `BatchLoader` collects the keys the resolvers ask
for during one level of the response and hands them to one function that
fetches them all, so the same request is two queries. It also remembers what it
loaded, so a key asked twice costs one fetch.

## A loader in the context

A loader belongs to one request. Create it in the code that makes the context
(in the request pipeline, the context factory), so its cache and its batches
never cross requests: a value one user may see must not be served from another
user's cache. The library keeps no global loader.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Context {
  Context(this.companies);

  final BatchLoader<int, String> companies;
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Context>();
  final user = b.object<int>(
    'User',
    fields: (t) => [
      t.field('company', b.string).resolve((parent, args, context, info) {
        return context.companies.load(parent);
      }),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('users', b.list(user)).pure((_) => const [1, 2, 3]),
    ],
  );
  final schema = b.build(query: query);
  final document = ValidDocument.assumeValid(
    schema.schema,
    const Parser().parse(Source('{ users { company } }')).requireDocument(),
  );

  final context = Context(
    BatchLoader<int, String>((keys) {
      print('fetching $keys');
      return {for (final key in keys) key: 'Company $key'};
    }),
  );
  final result = await schema.execute(document, context: context);
  print((result as ExecutionResult).toJson().toJson());
}
```

It prints:

```text
fetching [1, 2, 3]
{data: {users: [{company: Company 1}, {company: Company 2}, {company: Company 3}]}}
```

The function gets the distinct keys in the order they were asked and returns a
map. It may be asynchronous: its type is `FutureOr<Map<K, V>>`.

## When a batch is dispatched

The first `load` of a batch schedules its dispatch for when the microtask queue
has drained (a zero-duration timer). Everything that runs before that joins the
batch: the resolvers of one level, and also a resolver that `await`s a
completed future before it calls `load`, however many times. The executor needs
no hook for this. A `load` after the dispatch started begins the next batch.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final loader = BatchLoader<int, int>((keys) {
    print('batch $keys');
    return {for (final key in keys) key: key * 10};
  });

  Future<int> later(int awaits, int key) async {
    for (var i = 0; i < awaits; i++) {
      await Future<void>.value();
    }
    return loader.load(key);
  }

  print(await Future.wait([later(0, 1), later(3, 2), later(8, 3)]));
  print(await loader.load(4));
}
```

It prints:

```text
batch [1, 2, 3]
[10, 20, 30]
batch [4]
40
```

`loadMany(keys)` loads several keys at once and returns the values in the order
given; it fails when any key fails.

## De-duplication and the cache

A key asked twice in one batch is sent once, and both callers get the same
future. With `cachesValues` (the default) a loaded, pending or primed value is
also reused for the loader's lifetime, so a later `load` of the key does not
call the function again.

- `prime(key, value)` puts a value you already have into the cache, for
  example the rows a list query returned, so that `load` of those keys fetches
  nothing. It never replaces a value that is already cached.
- `clear(key)` and `clearAll()` forget cached values. Call them after a
  mutation that changed what the loader would return. Futures already handed
  out still complete. A `load` of a key that is still pending after the clear
  joins the pending batch and caches it again.
- `cachesValues: false` turns the cache off; keys asked in the same batch are
  still sent once.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final loader = BatchLoader<int, String>((keys) {
    print('fetching $keys');
    return {for (final key in keys) key: 'name $key'};
  });

  print(await Future.wait([loader.load(1), loader.load(1), loader.load(2)]));
  print(await loader.load(1));
  loader.prime(3, 'primed');
  print(await loader.load(3));
  loader.clear(1);
  print(await loader.load(1));
}
```

It prints:

```text
fetching [1, 2]
[name 1, name 1, name 2]
name 1
primed
fetching [1]
name 1
```

## Missing keys

A key the function leaves out of its map has no value. When the value type is
nullable (`BatchLoader<int, String?>`) the future completes with `null`.
Otherwise it fails with a `MissingValueException` that holds the key; a
resolver that lets it escape is a field error, masked like any other.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final optional = BatchLoader<int, String?>((keys) => {1: 'one'});
  print(await Future.wait([optional.load(1), optional.load(2)]));

  final required = BatchLoader<int, String>((keys) => {1: 'one'});
  try {
    await required.load(2);
  } on MissingValueException catch (error) {
    print(error);
  }
}
```

It prints:

```text
[one, null]
MissingValueException: the batch function returned no value for key 2
```

## One-to-many: GroupedLoader

A `BatchLoader` maps a key to one value. When a parent has many children, such
as the posts of an author, use a `GroupedLoader<K, V>`: its function gets the
keys of the batch and returns a map from each key to a list, so the posts of
every author on a level are one query (`WHERE author_id IN (...)`). Batching,
the cache, `prime`, `clear`, `maxBatchSize` and failures work as in
`BatchLoader`. A key the function leaves out has an empty list. The lists the
loader hands out are unmodifiable copies, so a resolver cannot change a cached
value that another field reads.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final posts = GroupedLoader<int, String>((authorIds) {
    print('fetching posts of $authorIds');
    return {
      1: ['Hello', 'Again'],
      2: ['Hi'],
    };
  });

  print(await Future.wait([posts.load(1), posts.load(2), posts.load(3)]));
  try {
    (await posts.load(1)).add('Nope');
  } on UnsupportedError {
    print('the list is unmodifiable');
  }
}
```

It prints:

```text
fetching posts of [1, 2, 3]
[[Hello, Again], [Hi], []]
the list is unmodifiable
```

## maxBatchSize

`maxBatchSize` caps the keys of one call. A batch with more keys is split in
order into calls of at most that many, for a database that limits the size of
an `IN` list. A value below 1 is an `ArgumentError`.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final loader = BatchLoader<int, int>((keys) {
    print('call $keys');
    return {for (final key in keys) key: key};
  }, maxBatchSize: 2);
  await loader.loadMany([1, 2, 3, 4, 5]);
}
```

It prints:

```text
call [1, 2]
call [3, 4]
call [5]
```

## Errors

If the function throws, or its future fails, every key of that call fails with
the same error. A failure is not cached: the next `load` of those keys calls
the function again. The loader listens to every future it creates, so a failed
batch never becomes an uncaught error by itself; the future you get back is
yours to await, and a resolver that returns it reports the failure as a field
error, with or without `cachesValues`. If the returned map cannot be read for
one key (a lookup that throws, a value of the wrong type), only that key fails
and the others complete. The function runs in the zone of the first `load` of
its batch.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  var isDown = true;
  final loader = BatchLoader<int, int>((keys) {
    if (isDown) {
      throw StateError('database is down');
    }
    return {for (final key in keys) key: key};
  });

  try {
    await loader.loadMany([1, 2]);
  } on StateError catch (error) {
    print(error.message);
  }
  isDown = false;
  print(await loader.loadMany([1, 2]));
}
```

It prints:

```text
database is down
[1, 2]
```
````

- [ ] **Step 2: Update the documents**

`dartdoc_options.yaml`: register the `dataloader` category and its guide. In `packages/typed_graphql_server/dartdoc_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,6 +9,9 @@ dartdoc:
     cancellation:
       markdown: doc/cancellation.md
       displayName: Cancellation
+    dataloader:
+      markdown: doc/dataloader.md
+      displayName: DataLoader
     execution:
       markdown: doc/execution.md
       displayName: Execution
@@ -25,6 +28,7 @@ dartdoc:
     - authorization
     - builder
     - cancellation
+    - dataloader
     - execution
     - introspection
     - lookahead
```

Barrel: update the library doc comment (the exports came in Tasks 1 and 2). In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,7 +4,8 @@
 ///
 /// Under construction: stage M5 is complete (the typed schema builder,
 /// execution, introspection, subscriptions, look-ahead, authorization and
-/// cancellation); transports follow. See the package README.
+/// cancellation) and DataLoader (`BatchLoader`, `GroupedLoader`) work; the
+/// request pipeline and the transports follow. See the package README.
 library;
 
 export 'src/authorization/authorization.dart';
```

Changelog: add the entries. In `packages/typed_graphql_server/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -139,3 +139,10 @@
   `FieldDef.middleware` and `CancelSignal.listenerCount` are `@internal`.
 - A run that halted (for example `GQL337`) and is then cancelled answers with
   the halt error, not `GQL350`.
+- `BatchLoader` batches and caches loads by key within a request (dispatch
+  after the microtask queue drains, `maxBatchSize`, `prime`, `clear`);
+  `MissingValueException` for a key the batch function left out. The DataLoader
+  guide and its dartdoc category `dataloader`.
+- `GroupedLoader` loads the list of children of a key (posts by author id) in
+  one batch, with the cache and failure behaviour of `BatchLoader`; a missing
+  key is an empty list and the lists it hands out are unmodifiable.
```

Package README: mention DataLoader and link the guide. In `packages/typed_graphql_server/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -14,8 +14,10 @@
 > masking and field middleware, answer introspection queries, run a
 > subscription over a stream of events, read which fields a request selected
 > under a field, guard fields with an authorizer and stop a request with a
-> cancel signal or a timeout. DataLoader and the request pipeline come in M6,
-> the HTTP, graphql-ws and graphql-sse handlers in M7. See the
+> cancel signal or a timeout. DataLoader (M6a) works too: `BatchLoader` and
+> `GroupedLoader` batch and cache the loads of one request. The request
+> pipeline comes later in M6, the HTTP, graphql-ws and graphql-sse handlers
+> in M7. See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
 ## Contents
@@ -49,7 +51,7 @@ dependencies:
 - **You do not need it when** you only call a GraphQL server: that is the
   client package, not usable yet. Today it also has no HTTP or
   WebSocket handler: you call `ExecutableSchema.execute` or `subscribe`
-  yourself with a parsed and validated document (the handlers are M6 and M7).
+  yourself with a parsed and validated document (the request pipeline is M6, the handlers M7).
 - **What it replaces**: resolvers written against `Map<String, dynamic>`, where
   a wrong result type or a misspelled argument name fails at run time in the
   middle of a request. Here the wrong type does not compile, and every error
@@ -142,6 +144,8 @@ It prints:
   answer as the core, `IntrospectionPolicy`, root types without a root value.
 - [Subscriptions](doc/subscriptions.md): source streams, one event at a time,
   rejected and failed subscriptions.
+- [DataLoader](doc/dataloader.md): batching and caching loads per request with
+  `BatchLoader` and `GroupedLoader`, missing keys, `maxBatchSize`.
 - [Look-ahead](doc/lookahead.md): the fields a request selected under a field,
   `fingerprint` as a DataLoader key, `ColumnAllowlist`.
 - [Authorization](doc/authorization.md): rules on fields and types, the
```

Root README: update the package table row. In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -112,7 +112,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization and cancellation (M5, complete) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete) and DataLoader (M6a) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
```

`llms.txt`: update the summary and the server entry. In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; DataLoader and the request pipeline (M6) and the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); the request pipeline (rest of M6) and the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
@@ -8,7 +8,7 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization and Cancellation in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization and cancellation work; DataLoader and the request pipeline (M6) and transport handlers (M7) come later
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation and DataLoader in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation and DataLoader (BatchLoader, GroupedLoader) work; the request pipeline (rest of M6) and transport handlers (M7) come later
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
 ## Guides
```

Discovery: add the query. In `docs/discovery.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,6 +45,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | GraphQL look-ahead requested fields dart | M5 | yes |
 | authorize GraphQL fields dart | M5 | yes |
 | cancel or time out a GraphQL request dart | M5 | yes |
+| dataloader dart graphql | M6 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | yes |
 
```

`CLAUDE.md`: record the stage and the `dataloader/` layer. In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -61,7 +61,10 @@ guides. M5d (look-ahead, authorization, cancellation) delivers
 `GQL352`), `CancelSignal` with `ExecutionOptions.cancelSignal` and `timeout`
 (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor
 benchmark and the Look-ahead, Authorization and Cancellation guides; with it
-stage M5 (execution) is complete. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
+stage M5 (execution) is complete. M6a (DataLoader) delivers `BatchLoader` and
+`GroupedLoader` (per-request batching after the microtask queue drains,
+de-duplication, a per-loader cache, `MissingValueException`) and the DataLoader
+guide. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
 file or a URL, the project's documents as one fragment graph, the planner and
 emitters that generate the schema-types library and a library per document
 (operations, variables, data, fragments, sealed polymorphic classes, the
@@ -499,6 +502,14 @@ request error, and disposes the timer and the listener when the run ends.
 subscription starts the timer and the listener at `subscribe`, and the run's
 own signal releases both when it fires, so an unlistened stream is freed by a
 cancel or a timeout (one with neither keeps its listener on the caller's signal).
+`dataloader/` (M6a): `BatchLoader` and `GroupedLoader` are thin faces over the
+internal `LoaderQueue`, which dispatches a batch with a zero-duration timer
+after the microtask queue drains, splits it into chunks of `maxBatchSize`,
+keeps the cache (a failed key is evicted by identity, so a later `clear` or
+`prime` of the same key survives), completes every key exactly once and puts a
+listener on every future it creates, so an unread load never reports an
+unhandled error. Loaders are request-scoped because the context factory
+creates them for each request.
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
```

- [ ] **Step 3: Run the documentation and discovery checks**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test test/doc" )' | tail -30
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )' | tail -30
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart doc" )' | tail -30
```

Expected: the suites pass and `dart doc` reports "Found 0 warnings and 0 errors". If the server package has no `test/doc` folder, skip that first command.

- [ ] **Step 4: Run the green check**

Run the green check above.

- [ ] **Step 5: Commit**

```sh
git add -A packages/typed_graphql_server README.md CLAUDE.md llms.txt docs/discovery.md
git commit -m "docs(typed_graphql_server): document the DataLoader" -m "Co-Authored-By: <your model trailer>"
```

(Original history: `ac3fdee` for the stage documents; the guide, the barrel, README and CHANGELOG entries came with `6d3c7d2` and `f78eee8`.)

## Verification against the commits

The plan was generated from these commits on `m6-final`, on top of `faf6ca5`:

```text
6d3c7d2 feat(typed_graphql_server): add BatchLoader
f78eee8 feat(typed_graphql_server): add GroupedLoader
164c2ae fix(typed_graphql_server): harden the DataLoader queue
3262abd test(typed_graphql_server): cover GroupedLoader copying and options
ac3fdee docs: record the DataLoader in the stage documents
```

(`e3bd58f`, the M6 design spec, is not part of the plan.) The Dart files in Tasks 1 and 2 were extracted with `git show HEAD:<path>` and pasted unchanged, so
`git diff faf6ca5..HEAD -- packages/typed_graphql_server/lib/src/dataloader packages/typed_graphql_server/test/dataloader`
matches the code in this plan: nine files (four in `lib/src/dataloader/`, five in `test/dataloader/`), each shown in full. The guide in Task 3 is `git show HEAD:packages/typed_graphql_server/doc/dataloader.md`, and the diffs of the other documents are `git diff faf6ca5..HEAD` for each path.
