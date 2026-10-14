import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('SourceLocation', () {
    test('compares by line and column', () {
      expect(const SourceLocation(2, 3), const SourceLocation(2, 3));
      expect(const SourceLocation(2, 3), isNot(const SourceLocation(3, 2)));
      expect(
        const SourceLocation(2, 3).hashCode,
        const SourceLocation(2, 3).hashCode,
      );
    });

    test('prints line:column', () {
      expect(const SourceLocation(2, 3).toString(), '2:3');
    });
  });

  group('Source.locationOf', () {
    test('counts lines and columns from 1', () {
      final source = Source('ab\ncd');
      expect(source.locationOf(0), const SourceLocation(1, 1));
      expect(source.locationOf(1), const SourceLocation(1, 2));
      expect(source.locationOf(3), const SourceLocation(2, 1));
      expect(source.locationOf(4), const SourceLocation(2, 2));
    });

    test('places the line feed on the line it ends', () {
      expect(Source('ab\ncd').locationOf(2), const SourceLocation(1, 3));
    });

    test('accepts the end of the document', () {
      expect(Source('ab\n').locationOf(3), const SourceLocation(2, 1));
      expect(Source('').locationOf(0), const SourceLocation(1, 1));
    });

    test(r'treats \r\n as one line terminator', () {
      final source = Source('a\r\nb');
      expect(source.locationOf(3), const SourceLocation(2, 1));
      expect(source.locationOf(1), const SourceLocation(1, 2));
      expect(source.locationOf(2), const SourceLocation(1, 3));
    });

    test(r'treats a lone \r as a line terminator', () {
      final source = Source('a\rb\r\rc');
      expect(source.locationOf(2), const SourceLocation(2, 1));
      expect(source.locationOf(4), const SourceLocation(3, 1));
      expect(source.locationOf(5), const SourceLocation(4, 1));
    });

    test(r'counts \n\r as two line terminators', () {
      expect(Source('a\n\rb').locationOf(3), const SourceLocation(3, 1));
    });

    test('does not treat U+2028 and U+2029 as line terminators', () {
      expect(
        Source('a b c').locationOf(4),
        const SourceLocation(1, 5),
      );
    });

    test('counts a byte order mark as one column', () {
      expect(Source('﻿query').locationOf(1), const SourceLocation(1, 2));
    });

    test('counts columns in UTF-16 code units', () {
      // U+1F600 is two code units, so `x` after it is column 3.
      expect(Source('\u{1F600}x').locationOf(2), const SourceLocation(1, 3));
    });

    test('finds the line in a long document', () {
      final source = Source(List.filled(1000, 'line').join('\n'));
      expect(source.locationOf(999 * 5 + 2), const SourceLocation(1000, 3));
      expect(source.locationOf(500 * 5), const SourceLocation(501, 1));
    });

    test('rejects an offset outside the document', () {
      final source = Source('ab');
      expect(() => source.locationOf(-1), throwsRangeError);
      expect(() => source.locationOf(3), throwsRangeError);
    });

    test('names a document from the wire like graphql-js', () {
      expect(Source('{ a }').name, 'GraphQL request');
      expect(Source('{ a }', name: 'lib/a.graphql').name, 'lib/a.graphql');
    });
  });

  group('SourceSpan', () {
    final source = Source('query {\n  hero\n}', name: 'hero.graphql');

    test('gives the location of its start and its text', () {
      final span = SourceSpan(source, 10, 14);
      expect(span.location, const SourceLocation(2, 3));
      expect(span.text, 'hero');
    });

    test('may be empty, at the end of the document', () {
      final end = source.body.length;
      expect(SourceSpan(source, end, end).text, '');
      expect(SourceSpan(source, end, end).location, const SourceLocation(3, 2));
    });

    test('prints name:line:column', () {
      expect(SourceSpan(source, 10, 14).toString(), 'hero.graphql:2:3');
    });

    test('is equal only for the same source and offsets', () {
      final same = Source(source.body, name: source.name);
      expect(SourceSpan(source, 10, 14), SourceSpan(source, 10, 14));
      expect(
        SourceSpan(source, 10, 14).hashCode,
        SourceSpan(source, 10, 14).hashCode,
      );
      expect(SourceSpan(source, 10, 14), isNot(SourceSpan(same, 10, 14)));
      expect(SourceSpan(source, 10, 14), isNot(SourceSpan(source, 10, 13)));
    });

    test('throws a RangeError when it runs past the document', () {
      final span = SourceSpan(source, 0, source.body.length + 1);
      expect(() => span.text, throwsRangeError);
      expect(
        () => SourceSpan(source, 99, 99).location,
        throwsRangeError,
      );
    });
  });
}
