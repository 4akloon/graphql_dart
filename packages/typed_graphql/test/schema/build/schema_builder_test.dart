import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  test('builds types and directives in declaration order', () {
    final built = Built('''
      directive @key(fields: String!) on OBJECT
      scalar Date
      type Query { today: Date }
      enum Color { RED }
    ''');
    expect(built.typeNames, ['Date', 'Query', 'Color']);
    expect(built.schema.directives.single.name, 'key');
    expect(built.schema.typeNamed('Query'), isA<ObjectType>());
  });

  test('builds an empty schema from an empty document', () {
    final schema = const SchemaBuilder().fromSdl(Document(const []));
    expect(schema, isA<BuildSuccess>());
    expect(schema.diagnostics, isEmpty);
  });

  test('takes the root types from the types named after them', () {
    final schema = Built('''
      type Query { a: Int }
      type Mutation { a: Int }
      type Subscription { a: Int }
    ''').schema;
    expect(schema.queryTypeName, 'Query');
    expect(schema.mutationTypeName, 'Mutation');
    expect(schema.subscriptionTypeName, 'Subscription');
  });

  test('has no root without a type named after it', () {
    final schema = Built('type Root { a: Int }').schema;
    expect(schema.queryTypeName, isNull);
  });

  test('takes the root types from the schema definition only', () {
    final schema = Built('''
      "The API." schema @key { query: Root }
      type Root { a: Int }
      type Mutation { a: Int }
    ''').schema;
    expect(schema.queryTypeName, 'Root');
    expect(schema.mutationTypeName, isNull);
    expect(schema.description, 'The API.');
    expect(schema.appliedDirectives.single.name, 'key');
    expect(schema.span?.text, startsWith('"The API." schema'));
  });

  test('keeps a reference to an unknown type: building does not validate', () {
    final field = Built('type Query { a: Missing }').schema.typeNamed('Query');
    expect(field, isA<ObjectType>());
  });

  test('gives every element the span of its definition', () {
    final type = Built('type Query { a: Int }').schema.typeNamed('Query');
    expect(type?.span?.text, 'type Query { a: Int }');
    expect(type?.span?.source.name, 'schema.graphql');
  });

  test('gives no spans without a source', () {
    final document = Sdl('type Query { a: Int }').document;
    final result = const SchemaBuilder().fromSdl(document);
    expect((result as BuildSuccess).schema.types.single.span, isNull);
  });

  test('reports an operation or a fragment and builds the rest', () {
    final built = Built('''
query { a }
type Query { a: Int }
fragment F on Query { a }''');
    expect(built.errors, [
      '1:1 GQL100 A schema document cannot hold operations or fragments.',
      '3:1 GQL100 A schema document cannot hold operations or fragments.',
    ]);
    expect(built.partial.typeNamed('Query'), isNotNull);
  });

  test('adds @defer and @stream when the builder includes them', () {
    const builder = SchemaBuilder(includesDeferAndStream: true);
    final schema = Built('type Query { a: Int }', builder: builder).schema;
    expect(schema.includesDeferAndStream, isTrue);
    expect(schema.directiveNamed('defer'), isNotNull);
    expect(
      Built('type Query { a: Int }').schema.includesDeferAndStream,
      isFalse,
    );
  });
}
