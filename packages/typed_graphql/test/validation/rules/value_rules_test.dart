import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes, the split of one
// graphql-js rule into three and the branches those suites do not reach.
void main() {
  final checked = Checked('''
scalar Any
input In { a: Int! b: Int next: In }
type Query { f(arg: In): Int any(arg: Any): Int }
''');
  const query = '{ f(arg: { b: "x", c: 1 }) }';
  const valueRules = <ValidationRule>[
    ValuesOfCorrectTypeRule(),
    InputObjectFieldNamesRule(),
    InputObjectRequiredFieldsRule(),
  ];

  test('a value of the wrong type is GQL218', () {
    expect(checked.errors(query, [const ValuesOfCorrectTypeRule()]), [
      '1:15 GQL218 Int cannot represent non-integer value: "x"',
    ]);
  });

  test('an unknown input field is GQL219', () {
    expect(checked.errors(query, [const InputObjectFieldNamesRule()]), [
      '1:20 GQL219 Expected value of type "In" not to include unknown field '
          '"c". Did you mean "a" or "b"? Found: { b: "x", c: 1 }.',
    ]);
  });

  test('a missing required input field is GQL221', () {
    expect(checked.errors(query, [const InputObjectRequiredFieldsRule()]), [
      '1:10 GQL221 Expected value of type "In" to include required field '
          '"a", found: { b: "x", c: 1 }.',
    ]);
  });

  test('a repeated input field is GQL220', () {
    expect(
      checked.errors('{ f(arg: { a: 1, a: 2 }) }', [
        const UniqueInputFieldNamesRule(),
      ]),
      ['1:12 GQL220 There can be only one input field named "a".'],
    );
  });

  test('a variable is not checked as a value', () {
    expect(
      checked.errors(r'query($v: Int) { f(arg: { a: $v }) }', valueRules),
      isEmpty,
    );
  });

  test('a value is checked once, at its outermost literal', () {
    expect(
      checked.errors('{ f(arg: { a: 1, next: { a: "x" } }) }', [
        const ValuesOfCorrectTypeRule(),
      ]),
      ['1:29 GQL218 Int cannot represent non-integer value: "x"'],
    );
  });

  group('values nested 100000 deep, built in code', () {
    const depth = 100000;

    List<Diagnostic> validate(
      String field,
      Value argument, {
      int maxErrors = 100,
    }) {
      final document = Document([
        OperationDefinition(
          OperationType.query,
          SelectionSet([
            Field(
              null,
              Name(field),
              arguments: [Argument(const Name('arg'), argument)],
            ),
          ]),
        ),
      ]);
      return DocumentValidator(
        rules: [...valueRules, UniqueInputFieldNamesRule()],
        maxErrors: maxErrors,
      ).validate(checked.schema, document).diagnostics;
    }

    test('a list value', () {
      Value value = const IntValue('1');
      for (var i = 0; i < depth; i++) {
        value = ListValue([value]);
      }
      expect(validate('any', value), isEmpty);
    });

    test('an object value', () {
      Value value = const IntValue('1');
      for (var i = 0; i < depth; i++) {
        value = ObjectValue([ObjectField(const Name('a'), value)]);
      }
      expect(validate('any', value), isEmpty);
    });

    test('an input object value of a recursive input type', () {
      Value value = ObjectValue([
        const ObjectField(Name('a'), IntValue('1')),
      ]);
      for (var i = 0; i < depth; i++) {
        value = ObjectValue([
          const ObjectField(Name('a'), IntValue('1')),
          ObjectField(const Name('next'), value),
        ]);
      }
      expect(validate('f', value), isEmpty);
    });

    test('an input object value missing a field at every level', () {
      Value value = ObjectValue([]);
      for (var i = 0; i < depth; i++) {
        value = ObjectValue([ObjectField(const Name('next'), value)]);
      }
      final stopwatch = Stopwatch()..start();
      final diagnostics = validate('f', value, maxErrors: depth + 10);
      expect(diagnostics, hasLength(depth + 1));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}
