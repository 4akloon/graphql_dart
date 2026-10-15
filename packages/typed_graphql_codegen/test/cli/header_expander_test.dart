import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/cli/header_expander.dart';

void main() {
  const expander = HeaderExpander({'A': 'one', 'B': 'a\nb'});

  test('replaces every reference', () {
    final result = expander.expand({'X': r'${A}-${A}'});
    expect(result.headers, {'X': 'one-one'});
    expect(result.problems, isEmpty);
  });

  test('keeps a lone dollar, a double dollar and an unclosed brace', () {
    final result = expander.expand({'X': r'$ $$ ${A'});
    expect(result.headers, {'X': r'$ $$ ${A'});
  });

  test('a missing variable is GQL501 and drops the header', () {
    final result = expander.expand({'X': r'${NOPE}'});
    expect(result.headers, isEmpty);
    expect(result.problems.map((d) => d.toString()), [
      "error GQL501: The header 'X' uses the environment variable 'NOPE', "
          'which is not set.',
    ]);
  });

  test('a line break from the environment is GQL501', () {
    final result = expander.expand({'X': r'${B}'});
    expect(result.headers, isEmpty);
    expect(result.problems.map((d) => d.toString()), [
      "error GQL501: The value of header 'X' must not have a control "
          'character after its environment variables are expanded.',
    ]);
  });
}
