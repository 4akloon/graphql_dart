import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/generator/schema_type_usage.dart';

const _sdl = '''
enum Role { ADMIN }
enum Color { RED }
enum Unused { A }
input Leaf { color: Color }
input Cycle { next: Cycle, leaf: Leaf }
input Orphan { value: Int }
input Filter { role: Role, more: [Cycle!] }
type User { id: ID!, role: Role!, color: Color }
type Query {
  user(filter: Filter): User
  users: [User!]!
}
''';

void main() {
  List<String> used(String query) {
    final schema = (const SchemaBuilder().fromSdl(
      const Parser().parse(Source(_sdl)).requireDocument(),
    ) as BuildSuccess).schema;
    final document = const Parser().parse(Source(query)).requireDocument();
    return [
      for (final type in SchemaTypeUsage(schema).of(document)) type.name,
    ];
  }

  test('a variable reaches its input object and what that holds', () {
    expect(used(r'query Q($f: Filter) { users { id } }'), [
      'Color',
      'Cycle',
      'Filter',
      'Leaf',
      'Role',
    ]);
  });

  test('a selected field reaches its enum', () {
    expect(used('query Q { users { role } }'), ['Role']);
  });

  test('a fragment field reaches its enum', () {
    expect(used('fragment F on User { color }'), ['Color']);
  });

  test('a type no variable or field reaches is absent', () {
    expect(used(r'query Q($f: Leaf) { users { id } }'), ['Color', 'Leaf']);
  });

  test('an input object that refers to itself is listed once', () {
    expect(used(r'query Q($c: Cycle!) { users { id } }'), [
      'Color',
      'Cycle',
      'Leaf',
    ]);
  });

  test('a document with no variables and only scalar fields uses nothing', () {
    expect(used('query Q { users { id } }'), isEmpty);
  });
}
