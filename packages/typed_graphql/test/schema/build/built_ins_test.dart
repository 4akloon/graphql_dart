import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const builtIns = BuiltIns();

  test('has the five scalars of the spec, in its order', () {
    expect(builtIns.scalars.map((scalar) => scalar.name), [
      'String',
      'Int',
      'Float',
      'Boolean',
      'ID',
    ]);
    expect(builtIns.scalarNamed('Int')?.description, startsWith('The `Int`'));
    expect(builtIns.scalarNamed('Date'), isNull);
  });

  test('has the five directives of the spec, in its order', () {
    expect(builtIns.directives.map((directive) => directive.name), [
      'include',
      'skip',
      'deprecated',
      'specifiedBy',
      'oneOf',
    ]);
    expect(builtIns.directiveNamed('defer'), isNull);
  });

  test('defines @deprecated as September2025 does', () {
    final deprecated = builtIns.directiveNamed('deprecated')!;
    expect(deprecated.locations, [
      DirectiveLocation.fieldDefinition,
      DirectiveLocation.argumentDefinition,
      DirectiveLocation.inputFieldDefinition,
      DirectiveLocation.enumValue,
    ]);
    final reason = deprecated.argumentNamed('reason')!;
    expect(const Printer().print(reason.type), 'String!');
    expect(
      const Printer().print(reason.defaultValue!),
      '"No longer supported"',
    );
  });

  test('keeps @defer and @stream apart, as graphql-js defines them', () {
    expect(builtIns.defer.name, 'defer');
    expect(builtIns.defer.arguments.map((argument) => argument.name), [
      'if',
      'label',
    ]);
    expect(builtIns.stream.locations, [DirectiveLocation.field]);
    expect(builtIns.stream.arguments.map((argument) => argument.name), [
      'initialCount',
      'if',
      'label',
    ]);
  });

  test('has the introspection types of the spec, in its order', () {
    expect(builtIns.introspectionTypes.map((type) => type.name), [
      '__Schema',
      '__Type',
      '__TypeKind',
      '__Field',
      '__InputValue',
      '__EnumValue',
      '__Directive',
      '__DirectiveLocation',
    ]);
  });

  test('leaves out the working-draft introspection additions', () {
    final directive = builtIns.introspectionTypes[6] as ObjectType;
    expect(directive.fieldNamed('isDeprecated'), isNull);
    final locations = builtIns.introspectionTypes[7] as EnumType;
    expect(locations.values, hasLength(19));
    expect(locations.valueNamed('DIRECTIVE_DEFINITION'), isNull);
  });

  test('declares includeDeprecated as Boolean! = false everywhere', () {
    final type = builtIns.introspectionTypes[1] as ObjectType;
    final field = builtIns.introspectionTypes[3] as ObjectType;
    final directive = builtIns.introspectionTypes[6] as ObjectType;
    final arguments = [
      type.fieldNamed('fields')!.argumentNamed('includeDeprecated'),
      type.fieldNamed('enumValues')!.argumentNamed('includeDeprecated'),
      type.fieldNamed('inputFields')!.argumentNamed('includeDeprecated'),
      field.fieldNamed('args')!.argumentNamed('includeDeprecated'),
      directive.fieldNamed('args')!.argumentNamed('includeDeprecated'),
    ];
    for (final argument in arguments) {
      expect(const Printer().print(argument!.type), 'Boolean!');
      expect(const Printer().print(argument.defaultValue!), 'false');
    }
  });

  test('gives the specified directives their locations', () {
    const common = [
      DirectiveLocation.field,
      DirectiveLocation.fragmentSpread,
      DirectiveLocation.inlineFragment,
    ];
    expect(builtIns.directiveNamed('include')!.locations, common);
    expect(builtIns.directiveNamed('skip')!.locations, common);
    expect(builtIns.directiveNamed('specifiedBy')!.locations, [
      DirectiveLocation.scalar,
    ]);
    expect(builtIns.directiveNamed('oneOf')!.locations, [
      DirectiveLocation.inputObject,
    ]);
  });

  test('types introspection fields with their nullability', () {
    final schema = builtIns.introspectionTypes[0] as ObjectType;
    final type = builtIns.introspectionTypes[1] as ObjectType;
    expect(const Printer().print(type.fieldNamed('kind')!.type), '__TypeKind!');
    expect(const Printer().print(type.fieldNamed('name')!.type), 'String');
    expect(
      const Printer().print(schema.fieldNamed('types')!.type),
      '[__Type!]!',
    );
    expect(
      const Printer().print(schema.fieldNamed('mutationType')!.type),
      '__Type',
    );
  });

  test('lists the values of __TypeKind', () {
    final kinds = builtIns.introspectionTypes[2] as EnumType;
    expect(kinds.values.map((value) => value.name), [
      'SCALAR',
      'OBJECT',
      'INTERFACE',
      'UNION',
      'ENUM',
      'INPUT_OBJECT',
      'LIST',
      'NON_NULL',
    ]);
  });

  test('gives @defer and @stream their argument defaults', () {
    String? defaultOf(SchemaDirective directive, String name) {
      final value = directive.argumentNamed(name)!.defaultValue;
      return value == null ? null : const Printer().print(value);
    }

    expect(defaultOf(builtIns.defer, 'if'), 'true');
    expect(defaultOf(builtIns.defer, 'label'), isNull);
    expect(defaultOf(builtIns.stream, 'initialCount'), '0');
    expect(defaultOf(builtIns.stream, 'if'), 'true');
    expect(builtIns.defer.locations, [
      DirectiveLocation.fragmentSpread,
      DirectiveLocation.inlineFragment,
    ]);
  });

  test('finds a scalar or an introspection type by name', () {
    expect(builtIns.typeNamed('ID'), same(builtIns.scalarNamed('ID')));
    expect(builtIns.typeNamed('__Field'), same(builtIns.introspectionTypes[3]));
    expect(builtIns.typeNamed('Query'), isNull);
  });

  test('has no spans: nothing was read from a user source', () {
    expect(builtIns.scalars.first.span, isNull);
    expect(builtIns.directives.first.span, isNull);
    expect(builtIns.directives.first.arguments.single.span, isNull);
  });

  test('tells the built-in directives, @defer and @stream by the flag', () {
    expect(
      builtIns.isBuiltInDirective('skip', includesDeferAndStream: false),
      isTrue,
    );
    expect(
      builtIns.isBuiltInDirective('defer', includesDeferAndStream: false),
      isFalse,
    );
    expect(
      builtIns.isBuiltInDirective('stream', includesDeferAndStream: true),
      isTrue,
    );
    expect(
      builtIns.isBuiltInDirective('key', includesDeferAndStream: true),
      isFalse,
    );
  });

  test('gives the same instances on every call', () {
    expect(const BuiltIns().scalars.first, same(builtIns.scalars.first));
    expect(builtIns.defer, same(const BuiltIns().defer));
  });
}
