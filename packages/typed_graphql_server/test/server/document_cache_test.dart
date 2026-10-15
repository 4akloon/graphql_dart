import 'package:test/test.dart';
import 'package:typed_graphql_server/src/server/document_cache.dart';
import 'package:typed_graphql_server/src/server/document_hash.dart';
import 'package:typed_graphql_server/src/server/document_result.dart';

import 'support/compiler_fixture.dart';

void main() {
  const fixture = CompilerFixture();

  group('DocumentHash', () {
    test('is the lower-case hex SHA-256 of the UTF-8 bytes', () {
      expect(
        const DocumentHash().of('{a}'),
        '460c3a93211614ac783c0f1d1bbbcb45a6da87d6421b5c0771772588f1015ff8',
      );
    });

    test('hashes bytes, not code units', () {
      expect(
        const DocumentHash().of('{a} # é'),
        isNot(const DocumentHash().of('{a} # e')),
      );
    });
  });

  group('DocumentCache', () {
    test('returns the same accepted entry for the same text', () {
      final cache = DocumentCache(10);
      final compiler = fixture.countingCompiler;
      final first = cache.resultFor('{a}', compiler);
      final second = cache.resultFor('{a}', compiler);
      expect(second, same(first));
      expect(compiler.calls, 1);
    });

    test('the accepted entry holds one ValidDocument for the text', () {
      final cache = DocumentCache(10);
      final compiler = fixture.compiler;
      final first = cache.resultFor('{a}', compiler) as DocumentAccepted;
      final second = cache.resultFor('{a}', compiler) as DocumentAccepted;
      expect(second.document, same(first.document));
    });

    test('the result carries the hash of the text', () {
      final result = DocumentCache(
        10,
      ).resultFor('{a}', fixture.compiler) as DocumentAccepted;
      expect(result.hash, const DocumentHash().of('{a}'));
    });

    test('compiles a failure once', () {
      final cache = DocumentCache(10);
      final compiler = fixture.countingCompiler;
      final first = cache.resultFor('{', compiler);
      final second = cache.resultFor('{', compiler);
      expect(second, same(first));
      expect(compiler.calls, 1);
    });

    test('evicts the least recently used entry', () {
      final cache = DocumentCache(2);
      final compiler = fixture.countingCompiler;
      cache
        ..resultFor('{a}', compiler)
        ..resultFor('{ a }', compiler)
        ..resultFor('{  a }', compiler);
      expect(cache.length, 2);
      cache.resultFor('{a}', compiler);
      expect(compiler.calls, 4);
    });

    test('a hit makes the entry the most recent', () {
      final cache = DocumentCache(2);
      final compiler = fixture.countingCompiler;
      cache
        ..resultFor('{a}', compiler)
        ..resultFor('{ a }', compiler)
        ..resultFor('{a}', compiler)
        ..resultFor('{  a }', compiler);
      expect(compiler.calls, 3);
      cache.resultFor('{a}', compiler);
      expect(compiler.calls, 3);
      cache.resultFor('{ a }', compiler);
      expect(compiler.calls, 4);
    });

    test('capacity 0 never stores', () {
      final cache = DocumentCache(0);
      final compiler = fixture.countingCompiler;
      cache
        ..resultFor('{a}', compiler)
        ..resultFor('{a}', compiler);
      expect(compiler.calls, 2);
      expect(cache.length, 0);
    });

    group('the total length bound', () {
      String text(String label, int length) =>
          '{a} # $label'.padRight(length, '-');

      test('evicts the least recently used entries past the bound', () {
        final cache = DocumentCache(100, maxTotalLength: 100);
        final compiler = fixture.countingCompiler;
        for (var index = 0; index < 20; index++) {
          cache.resultFor(text('t$index', 30), compiler);
        }
        expect(cache.totalLength, lessThanOrEqualTo(100));
        expect(cache.length, 3);
      });

      test('a text longer than the bound is not cached', () {
        final cache = DocumentCache(10, maxTotalLength: 100);
        final compiler = fixture.countingCompiler;
        final huge = text('huge', 101);
        cache
          ..resultFor(huge, compiler)
          ..resultFor(huge, compiler);
        expect(compiler.calls, 2);
        expect(cache.length, 0);
      });

      test('one huge text does not evict the small entries', () {
        final cache = DocumentCache(10, maxTotalLength: 100);
        final compiler = fixture.countingCompiler;
        cache
          ..resultFor('{a}', compiler)
          ..resultFor('{ a }', compiler)
          ..resultFor(text('huge', 5000), compiler)
          ..resultFor('{a}', compiler)
          ..resultFor('{ a }', compiler);
        expect(compiler.calls, 3);
        expect(cache.length, 2);
      });

      test('many large distinct texts stay under the budget', () {
        final cache = DocumentCache(1000, maxTotalLength: 10000);
        final compiler = fixture.countingCompiler;
        for (var index = 0; index < 500; index++) {
          cache.resultFor(text('t$index', 900), compiler);
          expect(cache.totalLength, lessThanOrEqualTo(10000));
        }
      });

      test('a negative bound is an ArgumentError', () {
        expect(
          () => DocumentCache(1, maxTotalLength: -1),
          throwsArgumentError,
        );
      });
    });

    test('a negative capacity is an ArgumentError', () {
      expect(() => DocumentCache(-1), throwsArgumentError);
    });
  });
}
