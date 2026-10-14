import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  group('limits (R1.6)', () {
    test('a selection set 100 000 levels deep gives one depth error', () {
      const depth = 100000;
      final text = '${'{a' * depth}${'}' * depth}';
      final parsed = Parsed(
        text,
        options: const ParserOptions(maxTokens: null),
      );
      expect(parsed.errors, [
        '1:257 GQL010 Document nests deeper than 128 levels.',
      ]);
    });

    test('the token limit stops a long document with one error', () {
      final parsed = Parsed('{ ${'a ' * 20000}}');
      expect(
        parsed.result.diagnostics.single.code,
        DiagnosticCode.tokenLimitExceeded,
      );
    });

    test('the sink stops after maxErrors errors with GQL000', () {
      // `query` follows `!` because recovery treats `{` as a definition start
      // only after `}` or at the document start.
      final parsed = Parsed('{ a } ! query { a } ' * 300);
      final codes = parsed.result.diagnostics.map(
        (diagnostic) => diagnostic.code,
      );
      expect(codes, hasLength(DiagnosticSink.defaultMaxErrors + 1));
      expect(codes.last, DiagnosticCode.diagnosticLimitReached);
    });
  });

  group('unterminated input gives one error and ends', () {
    test('in a string argument', () {
      expect(Parsed('{ a(b: "x').errors, ['1:10 GQL004 Unterminated string.']);
    });

    test('in a block string', () {
      expect(Parsed('"""abc').errors, ['1:7 GQL004 Unterminated string.']);
    });

    test('in nested selection sets', () {
      expect(Parsed('{ a { b ').errors, [
        '1:9 GQL007 Expected Name, found <EOF>.',
      ]);
    });

    test('in an argument definition list', () {
      expect(Parsed('type T { f(a: Int').errors, [
        '1:18 GQL007 Expected Name, found <EOF>.',
      ]);
    });
  });

  group('values', () {
    test('an integer past 64 bits keeps its raw lexeme', () {
      const lexeme = '123456789012345678901234567890';
      final value = switch (const Parser().parseValue(Source(lexeme))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };
      expect(
        value,
        isA<IntValue>().having((literal) => literal.value, 'value', lexeme),
      );
    });

    test('a lone surrogate in a selection is one error', () {
      expect(Parsed('{ a \uD800 b }').errors, [
        '1:5 GQL002 Invalid character: U+D800.',
      ]);
    });
  });
}
