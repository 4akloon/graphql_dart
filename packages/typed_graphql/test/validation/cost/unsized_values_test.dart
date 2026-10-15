import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../schema/built.dart';

// `first` has no default and no assumedSize: a value that names no size
// falls to `defaultListSize` (10).
const _plain = '''
type Query {
  items(first: Int): [Item] @listSize(slicingArguments: ["first"])
}
type Item { id: ID }
''';

const _defaulted = '''
type Query {
  items(first: Int = 4): [Item] @listSize(slicingArguments: ["first"])
}
type Item { id: ID }
''';

const _assumed = '''
type Query {
  items(first: Int): [Item]
    @listSize(assumedSize: 7, slicingArguments: ["first"], requireOneSlicingArgument: false)
}
type Item { id: ID }
''';

final class _Costs {
  const _Costs();

  OperationCost of(
    String sdl,
    String text, {
    Map<String, JsonValue> variables = const {},
  }) {
    final schema = Built(
      sdl,
      builder: const SchemaBuilder(includesCostDirectives: true),
    ).schema;
    final document = const Parser().parse(Source(text)).requireDocument();
    final operation = document.definitions
        .whereType<OperationDefinition>()
        .first;
    return CostAnalysis(
      schema,
    ).costOf(document, operation, variables: variables);
  }
}

const _costs = _Costs();
const _byVariable = r'query ($n: Int) { items(first: $n) { id } }';

void main() {
  group('a variable without a value', () {
    test('takes the default of the slicing argument', () {
      // Types: 1 + 4 * (1 + 0) = 5.
      expect(_costs.of(_defaulted, _byVariable), const OperationCost(1, 5));
    });

    test('takes assumedSize', () {
      // Types: 1 + 7 * (1 + 0) = 8.
      expect(_costs.of(_assumed, _byVariable), const OperationCost(1, 8));
    });
  });

  group('a variable value that names no size', () {
    test('an explicit null does not take the variable default', () {
      // An explicit null overrides the default: 1 + 10 * (1 + 0) = 11.
      expect(
        _costs.of(
          _plain,
          r'query ($n: Int = 2) { items(first: $n) { id } }',
          variables: {'n': const JsonNull()},
        ),
        const OperationCost(1, 11),
      );
    });

    test('a negative number counts as not given', () {
      expect(
        _costs.of(_plain, _byVariable, variables: {'n': JsonNumber(-5)}),
        const OperationCost(1, 11),
      );
    });

    test('a string does not take the variable default', () {
      expect(
        _costs.of(
          _plain,
          r'query ($n: Int = 2) { items(first: $n) { id } }',
          variables: {'n': const JsonString('many')},
        ),
        const OperationCost(1, 11),
      );
    });

    test('an explicit null takes the argument default', () {
      expect(
        _costs.of(_defaulted, _byVariable, variables: {'n': const JsonNull()}),
        const OperationCost(1, 5),
      );
    });
  });

  test('a negative literal counts as not given', () {
    expect(
      _costs.of(_plain, '{ items(first: -5) { id } }'),
      const OperationCost(1, 11),
    );
  });

  test('zero is a size', () {
    // Types: 1 + 0 * (1 + 0) = 1.
    expect(
      _costs.of(_plain, _byVariable, variables: {'n': JsonNumber(0)}),
      const OperationCost(1, 1),
    );
  });
}
