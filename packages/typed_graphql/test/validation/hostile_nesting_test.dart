import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

// Spec section 9 of M4 (R0.3): documents nested 100000 deep, built in code
// because the parser's depth limit would refuse them as text. No rule may
// recurse over them: on the web that overflows the stack.
void main() {
  final checked = Checked('''
type Query { node: Node nodes(filter: Filter, list: [[Int]]): [Node] }
type Node { name: String child: Node }
input Filter { name: String inner: Filter }
''');
  const depth = 100000;
  const limit = Duration(seconds: 10);
  final name = Field(null, const Name('name'));

  DocumentValidationResult timed(List<Definition> definitions) {
    final stopwatch = Stopwatch()..start();
    final result = const DocumentValidator().validate(
      checked.schema,
      Document(definitions),
    );
    expect(stopwatch.elapsed, lessThan(limit));
    return result;
  }

  OperationDefinition query(Selection selection) =>
      OperationDefinition(.query, SelectionSet([selection]));

  Field nodes(Argument argument) => Field(
    null,
    const Name('nodes'),
    arguments: [argument],
    selectionSet: SelectionSet([name]),
  );

  // `{ node { ...F0 } }` and fragments F0 to F[count - 1], each spreading
  // the next.
  List<Definition> chain(int count) => [
    query(
      Field(
        null,
        const Name('node'),
        selectionSet: SelectionSet([FragmentSpread(const Name('F0'))]),
      ),
    ),
    for (var index = 0; index < count; index++)
      FragmentDefinition(
        Name('F$index'),
        const NamedType(Name('Node')),
        SelectionSet([
          name,
          if (index < count - 1) FragmentSpread(Name('F${index + 1}')),
        ]),
      ),
  ];

  test('selections nested 100000 deep are valid', () {
    Selection field = name;
    for (var level = 0; level < depth; level++) {
      field = Field(
        null,
        const Name('child'),
        selectionSet: SelectionSet([field]),
      );
    }
    final node = Field(
      null,
      const Name('node'),
      selectionSet: SelectionSet([field]),
    );
    expect(timed([query(node)]), isA<ValidDocument>());
  });

  test('an input object nested 100000 deep is valid', () {
    Value value = ObjectValue([
      const ObjectField(Name('name'), StringValue('a')),
    ]);
    for (var level = 0; level < depth; level++) {
      value = ObjectValue([ObjectField(const Name('inner'), value)]);
    }
    final argument = Argument(const Name('filter'), value);
    expect(timed([query(nodes(argument))]), isA<ValidDocument>());
  });

  test('a list nested 100000 deep is one value error', () {
    Value value = const IntValue('1');
    for (var level = 0; level < depth; level++) {
      value = ListValue([value]);
    }
    final argument = Argument(const Name('list'), value);
    final result = timed([query(nodes(argument))]) as InvalidDocument;
    expect(
      result.diagnostics.single.code,
      DiagnosticCode.valuesOfCorrectType,
    );
  });

  test('a chain of 100000 fragments is valid', () {
    expect(timed(chain(depth)), isA<ValidDocument>());
  });
}
