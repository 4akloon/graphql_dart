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
    const member = NamedType(Name('A'));
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
      () => type.interfaces.add(const NamedType(Name('I'))),
      throwsUnsupportedError,
    );
  });
}
