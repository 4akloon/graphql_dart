@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'introspection_mutator.dart';
import 'introspection_view.dart';
import 'random_parts.dart';
import 'random_schema.dart';

/// R10.4 and spec §11 of M3, property 2 for introspection JSON: a broken
/// introspection result never makes `fromIntrospection` throw, ends, and
/// gives at most `maxErrors + 1` diagnostics, each a `GQL150`-`GQL155`
/// whose message starts with a JSON path (or the limit's `GQL000`); the
/// partial schema it gives validates without throwing.
void main() {
  final budget = FuzzBudget(defaultIterations: 500);
  const view = IntrospectionView();
  const limit = DiagnosticSink.defaultMaxErrors + 1;
  final introspectionCodes = {
    for (var id = 150; id <= 155; id++) 'GQL$id',
    DiagnosticCode.diagnosticLimitReached.id,
  };

  /// A result of a random schema, as plain objects to break.
  Map<String, Object?> resultFor(int index) {
    final parts = RandomParts(budget.randomFor(index));
    return view.closed(RandomSchema(parts).schema()).toIntrospection().toJson();
  }

  /// The codes of building [json], each diagnostic checked to be bounded,
  /// of the introspection family and led by a path; the partial schema is
  /// validated too.
  List<String> buildChecked(Object? json, String reason) {
    final value = switch (const JsonReader().read(json)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure() => fail('not JSON: $reason'),
    };
    final result = const SchemaBuilder().fromIntrospection(value);
    expect(result.diagnostics.length, lessThanOrEqualTo(limit), reason: reason);
    for (final diagnostic in result.diagnostics) {
      expect(introspectionCodes, contains(diagnostic.code.id), reason: reason);
      if (diagnostic.code != DiagnosticCode.diagnosticLimitReached) {
        expect(diagnostic.message, startsWith(r'$'), reason: reason);
      }
    }
    final schema = switch (result) {
      BuildSuccess(:final schema) => schema,
      BuildFailure(:final partial) => partial,
    };
    final validation = const SchemaValidator().validate(schema);
    expect(
      validation.diagnostics.length,
      lessThanOrEqualTo(limit),
      reason: reason,
    );
    return [for (final diagnostic in result.diagnostics) diagnostic.code.id];
  }

  test('broken results never throw and reach every introspection code', () {
    final codes = <String>{};
    final expected = [for (var id = 150; id <= 155; id++) 'GQL$id'];
    // Past the budget, with any seed, until every code was reached or the
    // extra iterations are spent: coverage must not depend on the seed.
    final extra = budget.iterations >= 200 ? 3000 : 0;
    for (var index = 0; index < budget.iterations + extra; index++) {
      if (index >= budget.iterations && codes.containsAll(expected)) {
        break;
      }
      final json = resultFor(index);
      IntrospectionMutator(budget.randomFor(index)).mutate(json);
      codes.addAll(buildChecked(json, budget.replay(index)));
    }
    // A handful of iterations cannot be expected to break every way.
    if (budget.iterations >= 200) {
      expect(codes, containsAll(expected));
    }
  });

  test('unbroken results build without diagnostics', () {
    for (var index = 0; index < 50; index++) {
      expect(buildChecked(resultFor(index), budget.replay(index)), isEmpty);
    }
  });

  test('many broken types reach the sink limit and stop there', () {
    final json = {
      '__schema': {
        'types': [
          for (var index = 0; index < 300; index++) {'name': 'T$index'},
        ],
      },
    };
    final codes = buildChecked(json, 'kinds missing');
    expect(codes, hasLength(limit));
    expect(codes.last, DiagnosticCode.diagnosticLimitReached.id);
  });

  // The reader once copied the JSON path per `ofType` level, which made a
  // long chain quadratic in memory (22 GB at 100000 levels); it keeps
  // parents now, so the chain is linear.
  test('a long ofType chain builds in linear memory', () {
    final scalar = JsonObject({
      'kind': const JsonString('SCALAR'),
      'name': const JsonString('String'),
    });
    JsonValue reference = scalar;
    for (var level = 0; level < 20000; level++) {
      reference = JsonObject({
        'kind': const JsonString('NON_NULL'),
        'ofType': JsonObject({
          'kind': const JsonString('LIST'),
          'ofType': reference,
        }),
      });
    }
    final result = const SchemaBuilder().fromIntrospection(
      JsonObject({
        '__schema': JsonObject({
          'queryType': JsonObject({'name': const JsonString('Query')}),
          'types': JsonArray([
            JsonObject({
              'kind': const JsonString('OBJECT'),
              'name': const JsonString('Query'),
              'interfaces': JsonArray(const []),
              'fields': JsonArray([
                JsonObject({
                  'name': const JsonString('a'),
                  'args': JsonArray(const []),
                  'type': reference,
                }),
              ]),
            }),
            scalar,
          ]),
        }),
      }),
    );
    // Deeper than any query can ask for (GQL155), reported at once.
    expect(result.diagnostics.map((d) => d.code.id), ['GQL155']);
  });
}
