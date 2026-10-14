import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/build_report.dart';
import 'package:typed_graphql/src/schema/build/element_reader.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/src/schema/build/schema_definition_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../sdl.dart';

void main() {
  /// Reads the schema definitions and extensions of [text] onto [base];
  /// the errors go to [errors].
  Schema read(String text, {Schema? base, List<String>? errors}) {
    final sdl = Sdl(text);
    final report = BuildReport(NodeSpans(sdl.source));
    final schema = SchemaDefinitionReader(
      report,
      ElementReader(report.spans),
    ).read(base ?? Schema(), sdl.all<SchemaDefinition>(), sdl.all());
    errors?.addAll([
      for (final diagnostic in report.diagnostics())
        '${diagnostic.span?.location} ${diagnostic.code.id} '
            '${diagnostic.message}',
    ]);
    return schema;
  }

  test('reads the roots, description, directives and span', () {
    final schema = read('"API" schema @a { query: Q subscription: S }');
    expect(schema.queryTypeName, 'Q');
    expect(schema.mutationTypeName, isNull);
    expect(schema.subscriptionTypeName, 'S');
    expect(schema.description, 'API');
    expect(schema.appliedDirectives.single.name, 'a');
    expect(schema.span?.start, 0);
  });

  test(
    'applies the definition first, then the extensions in document order',
    () {
      final schema = read('''
extend schema @b { mutation: M }
schema @a { query: Q }''');
      expect(schema.queryTypeName, 'Q');
      expect(schema.mutationTypeName, 'M');
      expect(schema.appliedDirectives.map((directive) => directive.name), [
        'a',
        'b',
      ]);
    },
  );

  test('keeps the first of two schema definitions', () {
    final errors = <String>[];
    final schema = read('''
schema { query: A }
schema { query: B }''', errors: errors);
    expect(schema.queryTypeName, 'A');
    expect(errors, ['2:1 GQL107 Must provide only one schema definition.']);
  });

  test('keeps the first root type of an operation', () {
    final errors = <String>[];
    final schema = read('''
schema { query: A query: B }
extend schema { query: C }''', errors: errors);
    expect(schema.queryTypeName, 'A');
    expect(errors, [
      '1:19 GQL108 There can be only one query type in schema.',
      '2:17 GQL108 There can be only one query type in schema.',
    ]);
  });

  group('onto a schema with roots', () {
    final base = Schema(
      queryTypeName: 'Q',
      description: 'Old',
      appliedDirectives: [AppliedDirective('old')],
    );

    test('rejects a new schema definition', () {
      final errors = <String>[];
      final schema = read(
        'schema { mutation: M }',
        base: base,
        errors: errors,
      );
      expect(schema.mutationTypeName, isNull);
      expect(errors, [
        '1:1 GQL107 Cannot define a new schema within a schema extension.',
      ]);
    });

    test('rejects a root type it already has', () {
      final errors = <String>[];
      final schema = read(
        'extend schema { query: Other }',
        base: base,
        errors: errors,
      );
      expect(schema.queryTypeName, 'Q');
      expect(errors, [
        '1:17 GQL108 Type for query already defined in the schema. It '
            'cannot be redefined.',
      ]);
    });

    test('adds a new root type and directives after its own', () {
      final schema = read('extend schema @new { mutation: M }', base: base);
      expect(schema.queryTypeName, 'Q');
      expect(schema.mutationTypeName, 'M');
      expect(schema.description, 'Old');
      expect(schema.appliedDirectives.map((directive) => directive.name), [
        'old',
        'new',
      ]);
    });
  });

  test('accepts a schema definition onto a schema without roots', () {
    final schema = read('schema { query: Q }', base: Schema());
    expect(schema.queryTypeName, 'Q');
  });
}
