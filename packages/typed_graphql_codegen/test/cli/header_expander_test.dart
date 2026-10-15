import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/cli/header_expander.dart';

void main() {
  const expander = HeaderExpander({
    'A': 'one',
    'B': 'a\nb',
    'C': '',
    'D': 'caf\u00e9',
  });

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
          'which is not set or is empty.',
    ]);
  });

  test('a line break from the environment is GQL501', () {
    final result = expander.expand({'X': r'${B}'});
    expect(result.headers, isEmpty);
    expect(result.problems.map((d) => d.toString()), [
      "error GQL501: The value of header 'X' must be ASCII without a control "
          'character after its environment variables are expanded.',
    ]);
  });

  test('an empty variable is GQL501 as if it were not set', () {
    final result = expander.expand({'X': r'${C}'});
    expect(result.headers, isEmpty);
    expect(result.problems.map((d) => d.toString()), [
      "error GQL501: The header 'X' uses the environment variable 'C', "
          'which is not set or is empty.',
    ]);
  });

  test('a value that is not ASCII is GQL501', () {
    final result = expander.expand({'X': r'${D}'});
    expect(result.headers, isEmpty);
    expect(result.problems.map((d) => d.toString()), [
      "error GQL501: The value of header 'X' must be ASCII without a control "
          'character after its environment variables are expanded.',
    ]);
  });

  test('the secrets are the expanded values and the variable values', () {
    final result = expander.expand({'X': r'Bearer ${A}'});
    expect(result.secrets, ['Bearer one', 'one']);
  });
}
