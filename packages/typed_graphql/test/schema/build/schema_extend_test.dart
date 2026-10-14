import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final base = Built('''
directive @key on OBJECT
type Query { a: Int }
enum Color { RED }''').schema;

  List<String> fieldsOf(Schema schema, String type) => [
    for (final field in (schema.typeNamed(type) as ObjectType).fields)
      field.name,
  ];

  test('adds new types after the schema\'s and keeps its roots', () {
    final schema = Built.extending(base, 'type Mutation { b: Int }').schema;
    expect(schema.types.map((type) => type.name), [
      'Query',
      'Color',
      'Mutation',
    ]);
    expect(schema.queryTypeName, 'Query');
    expect(schema.mutationTypeName, isNull);
  });

  test('extends a type of the schema after its own fields', () {
    final schema = Built.extending(base, 'extend type Query { b: Int }').schema;
    expect(fieldsOf(schema, 'Query'), ['a', 'b']);
    expect(fieldsOf(base, 'Query'), ['a']);
  });

  test('keeps the spans of both sources', () {
    final schema = Built.extending(base, 'extend type Query { b: Int }').schema;
    final query = schema.typeNamed('Query') as ObjectType;
    expect(query.span?.text, 'type Query { a: Int }');
    expect(query.fieldNamed('b')?.span?.text, 'b: Int');
  });

  test('gives the schema back for a document without definitions', () {
    final result = const SchemaBuilder().extend(base, Document(const []));
    expect((result as BuildSuccess).schema, same(base));
  });

  test('gives the schema back, failed, for operations only', () {
    final built = Built.extending(base, 'query { a }');
    expect(built.partial, same(base));
    expect(built.errors.single, contains('GQL100'));
  });

  test('rejects a field the schema\'s type has', () {
    final built = Built.extending(base, 'extend type Query { a: String }');
    expect(built.errors, [
      '1:21 GQL104 Field "Query.a" already exists in the schema. It cannot '
          'also be defined in this type extension.',
    ]);
    expect(built.result.diagnostics.single.related, isEmpty);
  });

  test('rejects an enum value the schema\'s type has', () {
    expect(Built.extending(base, 'extend enum Color { RED }').errors, [
      '1:21 GQL106 Enum value "Color.RED" already exists in the schema. It '
          'cannot also be defined in this type extension.',
    ]);
  });

  test('words a repeat of a field added by the document as a repeat', () {
    final built = Built.extending(base, '''
extend type Query { b: Int }
extend type Query { b: Int }''');
    expect(built.errors, [
      '2:21 GQL104 Field "Query.b" can only be defined once.',
    ]);
  });

  test('rejects a type the schema has', () {
    expect(Built.extending(base, 'enum Query { A }').errors, [
      '1:6 GQL101 Type "Query" already exists in the schema. It cannot also '
          'be defined in this type definition.',
    ]);
  });

  test('takes no default root types', () {
    final schema = Built.extending(Schema(), 'type Query { a: Int }').schema;
    expect(schema.queryTypeName, isNull);
  });

  test('keeps whether the schema includes @defer and @stream', () {
    final withDefer = Schema(includesDeferAndStream: true);
    final built = Built.extending(withDefer, 'directive @defer on FIELD');
    expect(built.errors.single, contains('GQL103'));
    expect(built.partial.includesDeferAndStream, isTrue);
  });

  group('directive extensions', () {
    test('add directives to a directive of the schema', () {
      final schema = Built.extending(base, 'extend directive @key @a').schema;
      final key = schema.directiveNamed('key');
      expect(key?.appliedDirectives.map((directive) => directive.name), [
        'a',
      ]);
      expect(base.directiveNamed('key')?.appliedDirectives, isEmpty);
    });

    test('add directives to a directive of the document', () {
      final schema = Built('''
extend directive @d @b
directive @d @a on FIELD''').schema;
      final d = schema.directiveNamed('d');
      expect(d?.appliedDirectives.map((directive) => directive.name), [
        'a',
        'b',
      ]);
    });

    test('report a directive that is not defined', () {
      expect(Built('extend directive @missing @a').errors, [
        '1:19 GQL109 Cannot extend directive "@missing" because it is not '
            'defined.',
      ]);
    });

    test('report a built-in directive', () {
      expect(Built('extend directive @skip @a').errors, [
        '1:19 GQL103 The built-in directive "@skip" cannot be extended.',
      ]);
    });
  });
}
