import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/validation/value_checker.dart';
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
