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
    expect(schema.typeNamed('__Type'), same(builtIns.typeNamed('__Type')));
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

  test('finds the first of two directives with one name', () {
    final first = SchemaDirective('key');
    final schema = Schema(directives: [first, SchemaDirective('key')]);
    expect(schema.directiveNamed('key'), same(first));
  });

  test('finds a declared type before a built-in of the same name', () {
    final int = ScalarType('Int');
    expect(Schema(types: [int]).typeNamed('Int'), same(int));
  });

  test('keeps the description, directives and span of the schema', () {
    final span = SourceSpan(Source('schema { query: Q }'), 0, 6);
    final schema = Schema(
      description: 'API',
      appliedDirectives: [AppliedDirective('key')],
      span: span,
    );
    expect(schema.description, 'API');
    expect(schema.appliedDirectives.single.name, 'key');
    expect(schema.span, same(span));
  });

  test('does not see the lists it was built from change', () {
    final types = [ScalarType('Date')];
    final directives = [SchemaDirective('key')];
    final schema = Schema(types: types, directives: directives);
    types.add(ScalarType('Time'));
    directives.add(SchemaDirective('auth'));
    expect(schema.types, hasLength(1));
    expect(schema.directives, hasLength(1));
    expect(schema.typeNamed('Time'), isNull);
    expect(schema.directiveNamed('auth'), isNull);
  });

  test('cannot be changed through its lists', () {
    final schema = Schema(types: [ScalarType('Date')]);
    expect(() => schema.types.add(ScalarType('Time')), throwsUnsupportedError);
    expect(
      () => schema.appliedDirectives.add(AppliedDirective('key')),
      throwsUnsupportedError,
    );
    expect(
      () => schema.directives.add(SchemaDirective('key')),
      throwsUnsupportedError,
    );
  });
}
