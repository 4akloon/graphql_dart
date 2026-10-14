import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const string = NamedType(Name('String'));

  /// What a `switch` over the sealed family says about [type].
  String kindOf(SchemaType type) => switch (type) {
    ScalarType() => 'scalar',
    ObjectType() => 'object',
    InterfaceType() => 'interface',
    UnionType() => 'union',
    EnumType() => 'enum',
    InputObjectType() => 'input object',
  };

  test('a switch over the family covers every kind', () {
    final types = <SchemaType>[
      ScalarType('Date'),
      ObjectType('Query'),
      InterfaceType('Node'),
      UnionType('Result'),
      EnumType('Color'),
      InputObjectType('Filter'),
    ];
    expect(types.map(kindOf), [
      'scalar',
      'object',
      'interface',
      'union',
      'enum',
      'input object',
    ]);
  });

  test('object and interface types find a field by name', () {
    final fields = [SchemaField('a', string), SchemaField('b', string)];
    expect(ObjectType('T', fields: fields).fieldNamed('b'), same(fields[1]));
    expect(InterfaceType('I', fields: fields).fieldNamed('a'), same(fields[0]));
    expect(ObjectType('T', fields: fields).fieldNamed('c'), isNull);
  });

  test('an input object type finds a field by name', () {
    final field = InputValue('limit', const NamedType(Name('Int')));
    expect(
      InputObjectType('Page', fields: [field]).fieldNamed('limit'),
      same(field),
    );
    expect(InputObjectType('Page').fieldNamed('offset'), isNull);
  });

  test('an enum type finds a value by name', () {
    final red = SchemaEnumValue('RED');
    expect(EnumType('Color', values: [red]).valueNamed('RED'), same(red));
    expect(EnumType('Color', values: [red]).valueNamed('BLUE'), isNull);
  });

  test('a scalar reads the url of @specifiedBy', () {
    final scalar = ScalarType(
      'Url',
      appliedDirectives: [
        AppliedDirective(
          'specifiedBy',
          arguments: [
            const Argument(
              Name('url'),
              StringValue('https://tools.ietf.org/html/rfc3986'),
            ),
          ],
        ),
      ],
    );
    expect(scalar.specifiedByUrl, 'https://tools.ietf.org/html/rfc3986');
    expect(ScalarType('Date').specifiedByUrl, isNull);
  });

  test('an input object type is one-of only with @oneOf', () {
    final oneOf = AppliedDirective('oneOf');
    expect(InputObjectType('A', appliedDirectives: [oneOf]).isOneOf, isTrue);
    expect(InputObjectType('B').isOneOf, isFalse);
  });

  test('a union keeps a repeated member for validation to report', () {
    const member = NamedTypeReference('A');
    final union = UnionType('U', memberTypes: [member, member]);
    expect(union.memberTypes, hasLength(2));
  });

  test('the lists of a type cannot be modified', () {
    final type = ObjectType('T');
    expect(
      () => type.fields.add(SchemaField('a', string)),
      throwsUnsupportedError,
    );
    expect(
      () => type.interfaces.add(const NamedTypeReference('I')),
      throwsUnsupportedError,
    );
  });

  test('every list of every kind cannot be modified', () {
    const member = NamedTypeReference('A');
    final additions = <void Function()>[
      () => ObjectType('T').appliedDirectives.add(AppliedDirective('d')),
      () => InterfaceType('I').interfaces.add(member),
      () => InterfaceType('I').fields.add(SchemaField('a', string)),
      () => UnionType('U').memberTypes.add(member),
      () => EnumType('E').values.add(SchemaEnumValue('A')),
      () => InputObjectType('F').fields.add(InputValue('a', string)),
      () => ScalarType('S').appliedDirectives.add(AppliedDirective('d')),
    ];
    for (final addition in additions) {
      expect(addition, throwsUnsupportedError);
    }
  });

  test('a type does not see the list it was built from change', () {
    final fields = [SchemaField('a', string)];
    final type = ObjectType('T', fields: fields);
    fields.add(SchemaField('b', string));
    expect(type.fields, hasLength(1));
    expect(type.fieldNamed('b'), isNull);
  });

  test('a @specifiedBy url that is not a string is no url', () {
    final scalar = ScalarType(
      'Url',
      appliedDirectives: [
        AppliedDirective(
          'specifiedBy',
          arguments: [const Argument(Name('url'), IntValue('1'))],
        ),
      ],
    );
    expect(scalar.specifiedByUrl, isNull);
  });

  test('a type keeps its description, directives and span', () {
    final span = SourceSpan(Source('type T'), 0, 6);
    final type = ObjectType(
      'T',
      description: 'A type.',
      appliedDirectives: [AppliedDirective('d')],
      span: span,
    );
    expect(type.description, 'A type.');
    expect(type.appliedDirectives.single.name, 'd');
    expect(type.span, same(span));
  });
}
