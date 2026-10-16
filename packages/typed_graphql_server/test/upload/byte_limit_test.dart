import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/src/upload/byte_limit.dart';
import 'package:typed_graphql_server/src/upload/byte_limit_exceeded.dart';

void main() {
  Stream<List<int>> chunks(List<int> sizes) => Stream.fromIterable([
    for (final size in sizes) List.filled(size, 1),
  ]);

  group('ByteLimit', () {
    test('passes a stream within the limit unchanged', () async {
      final result = await ByteLimit(6).bind(chunks([3, 3])).toList();
      expect(result.map((chunk) => chunk.length), [3, 3]);
    });

    test('passes a stream of exactly the limit', () async {
      final result = await ByteLimit(4).bind(chunks([4])).toList();
      expect(result, hasLength(1));
    });

    test('fails with ByteLimitExceeded past the limit', () async {
      await expectLater(
        ByteLimit(5).bind(chunks([3, 3])).toList(),
        throwsA(isA<ByteLimitExceeded>()),
      );
    });

    test('emits the chunks before the one that passes the limit', () async {
      final seen = <int>[];
      final limit = ByteLimit(5);
      await limit
          .bind(chunks([3, 3, 1]))
          .forEach((chunk) => seen.add(chunk.length))
          .onError<ByteLimitExceeded>((error, stack) {});
      expect(seen, [3]);
    });

    test('stops reading the source after the failure', () async {
      var pulled = 0;
      final source = Stream<List<int>>.fromIterable(
        Iterable.generate(100, (_) {
          pulled++;
          return [1, 1];
        }),
      );
      await ByteLimit(3)
          .bind(source)
          .drain<void>()
          .onError<ByteLimitExceeded>((error, stack) {});
      expect(pulled, lessThan(5));
    });

    test('names the limit that failed', () async {
      final limit = ByteLimit(1);
      final error = await limit
          .bind(chunks([2]))
          .drain<void>()
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect((error! as ByteLimitExceeded).origin, same(limit));
    });

    test('admits counts the bytes of every call', () {
      final limit = ByteLimit(4);
      expect(limit.admits(3), isTrue);
      expect(limit.admits(1), isTrue);
      expect(limit.admits(1), isFalse);
    });
  });
}
