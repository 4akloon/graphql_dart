import 'package:test/test.dart';
import 'package:typed_graphql/src/validation/cost/cost_number.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../schema/built.dart';
import '../checked.dart';

const _sdl = '''
type Query {
  users(first: Int): [User]
    @listSize(slicingArguments: ["first"], requireOneSlicingArgument: false)
  negative: [User] @listSize(assumedSize: -5)
}
type User {
  name: String
  friends(first: Int): [User]
    @listSize(slicingArguments: ["first"], requireOneSlicingArgument: false)
}
''';

const _builder = SchemaBuilder(includesCostDirectives: true);

OperationCost _cost(
  String text, {
  Map<String, JsonValue> variables = const {},
  int defaultListSize = 10,
}) {
  final document = const Parser(
    options: ParserOptions(maxTokens: null),
  ).parse(Source(text)).requireDocument();
  return CostAnalysis(
    Built(_sdl, builder: _builder).schema,
    defaultListSize: defaultListSize,
  ).costOf(
    document,
    document.definitions.whereType<OperationDefinition>().first,
    variables: variables,
  );
}

void main() {
  final hugeLiteral = '9' * 400;
  final checked = Checked(_sdl, builder: _builder);

  test('a 400-digit slicing literal costs a finite number', () {
    final cost = _cost('{ users(first: $hugeLiteral) { friends { name } } }');
    expect(cost.fieldCost.isFinite, isTrue);
    expect(cost.fieldCost, greaterThan(1e300));
  });

  test('MaxCostRule reports an overflowing operation', () {
    expect(
      checked.errors('{ users(first: $hugeLiteral) { name } }', [
        const MaxCostRule(maxCost: 1000000),
      ]),
      [contains('GQL238')],
    );
  });

  test('first: 0 over an overflowing child costs the field alone', () {
    final cost = _cost(
      '{ users(first: 0) { friends(first: $hugeLiteral) '
      '{ friends(first: $hugeLiteral) { name } } } }',
    );
    expect(cost.fieldCost, 1);
    expect(cost.typeCost, 1);
  });

  test('nested default lists that overflow stay finite', () {
    final text = '{ users ${'{ friends ' * 30} { name } ${'}' * 30} }';
    final cost = _cost(text, defaultListSize: 1000000000000000);
    expect(cost.fieldCost.isFinite, isTrue);
    expect(cost.typeCost.isFinite, isTrue);
    expect(
      checked.errors(text, [
        const MaxCostRule(maxCost: 1e300, defaultListSize: 1000000000000000),
      ]),
      [contains('GQL238')],
    );
  });

  test('a negative assumedSize counts as 0', () {
    expect(_cost('{ negative { name } }').typeCost, 1);
  });

  test('a variable beyond the safe-integer range is its double value', () {
    final cost = _cost(
      r'query ($n: Int) { users(first: $n) { friends(first: 1) { name } } }',
      variables: {'n': JsonNumber(1e16)},
    );
    expect(cost.fieldCost, 1e16);
  });

  test('a negative zero prints as 0', () {
    expect(CostNumber(0.0 * -1).text, '0');
  });
}
