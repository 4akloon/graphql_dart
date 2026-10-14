import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const builtIns = BuiltIns();

  test('keeps types and directives in declaration order', () {
    final schema = Schema(
      types: [ObjectType('Query'), ScalarType('Date'), EnumType('Color')],
      directives: [SchemaDirective('key'), SchemaDirective('auth')],
    );
    expect(schema.types.map((type) => type.name), ['Query', 'Date', 'Color']);
    expect(schema.directives.map((directive) => directive.name), [
      'key',
      'auth',
    ]);
  });

  test('finds a declared type by name', () {
    final date = ScalarType('Date');
    final schema = Schema(types: [ObjectType('Query'), date]);
    expect(schema.typeNamed('Date'), same(date));
    expect(schema.typeNamed('Time'), isNull);
  });

  test('finds the first of two types with one name', () {
    final first = ScalarType('Date');
    final schema = Schema(types: [first, EnumType('Date')]);
    expect(schema.typeNamed('Date'), same(first));
  });

  test('finds the built-in scalars and introspection types undeclared', () {
    final schema = Schema();
    expect(schema.typeNamed('Int'), same(builtIns.scalarNamed('Int')));
    expect(schema.typeNamed('__Type'), same(builtIns.introspectionTypes[1]));
  });

  test('finds the five specified directives undeclared', () {
    final schema = Schema();
    expect(
      schema.directiveNamed('skip'),
      same(builtIns.directiveNamed('skip')),
    );
    expect(schema.directiveNamed('oneOf'), isNotNull);
    expect(schema.directiveNamed('key'), isNull);
  });

  test('finds @defer and @stream only when they are included', () {
    expect(Schema().directiveNamed('defer'), isNull);
    final schema = Schema(includesDeferAndStream: true);
    expect(schema.directiveNamed('defer'), same(builtIns.defer));
    expect(schema.directiveNamed('stream'), same(builtIns.stream));
  });

  test('prefers a declared directive to a built-in of the same name', () {
    final skip = SchemaDirective('skip');
    expect(Schema(directives: [skip]).directiveNamed('skip'), same(skip));
  });

  test('has no root operation types unless they are named', () {
    final schema = Schema();
    expect(schema.queryTypeName, isNull);
    expect(schema.mutationTypeName, isNull);
    expect(schema.subscriptionTypeName, isNull);
  });

  test('finds the root operation type by operation', () {
    final schema = Schema(
      queryTypeName: 'Root',
      subscriptionTypeName: 'Events',
    );
    expect(schema.rootTypeName(OperationType.query), 'Root');
    expect(schema.rootTypeName(OperationType.mutation), isNull);
    expect(schema.rootTypeName(OperationType.subscription), 'Events');
  });

  test('cannot be changed through its lists', () {
    final schema = Schema(types: [ScalarType('Date')]);
    expect(() => schema.types.add(ScalarType('Time')), throwsUnsupportedError);
    expect(
      () => schema.appliedDirectives.add(AppliedDirective('key')),
      throwsUnsupportedError,
    );
  });
}
