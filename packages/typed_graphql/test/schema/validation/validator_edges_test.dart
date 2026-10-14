import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../validated.dart';

void main() {
  const string = NamedType(Name('String'));

  test('a directive on the schema definition is checked at SCHEMA', () {
    expect(
      Validated('schema @deprecated { query: Query }\ntype Query { a: Int }')
          .errors,
      [
        '1:8 GQL118 Directive "@deprecated" may not be used on SCHEMA.',
      ],
    );
  });

  test('a directive on a schema extension is checked at SCHEMA', () {
    expect(
      Validated('type Query { a: Int }\nextend schema @deprecated').errors,
      [
        '2:15 GQL118 Directive "@deprecated" may not be used on SCHEMA.',
      ],
    );
  });

  test('defer and stream are built in only where the schema includes them', () {
    final directives = [
      SchemaDirective('defer', locations: const [DirectiveLocation.field]),
    ];
    Schema schema({required bool includes}) => Schema(
      types: [
        ObjectType('Query', fields: [SchemaField('a', string)]),
      ],
      directives: directives,
      queryTypeName: 'Query',
      includesDeferAndStream: includes,
    );
    expect(Validated.schema(schema(includes: true)).codes, ['GQL103']);
    expect(Validated.schema(schema(includes: false)).codes, isEmpty);
  });

  test('more than 100 problems end with the limit error', () {
    final types = [
      for (var i = 0; i < 150; i++) ScalarType('__S$i'),
    ];
    final result = const SchemaValidator().validate(
      Schema(
        types: [
          ObjectType('Query', fields: [SchemaField('a', string)]),
          ...types,
        ],
        queryTypeName: 'Query',
      ),
    );
    expect(result.diagnostics, hasLength(101));
    expect(result.diagnostics.last.code.id, 'GQL000');
  });

  test('three repeats of a name give two errors related to the first', () {
    final base = Built('type Query { a: Int }\ntype S { b: Int }').schema;
    final repeated = base.typeNamed('S')!;
    final validated = Validated.schema(
      Schema(
        types: [...base.types, repeated, repeated],
        queryTypeName: 'Query',
      ),
    );
    expect(validated.errors, [
      '2:1 GQL101 There can be only one type named "S". | 2:1',
      '2:1 GQL101 There can be only one type named "S". | 2:1',
    ]);
  });

  test('an invalid schema result needs a diagnostic', () {
    expect(
      () => InvalidSchema(Built('type Query { a: Int }').schema, const []),
      throwsA(isA<AssertionError>()),
    );
  });
}
