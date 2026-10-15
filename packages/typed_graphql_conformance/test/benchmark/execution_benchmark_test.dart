@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../benchmark/execution_benchmark.dart';

void main() {
  const benchmark = ExecutionBenchmark();

  for (final scenario in benchmark.scenarios()) {
    test('${scenario.name} runs once without errors', () async {
      final payload = await scenario.run();
      expect(payload.errors, isEmpty);
      expect(payload, isA<ExecutionResult>());
    });
  }
}
