import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  test('a schema with an object query root is valid', () {
    final validated = Validated('type Query { a: Int }');
    expect(validated.result, isA<ValidSchema>());
    expect(validated.result.diagnostics, isEmpty);
  });

  test('a schema without a query root is invalid', () {
    final validated = Validated('type Mutation { a: Int }');
    expect(validated.result, isA<InvalidSchema>());
    expect(validated.errors, [
      'null GQL111 Query root type must be provided.',
    ]);
  });

  test('the missing query root points at the schema definition', () {
    final validated = Validated('''
schema { mutation: M }
type M { a: Int }''');
    expect(validated.errors, [
      '1:1 GQL111 Query root type must be provided.',
    ]);
  });

  test('a root of another kind points at its name in the schema', () {
    final validated = Validated('''
schema { query: Q subscription: S }
input Q { a: Int }
scalar S''');
    expect(validated.errors, [
      '1:17 GQL112 Query root type must be Object type, it cannot be Q.',
      '1:33 GQL112 Subscription root type must be Object type if provided, '
          'it cannot be S.',
    ]);
  });

  test('a default root of another kind points at the type', () {
    final validated = Validated('''
scalar Mutation
type Query { a: Int }''');
    expect(validated.errors, [
      '1:1 GQL112 Mutation root type must be Object type if provided, it '
          'cannot be Mutation.',
    ]);
  });

  test('a type used as two roots is reported with both places', () {
    final validated = Validated('''
schema { query: Q mutation: Q }
type Q { a: Int }''');
    expect(validated.errors, [
      '1:17 GQL113 All root types must be different, "Q" type is used as '
          'query and mutation root types. | 1:29',
    ]);
  });

  test('a type used as three roots lists them with a serial comma', () {
    final validated = Validated('''
schema { query: Q mutation: Q subscription: Q }
type Q { a: Int }''');
    expect(validated.errors.single, contains('used as query, mutation, and '));
  });

  test('a root that names no type is left to the reference rules', () {
    final schema = Schema(queryTypeName: 'Missing');
    expect(Validated.schema(schema).codes, isNot(contains('GQL112')));
  });

  test('assumeValid wraps a schema without checking it', () {
    final schema = Schema();
    final valid = ValidSchema.assumeValid(schema);
    expect(valid.schema, same(schema));
    expect(valid.diagnostics, isEmpty);
  });

  test('the result keeps the schema it validated', () {
    final schema = Schema();
    expect(const SchemaValidator().validate(schema).schema, same(schema));
  });
}
