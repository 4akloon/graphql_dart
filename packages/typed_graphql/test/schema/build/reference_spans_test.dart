import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final base = Built('''
schema { query: Query }
interface A { a: Int }
interface B { a: Int }
type Query implements A { a: Int }
type M { a: Int }
union U = Query''').schema;

  test('an implemented interface has the span of its name', () {
    final query = base.typeNamed('Query') as ObjectType;
    final span = query.interfaces.single.span;
    expect(span?.text, 'A');
    expect(span?.location, const SourceLocation(4, 23));
  });

  test('a union member has the span of its name', () {
    final union = base.typeNamed('U') as UnionType;
    expect(
      union.memberTypes.single.span?.location,
      const SourceLocation(6, 11),
    );
  });

  test('an interface added by an extension has a span in its source', () {
    const text = 'extend type Query implements B';
    final schema = Built.extending(base, text).schema;
    final query = schema.typeNamed('Query') as ObjectType;
    final added = query.interfaces.last.span;
    expect(added?.text, 'B');
    expect(added?.source.body, text);
    expect(query.interfaces.first.span?.source, same(query.span?.source));
  });

  test('a union member added by an extension has a span in its source', () {
    const text = 'extend union U = M';
    final schema = Built.extending(base, text).schema;
    final union = schema.typeNamed('U') as UnionType;
    expect(union.memberTypes.last.span?.source.body, text);
  });

  test('a root type has the span of its name in the schema definition', () {
    final span = base.rootTypeSpan(OperationType.query);
    expect(span?.text, 'Query');
    expect(span?.location, const SourceLocation(1, 17));
  });

  test('a root type added by a schema extension has a span in its source', () {
    const text = 'extend schema { mutation: M }';
    final schema = Built.extending(base, text).schema;
    expect(schema.rootTypeSpan(OperationType.mutation)?.source.body, text);
    expect(
      schema.rootTypeSpan(OperationType.query),
      same(base.rootTypeSpan(OperationType.query)),
    );
  });

  test('a default root type has no span', () {
    final schema = Built('type Query { a: Int }').schema;
    expect(schema.queryTypeName, 'Query');
    expect(schema.rootTypeSpan(OperationType.query), isNull);
  });

  test('a schema built in code keeps the root spans it is given', () {
    final span = SourceSpan(Source('Root'), 0, 4);
    final schema = Schema(
      queryTypeName: 'Root',
      rootTypeSpans: {OperationType.query: span},
    );
    expect(schema.rootTypeSpan(OperationType.query), same(span));
    expect(schema.rootTypeSpan(OperationType.mutation), isNull);
  });
}
