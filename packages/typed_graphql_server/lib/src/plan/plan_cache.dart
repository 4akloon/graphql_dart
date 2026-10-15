import 'package:typed_graphql/typed_graphql.dart';

import 'lru_map.dart';
import 'operation_plan.dart';

/// The plans of an `ExecutableSchema`, at most [capacity] of them, least
/// recently used first out (R4.8). A plan is found by the identity of its
/// [Document] (syntax nodes compare by identity), the operation name and
/// whether messages carry suggestions (a plan holds constant-argument
/// problems, whose text depends on it).
final class PlanCache(
  /// The most plans kept (`planCacheSize`).
  final int capacity,
) {
  /// Creates an empty cache.
  this : _plans = LruMap(capacity);

  final LruMap<(Document, String?, bool), OperationPlan> _plans;
  int _hits = 0;
  int _misses = 0;

  /// How many lookups found a plan.
  int get hitCount => _hits;

  /// How many lookups found none.
  int get missCount => _misses;

  /// The number of plans held.
  int get length => _plans.length;

  /// The plan of [operationName] in [document], or null.
  OperationPlan? lookup(
    Document document,
    String? operationName, {
    required bool includesSuggestions,
  }) {
    final plan = _plans.use((document, operationName, includesSuggestions));
    if (plan == null) {
      _misses++;
    } else {
      _hits++;
    }
    return plan;
  }

  /// Keeps [plan] for [operationName] in [document].
  void store(
    Document document,
    String? operationName,
    OperationPlan plan, {
    required bool includesSuggestions,
  }) {
    _plans.store((document, operationName, includesSuggestions), plan);
  }
}
