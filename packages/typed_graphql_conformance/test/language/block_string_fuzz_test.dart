// Ported from graphql-js src/language/__tests__/blockString-fuzz.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const blockString = BlockString();

  /// graphql-js's `genFuzzStrings`: the empty string, then every string of
  /// [allowedChars] up to [maxLength] characters.
  Iterable<String> genFuzzStrings(
    List<String> allowedChars,
    int maxLength,
  ) sync* {
    final count = allowedChars.length;
    var combinations = 0;
    var power = 1;
    for (var length = 1; length <= maxLength; length++) {
      power *= count;
      combinations += power;
    }
    yield ''; // special case for empty string
    for (var combination = 0; combination < combinations; combination++) {
      var permutation = '';
      for (
        var leftOver = combination;
        leftOver >= 0;
        leftOver = leftOver ~/ count - 1
      ) {
        permutation = allowedChars[leftOver % count] + permutation;
      }
      yield permutation;
    }
  }

  String lexValue(String text) {
    final lexer = Lexer(Source(text), DiagnosticSink());
    final value = lexer.advance().value;
    if (value == null || lexer.advance().kind != TokenKind.eof) {
      fail('Expected one string token in ${text.codeUnits}');
    }
    return value;
  }

  group('printBlockString', () {
    test('correctly print random strings', () {
      for (final fuzzStr in genFuzzStrings(const [
        '\n',
        '\t',
        ' ',
        '"',
        'a',
        r'\',
      ], 7)) {
        if (!blockString.isPrintable(fuzzStr)) {
          final printed = lexValue(blockString.print(fuzzStr));
          if (printed == fuzzStr) {
            fail('Expected the value of ${fuzzStr.codeUnits} to change');
          }
          continue;
        }
        for (final isMinified in const [false, true]) {
          final printed = blockString.print(fuzzStr, isMinified: isMinified);
          if (lexValue(printed) != fuzzStr) {
            fail(
              'Expected ${printed.codeUnits} to lex as ${fuzzStr.codeUnits}',
            );
          }
        }
      }
    });
  });
}
