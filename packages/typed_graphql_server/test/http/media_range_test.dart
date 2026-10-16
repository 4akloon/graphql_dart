import 'package:test/test.dart';
import 'package:typed_graphql_server/src/http/media_range.dart';
import 'package:typed_graphql_server/src/http/response_media_type.dart';

void main() {
  group('MediaRange.parse', () {
    test('reads the type, the subtype and a default quality of 1', () {
      final range = MediaRange.parse('application/json')!;
      expect(
        [range.type, range.subtype, range.quality],
        [
          'application',
          'json',
          1.0,
        ],
      );
    });

    test('lower-cases the names and trims blanks', () {
      final range = MediaRange.parse('  Application/JSON ; Q=0.5 ')!;
      expect(
        [range.type, range.subtype, range.quality],
        [
          'application',
          'json',
          0.5,
        ],
      );
    });

    test('reads the wildcards', () {
      expect(MediaRange.parse('*/*')!.type, '*');
      expect(MediaRange.parse('application/*')!.subtype, '*');
    });

    test('ignores parameters other than q', () {
      expect(
        MediaRange.parse('application/json; charset=utf-8; q=0.3')!.quality,
        0.3,
      );
    });

    test('accepts 0, 1 and three decimals', () {
      expect(MediaRange.parse('a/b;q=0')!.quality, 0.0);
      expect(MediaRange.parse('a/b;q=1.000')!.quality, 1.0);
      expect(MediaRange.parse('a/b;q=0.125')!.quality, 0.125);
    });

    test(
      'rejects a q above 1, with four decimals, negative or not a number',
      () {
        for (final q in ['1.5', '0.1234', '-0.1', 'x', '', '1.001', '2']) {
          expect(MediaRange.parse('a/b;q=$q'), isNull, reason: q);
        }
      },
    );

    test('rejects a q without a value', () {
      expect(MediaRange.parse('a/b;q'), isNull);
    });

    test('rejects a missing slash, an empty part and a wildcard type only', () {
      for (final text in ['json', '/json', 'application/', '', '*/json']) {
        expect(MediaRange.parse(text), isNull, reason: text);
      }
    });
  });

  group('MediaRange.specificityFor', () {
    const offered = ResponseMediaType.json;

    test('is 2 for the exact type', () {
      expect(MediaRange.parse('application/json')!.specificityFor(offered), 2);
    });

    test('is 1 for type/*', () {
      expect(MediaRange.parse('application/*')!.specificityFor(offered), 1);
    });

    test('is 0 for */*', () {
      expect(MediaRange.parse('*/*')!.specificityFor(offered), 0);
    });

    test('is null for another type or subtype', () {
      expect(MediaRange.parse('text/html')!.specificityFor(offered), isNull);
      expect(MediaRange.parse('text/*')!.specificityFor(offered), isNull);
      expect(
        MediaRange.parse('application/xml')!.specificityFor(offered),
        isNull,
      );
    });
  });
}
