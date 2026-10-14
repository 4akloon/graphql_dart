import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../validated.dart';

void main() {
  const string = NamedType(Name('String'));
  final query = ObjectType('Query', fields: [SchemaField('a', string)]);
  List<String> errorsOf({
    List<SchemaType> types = const [],
    List<SchemaDirective> directives = const [],
  }) => Validated.schema(
    Schema(
      types: [query, ...types],
      directives: directives,
      queryTypeName: 'Query',
    ),
  ).errors;

  test('two types with one name are reported once', () {
    expect(errorsOf(types: [ScalarType('S'), ScalarType('S')]), [
      'null GQL101 There can be only one type named "S".',
    ]);
  });

  test('a type with a built-in name is reported', () {
    expect(errorsOf(types: [ScalarType('String')]), [
      'null GQL103 The built-in type "String" cannot be redefined.',
    ]);
  });

  test('two directives with one name are reported once', () {
    final directive = SchemaDirective('d', locations: const [.field]);
    expect(errorsOf(directives: [directive, directive]), [
      'null GQL102 There can be only one directive named "@d".',
    ]);
  });

  test('a directive with a built-in name is reported', () {
    final skip = SchemaDirective('skip', locations: const [.field]);
    expect(errorsOf(directives: [skip]), [
      'null GQL103 The built-in directive "@skip" cannot be redefined.',
    ]);
  });

  test('two fields with one name are reported with their coordinate', () {
    final type = ObjectType(
      'T',
      fields: [SchemaField('f', string), SchemaField('f', string)],
    );
    expect(errorsOf(types: [type]), [
      'null GQL104 Field "T.f" can only be defined once.',
    ]);
  });

  test('two input fields with one name are reported', () {
    final type = InputObjectType(
      'In',
      fields: [InputValue('f', string), InputValue('f', string)],
    );
    expect(errorsOf(types: [type]), [
      'null GQL104 Field "In.f" can only be defined once.',
    ]);
  });

  test('two arguments of a field with one name are reported', () {
    final type = InterfaceType(
      'I',
      fields: [
        SchemaField(
          'f',
          string,
          arguments: [InputValue('a', string), InputValue('a', string)],
        ),
      ],
    );
    expect(errorsOf(types: [type]), [
      'null GQL105 Argument "I.f(a:)" can only be defined once.',
    ]);
  });

  test('two arguments of a directive with one name are reported', () {
    final directive = SchemaDirective(
      'd',
      arguments: [InputValue('a', string), InputValue('a', string)],
      locations: const [.field],
    );
    expect(errorsOf(directives: [directive]), [
      'null GQL105 Argument "@d(a:)" can only be defined once.',
    ]);
  });

  test('two enum values with one name are reported', () {
    final type = EnumType(
      'E',
      values: [SchemaEnumValue('A'), SchemaEnumValue('A')],
    );
    expect(errorsOf(types: [type]), [
      'null GQL106 Enum value "E.A" can only be defined once.',
    ]);
  });

  test('a repeat relates to the span of the first', () {
    final sdl = Built('type Query { a: Int }').schema;
    final first = sdl.types.single;
    final schema = Schema(types: [first, first], queryTypeName: 'Query');
    expect(Validated.schema(schema).errors, [
      '1:1 GQL101 There can be only one type named "Query". | 1:1',
    ]);
  });
}
