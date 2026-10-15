import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final schema = Built('type Query { a: Int }').schema;
  final listing = IntrospectionListing(schema);

  test('lists own types, then referenced built-ins, then introspection', () {
    final names = [for (final type in listing.types) type.name];
    expect(names.first, 'Query');
    expect(names, containsAllInOrder(['Query', 'String', 'Int', '__Schema']));
    expect(names, isNot(contains('Float')));
  });

  test('lists the specified directives after the schema own', () {
    final names = [for (final directive in listing.directives) directive.name];
    expect(names, containsAll(['skip', 'include', 'deprecated']));
  });
}
