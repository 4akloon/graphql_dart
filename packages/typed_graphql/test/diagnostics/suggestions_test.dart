import 'package:test/test.dart';
import 'package:typed_graphql/src/diagnostics/suggestions.dart';

// The cases of graphql-js's suggestionList, didYouMean and naturalCompare
// suites (src/jsutils/__tests__).
void main() {
  const suggestions = Suggestions();

  group('listFor', () {
    test('returns results when input is empty', () {
      expect(suggestions.listFor('', ['a']), ['a']);
    });

    test('returns an empty list when there are no options', () {
      expect(suggestions.listFor('input', []), isEmpty);
    });

    test('returns options with small lexical distance', () {
      expect(suggestions.listFor('greenish', ['green']), ['green']);
      expect(suggestions.listFor('green', ['greenish']), ['greenish']);
    });

    test('rejects options with distance that exceeds threshold', () {
      expect(suggestions.listFor('aaaa', ['aaab']), ['aaab']);
      expect(suggestions.listFor('aaaa', ['aabb']), ['aabb']);
      expect(suggestions.listFor('aaaa', ['abbb']), isEmpty);
      expect(suggestions.listFor('ab', ['ca']), isEmpty);
    });

    test('returns options with different case', () {
      expect(suggestions.listFor('verylongstring', ['VERYLONGSTRING']), [
        'VERYLONGSTRING',
      ]);
      expect(suggestions.listFor('VERYLONGSTRING', ['VeryLongString']), [
        'VeryLongString',
      ]);
    });

    test('returns options with transpositions', () {
      expect(suggestions.listFor('agr', ['arg']), ['arg']);
      expect(suggestions.listFor('214365879', ['123456789']), ['123456789']);
    });

    test('sorts options by lexical distance', () {
      expect(suggestions.listFor('abc', ['a', 'ab', 'abc']), [
        'abc',
        'ab',
        'a',
      ]);
      expect(
        suggestions.listFor('GraphQl', [
          'graphics',
          'SQL',
          'GraphQL',
          'quarks',
          'mark',
        ]),
        ['GraphQL', 'graphics'],
      );
    });

    test('sorts options at the same distance naturally', () {
      expect(suggestions.listFor('a', ['az', 'ax', 'ay']), ['ax', 'ay', 'az']);
      expect(suggestions.listFor('abc', ['a1', 'a12', 'a2']), [
        'a1',
        'a2',
        'a12',
      ]);
      expect(
        suggestions.listFor('csutomer', [
          'store',
          'customer',
          'stomer',
          'some',
          'more',
        ]),
        ['customer', 'stomer', 'some', 'store'],
      );
    });

    test('drops long options against a short input at once', () {
      final long = 'a' * 100000;
      expect(suggestions.listFor('a', [long]), isEmpty);
      expect(suggestions.listFor(long, ['a']), isEmpty);
    });
  });

  group('didYouMean', () {
    test('is empty for no suggestion', () {
      expect(suggestions.didYouMean([]), '');
    });

    test('lists one, two and several suggestions', () {
      expect(suggestions.didYouMean(['A']), ' Did you mean "A"?');
      expect(suggestions.didYouMean(['A', 'B']), ' Did you mean "A" or "B"?');
      expect(
        suggestions.didYouMean(['A', 'B', 'C']),
        ' Did you mean "A", "B", or "C"?',
      );
    });

    test('lists at most five suggestions', () {
      expect(
        suggestions.didYouMean(['A', 'B', 'C', 'D', 'E', 'F']),
        ' Did you mean "A", "B", "C", "D", or "E"?',
      );
    });

    test('names the subject', () {
      expect(
        suggestions.didYouMean(['A'], subject: 'the letter'),
        ' Did you mean the letter "A"?',
      );
    });
  });

  group('naturalCompare', () {
    int compare(String a, String b) => suggestions.naturalCompare(a, b);

    test('handles empty strings and different lengths', () {
      expect(compare('', ''), 0);
      expect(compare('', 'a'), -1);
      expect(compare('1', ''), 1);
      expect(compare('A1', 'A1A'), -1);
      expect(compare('A1A', 'A1'), 1);
    });

    test('compares numbers by value', () {
      expect(compare('1', '2'), -1);
      expect(compare('2', '11'), -1);
      expect(compare('11', '2'), 1);
    });

    test('takes a leading zero alone', () {
      expect(compare('00', '00'), 0);
      expect(compare('0', '00'), -1);
      expect(compare('02', '11'), -1);
      expect(compare('011', '200'), -1);
      expect(compare('200', '011'), 1);
    });

    test('compares numbers embedded into names', () {
      expect(compare('a0a', 'a9a'), -1);
      expect(compare('a00a', 'a09a'), -1);
      expect(compare('a0a9', 'a0a1'), 1);
      expect(compare('a10a11a', 'a10a19a'), -1);
      expect(compare('a10a11b', 'a10a11a'), 1);
    });

    test('compares runs longer than any integer', () {
      expect(compare('a${'9' * 40}', 'a1${'0' * 40}'), -1);
    });
  });
}
