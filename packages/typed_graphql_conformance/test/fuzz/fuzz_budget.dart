import 'dart:io';
import 'dart:math';

/// How much a fuzzer runs (R10.4): a fixed count in CI, more on demand.
///
/// `TYPED_GRAPHQL_FUZZ_ITERATIONS` raises [iterations] and
/// `TYPED_GRAPHQL_FUZZ_SEED` changes [seed]. Iteration `i` draws from
/// `Random(seed + i)`, so a failure names the one iteration to replay.
final class FuzzBudget {
  /// A budget of [defaultIterations] unless [environment] (the process
  /// environment by default) says more; a variable that is set but is not
  /// a positive integer is an [ArgumentError].
  FuzzBudget({
    required int defaultIterations,
    Map<String, String>? environment,
  }) : iterations =
           _read(
             environment ?? Platform.environment,
             'TYPED_GRAPHQL_FUZZ_ITERATIONS',
           ) ??
           defaultIterations,
       seed =
           _read(
             environment ?? Platform.environment,
             'TYPED_GRAPHQL_FUZZ_SEED',
           ) ??
           defaultSeed;

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

  static int? _read(Map<String, String> environment, String name) {
    final text = environment[name];
    if (text == null) {
      return null;
    }
    final value = int.tryParse(text);
    if (value == null || value <= 0) {
      throw ArgumentError.value(text, name, 'must be a positive integer');
    }
    return value;
  }
}
