@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'introspection_view.dart';
import 'random_parts.dart';
import 'random_schema.dart';
import 'schema_dump.dart';

/// R10.4 and spec §11 of M3, property 1 through introspection: a random
/// schema, written as introspection and built back, holds what
/// introspection carries of it, and writes the same introspection again
/// (graphql-js's `cycleIntrospection`).
void main() {
  final budget = FuzzBudget(defaultIterations: 300);
  const view = IntrospectionView();
  const dump = SchemaDump();

  void check(int index) {
    final random = RandomSchema(RandomParts(budget.randomFor(index)));
    final schema = view.closed(random.schema());
    final introspection = schema.toIntrospection();
    final reason = budget.replay(index);
    final client = switch (const SchemaBuilder().fromIntrospection(
      introspection,
    )) {
      BuildSuccess(:final schema) => schema,
      BuildFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
    };
    expect(dump.of(client), dump.of(view.carried(schema)), reason: reason);
    expect(client.toIntrospection(), introspection, reason: reason);
  }

  test('introspection then build gives what introspection carries', () {
    for (var index = 0; index < budget.iterations; index++) {
      var isDone = false;
      try {
        check(index);
        isDone = true;
      } finally {
        // The generator and the writer can throw too; name the replay.
        if (!isDone) printOnFailure(budget.replay(index));
      }
    }
  });

  test('a closed schema keeps only references the schema has', () {
    final schema = view.closed(
      Schema(
        types: [
          ObjectType(
            'Query',
            interfaces: [const NamedTypeReference('Missing')],
            fields: [SchemaField('a', const ListType(NamedType(Name('X'))))],
          ),
        ],
        queryTypeName: 'Query',
      ),
    );
    final query = schema.typeNamed('Query')! as ObjectType;
    expect(query.interfaces, isEmpty);
    expect(const Printer().print(query.fields.single.type), '[String]');
  });
}
