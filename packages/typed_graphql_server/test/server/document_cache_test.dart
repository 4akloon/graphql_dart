import 'package:test/test.dart';
import 'package:typed_graphql_server/src/server/document_cache.dart';
import 'package:typed_graphql_server/src/server/document_entry.dart';
import 'package:typed_graphql_server/src/server/document_hash.dart';

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
      final first = cache.entryFor('{a}', compiler);
      final second = cache.entryFor('{a}', compiler);
      expect(second, same(first));
      expect(compiler.calls, 1);
    });

    test('the accepted entry holds one ValidDocument for the text', () {
      final cache = DocumentCache(10);
      final compiler = fixture.compiler;
      final first = cache.entryFor('{a}', compiler) as AcceptedEntry;
      final second = cache.entryFor('{a}', compiler) as AcceptedEntry;
      expect(second.document, same(first.document));
    });

    test('the entry carries the hash of the text', () {
      final entry = DocumentCache(10).entryFor('{a}', fixture.compiler);
      expect(entry.hash, const DocumentHash().of('{a}'));
    });

    test('compiles a failure once', () {
      final cache = DocumentCache(10);
      final compiler = fixture.countingCompiler;
      final first = cache.entryFor('{', compiler);
      final second = cache.entryFor('{', compiler);
      expect(second, same(first));
      expect(compiler.calls, 1);
    });

    test('evicts the least recently used entry', () {
      final cache = DocumentCache(2);
      final compiler = fixture.countingCompiler;
      cache
        ..entryFor('{a}', compiler)
        ..entryFor('{ a }', compiler)
        ..entryFor('{  a }', compiler);
      expect(cache.length, 2);
      cache.entryFor('{a}', compiler);
      expect(compiler.calls, 4);
    });

    test('a hit makes the entry the most recent', () {
      final cache = DocumentCache(2);
      final compiler = fixture.countingCompiler;
      cache
        ..entryFor('{a}', compiler)
        ..entryFor('{ a }', compiler)
        ..entryFor('{a}', compiler)
        ..entryFor('{  a }', compiler);
      expect(compiler.calls, 3);
      cache.entryFor('{a}', compiler);
      expect(compiler.calls, 3);
      cache.entryFor('{ a }', compiler);
      expect(compiler.calls, 4);
    });

    test('capacity 0 never stores', () {
      final cache = DocumentCache(0);
      final compiler = fixture.countingCompiler;
      cache
        ..entryFor('{a}', compiler)
        ..entryFor('{a}', compiler);
      expect(compiler.calls, 2);
      expect(cache.length, 0);
    });

    test('a negative capacity is an ArgumentError', () {
      expect(() => DocumentCache(-1), throwsArgumentError);
    });
  });
}
