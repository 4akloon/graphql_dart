@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'random_parts.dart';
import 'random_schema.dart';

/// R10.4 and spec §11 of M3 for schema coordinates: the coordinate of
/// every element of a random schema resolves to that element, and hostile
/// coordinate text never throws, ends, and gives at most `maxErrors + 1`
/// diagnostics; what parses resolves without throwing.
void main() {
  final budget = FuzzBudget(defaultIterations: 500);
  const parser = Parser();
  const limit = DiagnosticSink.defaultMaxErrors + 1;

  /// Every element of [schema] that has a coordinate, with its text.
  List<(String, CoordinateTarget)> elementsOf(Schema schema) => [
    for (final type in schema.types) ...[
      (type.name, TypeTarget(type)),
      ...switch (type) {
        ObjectType(:final fields) || InterfaceType(:final fields) => [
          for (final field in fields) ...[
            ('${type.name}.${field.name}', FieldTarget(type, field)),
            for (final argument in field.arguments)
              (
                '${type.name}.${field.name}(${argument.name}:)',
                ArgumentTarget(type, field, argument),
              ),
          ],
        ],
        InputObjectType(:final fields) => [
          for (final field in fields)
            ('${type.name}.${field.name}', InputFieldTarget(type, field)),
        ],
        EnumType(:final values) => [
          for (final value in values)
            ('${type.name}.${value.name}', EnumValueTarget(type, value)),
        ],
        ScalarType() || UnionType() => const <(String, CoordinateTarget)>[],
      },
    ],
    for (final directive in schema.directives) ...[
      ('@${directive.name}', DirectiveTarget(directive)),
      for (final argument in directive.arguments)
        (
          '@${directive.name}(${argument.name}:)',
          DirectiveArgumentTarget(directive, argument),
        ),
    ],
  ];

  /// The coordinate [text] parsed and resolved; null when it does not
  /// parse. The diagnostics are checked to be bounded.
  CoordinateTarget? resolve(Schema schema, String text, String reason) {
    final result = parser.parseSchemaCoordinate(Source(text));
    expect(result.diagnostics.length, lessThanOrEqualTo(limit), reason: reason);
    return switch (result) {
      ParseElementSuccess(:final value) => schema.resolve(value),
      ParseElementFailure() => null,
    };
  }

  /// Text made of coordinate punctuation, names of [schema] and debris.
  String hostileText(Random random, Schema schema) {
    final names = [
      for (final (text, _) in elementsOf(schema))
        ...text.split(RegExp('[.@():]')),
      '__typename',
      '__Type',
      'String',
      'deprecated',
    ].where((name) => name.isNotEmpty).toList();
    const debris = ['.', '(', ')', ':', '@', ' ', '#', r'$', '\uD800', '1'];
    return List.generate(random.nextInt(8), (_) {
      if (random.nextBool() && names.isNotEmpty) {
        return names[random.nextInt(names.length)];
      }
      return debris[random.nextInt(debris.length)];
    }).join();
  }

  Schema schemaFor(int index) =>
      RandomSchema(RandomParts(budget.randomFor(index))).schema();

  test('the coordinate of every element resolves to it', () {
    var count = 0;
    for (var index = 0; index < budget.iterations; index++) {
      final schema = schemaFor(index);
      for (final (text, target) in elementsOf(schema)) {
        final reason = '${budget.replay(index)}: $text';
        expect(resolve(schema, text, reason), target, reason: reason);
        count++;
      }
    }
    expect(count, greaterThan(budget.iterations));
  });

  test('hostile text never throws and reaches every outcome', () {
    final outcomes = {'parse failure': 0, 'null': 0, 'element': 0};
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final schema = schemaFor(index);
      final text = hostileText(random, schema);
      final reason = '${budget.replay(index)}: $text ${text.codeUnits}';
      final parsed = parser.parseSchemaCoordinate(Source(text));
      final outcome = switch (resolve(schema, text, reason)) {
        _ when parsed is ParseElementFailure => 'parse failure',
        null => 'null',
        _ => 'element',
      };
      outcomes[outcome] = outcomes[outcome]! + 1;
    }
    if (budget.iterations >= 200) {
      expect(
        outcomes.values,
        everyElement(greaterThan(0)),
        reason: '$outcomes',
      );
    }
  });

  // A coordinate is one element: the parser stops at the first problem
  // instead of recovering, so a long text costs one diagnostic.
  test('a long hostile text gives one diagnostic', () {
    final result = parser.parseSchemaCoordinate(Source('#' * 100000));
    expect(result.diagnostics, hasLength(1));
  });
}
