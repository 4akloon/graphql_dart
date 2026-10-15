import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

/// Cost directives that try to make the schema check quadratic (R0.3, R0.5).
void main() {
  test('a sizedFields of 20000 unknown names stops at the error limit', () {
    final fields = [for (var i = 0; i < 20000; i++) 'f$i: [Int]'].join(' ');
    final names = [for (var i = 0; i < 20000; i++) '"missing$i"'].join(', ');
    final watch = Stopwatch()..start();
    final built = Built(
      'type Query { page: Page @listSize(sizedFields: [$names]) }\n'
      'type Page { $fields }',
      builder: const SchemaBuilder(includesCostDirectives: true),
    );
    final result = const SchemaValidator().validate(built.schema);
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    final diagnostics = switch (result) {
      InvalidSchema(:final diagnostics) => diagnostics,
      ValidSchema() => fail('expected errors'),
    };
    // 100 errors and the limit.
    expect(diagnostics, hasLength(101));
    expect(diagnostics.last.code.id, 'GQL000');
  });

  test('20000 known sized names cost one set lookup each', () {
    final fields = [for (var i = 0; i < 20000; i++) 'f$i: [Int]'].join(' ');
    final names = [for (var i = 0; i < 20000; i++) '"f$i"'].join(', ');
    final watch = Stopwatch()..start();
    final built = Built(
      'type Query { page: Page @listSize(sizedFields: [$names]) }\n'
      'type Page { $fields }',
      builder: const SchemaBuilder(includesCostDirectives: true),
    );
    expect(
      const SchemaValidator().validate(built.schema),
      isA<ValidSchema>(),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
