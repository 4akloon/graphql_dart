import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/validation/value_checker.dart';
import 'package:typed_graphql/src/schema/validation/value_problem_kind.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final schema = Built('''
type Query { a: Int }
input In { a: In b: Int }''').schema;
  const input = NamedType(Name('In'));

  test('a value nested 100000 deep is checked without recursion', () {
    Value value = ObjectValue(const []);
    for (var depth = 0; depth < 100000; depth++) {
      value = ObjectValue([ObjectField(const Name('a'), value)]);
    }
    expect(ValueChecker(schema).check(value, input), isEmpty);
  });

  test('a problem deep inside a value has the whole path', () {
    Value value = ObjectValue([
      const ObjectField(Name('b'), StringValue('x')),
    ]);
    for (var depth = 0; depth < 3; depth++) {
      value = ObjectValue([ObjectField(const Name('a'), value)]);
    }
    final problem = ValueChecker(schema).check(value, input).single;
    expect(problem.pathText, ' at .a.a.a.b');
  });

  test('a variable built in code is not a constant', () {
    final problem = ValueChecker(
      schema,
    ).check(const Variable(Name('v')), const NamedType(Name('Int'))).single;
    expect(problem.message, r'Expected a constant value, found: $v.');
  });

  test('an Int literal built in code with other text is not an integer', () {
    final problem = ValueChecker(
      schema,
    ).check(const IntValue('x'), const NamedType(Name('Int'))).single;
    expect(problem.message, 'Int cannot represent non-integer value: x');
  });

  test('allowsVariables accepts a variable anywhere in the value', () {
    final value = ObjectValue([
      const ObjectField(Name('a'), Variable(Name('v'))),
      const ObjectField(Name('b'), Variable(Name('w'))),
    ]);
    // The variables' types are the variable rules' to check.
    expect(
      ValueChecker(schema, allowsVariables: true).check(value, input),
      isEmpty,
    );
  });

  test('each problem has the kind of the rule it breaks', () {
    final enums = Built('''
type Query { a: Int }
input Req { r: Int! s: Int }''').schema;
    final value = ObjectValue([
      const ObjectField(Name('s'), StringValue('x')),
      const ObjectField(Name('t'), IntValue('1')),
    ]);
    final kinds = [
      for (final problem in ValueChecker(
        enums,
      ).check(value, const NamedType(Name('Req'))))
        problem.kind,
    ];
    expect(kinds, [
      ValueProblemKind.missingField,
      ValueProblemKind.invalid,
      ValueProblemKind.unknownField,
    ]);
  });

  group('includesSuggestions', () {
    final enums = Built('''
type Query { a: Int }
enum Color { RED BLUE }
input Pick { color: Color shade: Int }''').schema;
    List<String> messages(Value value, String type, bool suggests) => [
      for (final problem in ValueChecker(
        enums,
        includesSuggestions: suggests,
      ).check(value, NamedType(Name(type))))
        problem.message,
    ];

    test('suggests an enum value', () {
      expect(messages(const EnumValue('RDE'), 'Color', true), [
        'Value "RDE" does not exist in "Color" enum. Did you mean the enum '
            'value "RED"?',
      ]);
      expect(messages(const StringValue('RED'), 'Color', true), [
        'Enum "Color" cannot represent non-enum value: "RED". Did you mean '
            'the enum value "RED"?',
      ]);
    });

    test('suggests an input field', () {
      expect(
        messages(
          ObjectValue([const ObjectField(Name('colr'), EnumValue('RED'))]),
          'Pick',
          true,
        ),
        [
          'Expected value of type "Pick" not to include unknown field '
              '"colr". Did you mean "color"? Found: { colr: RED }.',
        ],
      );
    });

    test('is off by default', () {
      expect(messages(const EnumValue('RDE'), 'Color', false), [
        'Value "RDE" does not exist in "Color" enum.',
      ]);
      expect(
        messages(
          ObjectValue([const ObjectField(Name('colr'), EnumValue('RED'))]),
          'Pick',
          false,
        ),
        [
          'Expected value of type "Pick" not to include unknown field '
              '"colr", found: { colr: RED }.',
        ],
      );
    });
  });

  test('a deep value given to a leaf type is not printed whole', () {
    Value value = ListValue(const []);
    for (var depth = 0; depth < 100000; depth++) {
      value = ListValue([value]);
    }
    final problem = ValueChecker(
      schema,
    ).check(value, const NamedType(Name('Int'))).single;
    expect(problem.message, 'Int cannot represent non-integer value: [ ... ]');
  });

  test('a value of an output or unknown type is left to the type rules', () {
    const value = IntValue('1');
    expect(
      ValueChecker(schema).check(value, const NamedType(Name('Query'))),
      isEmpty,
    );
    expect(
      ValueChecker(schema).check(value, const NamedType(Name('Missing'))),
      isEmpty,
    );
  });
}
