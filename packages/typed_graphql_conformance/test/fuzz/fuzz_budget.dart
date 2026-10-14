import 'dart:io';
import 'dart:math';

/// How much a fuzzer runs (R10.4): a fixed count in CI, more on demand.
///
/// `TYPED_GRAPHQL_FUZZ_ITERATIONS` raises [iterations] and
/// `TYPED_GRAPHQL_FUZZ_SEED` changes [seed]. Iteration `i` draws from
/// `Random(seed + i)`, so a failure names the one iteration to replay.
final class FuzzBudget {
  /// A budget of [defaultIterations] unless the environment says more.
  FuzzBudget({required int defaultIterations})
    : iterations = _read('TYPED_GRAPHQL_FUZZ_ITERATIONS') ?? defaultIterations,
      seed = _read('TYPED_GRAPHQL_FUZZ_SEED') ?? defaultSeed;

  /// The seed CI uses.
  static const int defaultSeed = 20261014;

  /// How many cases to run.
  final int iterations;

  /// The seed of the first case.
  final int seed;

  /// The random source of case [index].
  Random randomFor(int index) => Random(seed + index);

  /// How to replay case [index], for a failure message.
  String replay(int index) =>
      'case $index of seed $seed: Random(${seed + index})';

  static int? _read(String name) => switch (Platform.environment[name]) {
    final text? => int.tryParse(text),
    null => null,
  };
}
