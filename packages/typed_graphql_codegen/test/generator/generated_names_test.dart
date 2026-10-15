import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/generator/generated_names.dart';

void main() {
  final source = Source('0123456789', name: 'schema.graphql');
  final first = SourceSpan(source, 0, 3);
  final second = SourceSpan(source, 5, 8);

  test('a name declared twice is a GQL507 at the second, related to the first', () {
    final names = GeneratedNames()
      ..register('RoleKnown', "the enum 'Role'", first)
      ..register('RoleKnown', "the input object 'RoleKnown'", second);
    expect(names.diagnostics, [
      Diagnostic(
        .generatedNameCollision,
        .error,
        "The generated name 'RoleKnown' is declared twice: by the enum 'Role' "
        "and by the input object 'RoleKnown'.",
        span: second,
        related: [first],
      ),
    ]);
  });

  test('a collision without spans has none', () {
    final names = GeneratedNames()
      ..register('A', 'the first', null)
      ..register('A', 'the second', null);
    expect(names.diagnostics.single.span, isNull);
    expect(names.diagnostics.single.related, isEmpty);
  });

  test('a reserved name is a GQL508 at its declaration', () {
    final names = GeneratedNames()..register('List', "the enum 'List'", first);
    expect(names.diagnostics, [
      Diagnostic(
        .reservedTypeName,
        .error,
        "The generated name 'List' would hide the Dart type 'List' the "
        'generated code uses.',
        span: first,
      ),
    ]);
  });

  test('a dart:core type a scalar is mapped to is reserved', () {
    final names = GeneratedNames(mappedCoreTypes: ['Rational'])
      ..register('Rational', "the enum 'Rational'", null);
    expect(names.diagnostics.single.code, DiagnosticCode.reservedTypeName);
  });

  test('distinct ordinary names are fine', () {
    final names = GeneratedNames()
      ..register('Role', "the enum 'Role'", first)
      ..register('Other', "the enum 'Other'", second);
    expect(names.diagnostics, isEmpty);
  });

  group('registerSchemaType', () {
    List<String> problems(String sdl) {
      final schema = (const SchemaBuilder().fromSdl(
        const Parser().parse(Source(sdl)).requireDocument(),
      ) as BuildSuccess).schema;
      final names = GeneratedNames();
      schema.types.forEach(names.registerSchemaType);
      return [for (final d in names.diagnostics) d.message];
    }

    test('an enum declares its known and unknown classes', () {
      expect(
        problems('''
enum Role { A }
input RoleKnown { a: Int }
type Query { a: Int }
'''),
        [
          "The generated name 'RoleKnown' is declared twice: by the enum "
              "'Role' and by the input object 'RoleKnown'.",
        ],
      );
    });

    test('a oneOf input declares a class per field', () {
      expect(
        problems('''
input Pick @oneOf { id: ID, name: String }
input PickId { a: Int }
type Query { a: Int }
'''),
        [
          "The generated name 'PickId' is declared twice: by the input object "
              "'Pick' and by the input object 'PickId'.",
        ],
      );
    });
  });
}
