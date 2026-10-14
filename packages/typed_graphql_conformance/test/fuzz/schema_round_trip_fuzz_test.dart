@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'random_parts.dart';
import 'random_schema.dart';
import 'schema_dump.dart';

/// R10.4 and spec §11 of M3, property 1: a random schema, printed as SDL
/// and built again, holds the same elements, and prints the same text.
void main() {
  final budget = FuzzBudget(defaultIterations: 500);
  const parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true, maxTokens: null),
  );
  const printer = SchemaPrinter();
  const dump = SchemaDump();

  Schema rebuilt(String text, String reason) {
    final source = Source(text);
    final document = switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
    };
    return switch (const SchemaBuilder().fromSdl(document, source: source)) {
      BuildSuccess(:final schema) => schema,
      BuildFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
    };
  }

  test('print then build gives the same schema and the same text', () {
    for (var index = 0; index < budget.iterations; index++) {
      final schema = RandomSchema(
        RandomParts(budget.randomFor(index)),
      ).schema();
      final text = printer.print(schema);
      final reason = '${budget.replay(index)}\n$text';
      // An empty document is a syntax error (spec §2.2), so an empty
      // schema is checked to be one instead.
      if (text.isEmpty) {
        expect(dump.of(schema), dump.of(Schema()), reason: reason);
        continue;
      }
      final built = rebuilt(text, reason);
      expect(dump.of(built), dump.of(schema), reason: reason);
      expect(printer.print(built), text, reason: reason);
    }
  });

  test('the generator makes every kind of schema element', () {
    final kinds = <String>{};
    for (var index = 0; index < 200; index++) {
      final parts = RandomParts(Random(FuzzBudget.defaultSeed + index));
      final schema = RandomSchema(parts).schema();
      kinds.addAll([
        for (final type in schema.types) '${type.runtimeType}',
        if (schema.directives.isNotEmpty) 'directive',
        if (schema.typeNamed('Query') != null) 'Query',
        if (schema.queryTypeName != null) 'query root',
        if (schema.mutationTypeName != null) 'mutation root',
        if (schema.description != null) 'schema description',
        if (schema.appliedDirectives.isNotEmpty) 'schema directive',
        for (final line in dump.of(schema))
          if (line.contains(' = ') && !line.endsWith('= none')) 'default value',
      ]);
    }
    expect(kinds, {
      'ScalarType',
      'ObjectType',
      'InterfaceType',
      'UnionType',
      'EnumType',
      'InputObjectType',
      'directive',
      'Query',
      'query root',
      'mutation root',
      'schema description',
      'schema directive',
      'default value',
    });
  });
}
