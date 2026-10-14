import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/build_report.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/src/schema/build/unique_definitions.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  test('keeps the first of two types with one name', () {
    final built = Built('''
type A { a: Int }
enum A { B }''');
    expect(built.errors, [
      '2:6 GQL101 There can be only one type named "A".',
    ]);
    expect(built.partial.types.single, isA<ObjectType>());
  });

  test('points a repeated type at the definition it repeats', () {
    final built = Built('scalar A scalar A');
    final related = built.result.diagnostics.single.related.single;
    expect(related.text, 'scalar A');
    expect(related.start, 0);
  });

  test('reports each repeat of a type name, related to the first', () {
    final built = Built('scalar A scalar A scalar A');
    expect(built.errors, hasLength(2));
    expect(
      built.result.diagnostics.map(
        (diagnostic) => diagnostic.related.single.start,
      ),
      [0, 0],
    );
  });

  test('points a repeated directive at the definition it repeats', () {
    final built = Built('directive @d on FIELD directive @d on FIELD');
    final related = built.result.diagnostics.single.related.single;
    expect(related.text, 'directive @d on FIELD');
    expect(related.start, 0);
  });

  test('keeps the first of two directives with one name', () {
    final built = Built('''
directive @key on OBJECT
directive @key(fields: String) on FIELD''');
    expect(built.errors, [
      '2:12 GQL102 There can be only one directive named "@key".',
    ]);
    expect(built.partial.directives.single.arguments, isEmpty);
  });

  test('rejects a redefined built-in scalar', () {
    final built = Built('''
scalar String
type Int { a: Int }''');
    expect(built.errors, [
      '1:8 GQL103 The built-in type "String" cannot be redefined.',
      '2:6 GQL103 The built-in type "Int" cannot be redefined.',
    ]);
    expect(built.partial.types, isEmpty);
  });

  test('rejects a redefined introspection type', () {
    expect(Built('type __Type { a: Int }').errors, [
      '1:6 GQL103 The built-in type "__Type" cannot be redefined.',
    ]);
  });

  test('rejects a redefined built-in directive', () {
    expect(Built('directive @skip(if: Boolean!) on FIELD').errors, [
      '1:12 GQL103 The built-in directive "@skip" cannot be redefined.',
    ]);
  });

  test('rejects a redefined @defer only when the builder includes it', () {
    const sdl = 'directive @defer on FIELD';
    expect(Built(sdl).schema.directives.single.name, 'defer');
    const builder = SchemaBuilder(includesDeferAndStream: true);
    expect(Built(sdl, builder: builder).errors, [
      '1:12 GQL103 The built-in directive "@defer" cannot be redefined.',
    ]);
  });

  test('reports problems of different definitions in document order', () {
    final built = Built('''
scalar A
directive @d on FIELD
directive @d on FIELD
scalar A''');
    expect(built.errors.map((error) => error.split(' ')[1]), [
      'GQL102',
      'GQL101',
    ]);
  });

  group('onto a schema', () {
    final base = Schema(
      types: [ScalarType('Date')],
      directives: [SchemaDirective('key')],
    );

    /// The messages of checking the definitions of [text] against [base].
    List<String> check(String text) {
      final sdl = Sdl(text);
      final report = BuildReport(NodeSpans(sdl.source));
      UniqueDefinitions(report, base)
        ..types(sdl.all())
        ..directives(sdl.all());
      return [
        for (final diagnostic in report.diagnostics())
          '${diagnostic.code.id} ${diagnostic.message}',
      ];
    }

    test('rejects a type the schema has', () {
      expect(check('scalar Date'), [
        'GQL101 Type "Date" already exists in the schema. It cannot also be '
            'defined in this type definition.',
      ]);
    });

    test('reports a built-in before a type the schema has', () {
      final withInt = Schema(types: [ScalarType('Int')]);
      final sdl = Sdl('scalar Int');
      final report = BuildReport(NodeSpans(sdl.source));
      UniqueDefinitions(report, withInt).types(sdl.all());
      expect(
        report.diagnostics().single.code,
        DiagnosticCode.builtInRedefinition,
      );
    });

    test('reports a built-in before a directive the schema has', () {
      final withSkip = Schema(directives: [SchemaDirective('skip')]);
      final sdl = Sdl('directive @skip on FIELD');
      final report = BuildReport(NodeSpans(sdl.source));
      UniqueDefinitions(report, withSkip).directives(sdl.all());
      expect(
        report.diagnostics().single.code,
        DiagnosticCode.builtInRedefinition,
      );
    });

    test('reports each repeat of a type the schema has', () {
      expect(check('scalar Date scalar Date'), hasLength(2));
    });

    test('rejects a directive the schema has', () {
      expect(check('directive @key on FIELD'), [
        'GQL102 Directive "@key" already exists in the schema. It cannot be '
            'redefined.',
      ]);
    });
  });
}
