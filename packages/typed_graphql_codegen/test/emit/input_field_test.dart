import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_type.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/input_field.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';

void main() {
  InputField field(String sdl, {bool isExclusive = false}) {
    final document = const Parser()
        .parse(Source('enum Role { A }\ninput Probe { $sdl }'))
        .requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    final input = (schema.typeNamed('Probe')! as InputObjectType).fields.first;
    final mapper = TypeMapper(schema, const {});
    return isExclusive
        ? InputField.exclusive(input, mapper, Imports())
        : InputField.of(input, mapper, Imports());
  }

  test('a non-null field without a default is required', () {
    final InputField result = field('a: Int!');
    expect(result.isOptional, false);
    expect(result.fieldType, 'int');
    expect(result.doc, 'The field `a`.');
  });

  test('a nullable field is optional with a nullable value', () {
    final InputField result = field('a: Int');
    expect(result.isOptional, true);
    expect(result.fieldType, 'graphql.Optional<int?>');
    expect(
      result.value,
      const DartType(
        'int?',
        'client.NullableDataCodec(client.ScalarDataCodec(graphql.IntCodec()))',
      ),
    );
  });

  test('a non-null field with a default is optional with a non-null value', () {
    final InputField result = field('a: [Int!]! = [1, 2]');
    expect(result.isOptional, true);
    expect(result.fieldType, 'graphql.Optional<List<int>>');
    expect(result.doc, 'The field `a`. Its default is `[1, 2]`.');
  });

  test('a description, a default and a deprecation are all kept', () {
    final InputField result = field(
      '"Says it." a: Role = A @deprecated(reason: "Use b.")',
    );
    expect(
      result.doc,
      'Says it. Its default is `A`.\n\nDeprecated: Use b.',
    );
  });

  test('a name that is a reserved word gets a dollar', () {
    expect(field('default: Int').dartName, r'default$');
    expect(field('codec: Int').dartName, r'codec$');
  });

  test('a list value is found for equality, a named type is not', () {
    expect(field('a: [Int]').holdsList, true);
    expect(field('a: Role').holdsList, false);
  });

  test('an interpolation of a name with a dollar uses braces', () {
    expect(field('default: Int').interpolation, r'${default$}');
    expect(field('a: Int').interpolation, r'$a');
  });

  test('an exclusive field is given and has the non-null type', () {
    final InputField result = field('a: Int', isExclusive: true);
    expect(result.isOptional, false);
    expect(result.fieldType, 'int');
  });
}
