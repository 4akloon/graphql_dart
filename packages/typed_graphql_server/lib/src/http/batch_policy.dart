/// How a `GraphQLHttpHandler` runs a JSON array of requests, which it refuses
/// unless `HttpOptions.batching` holds a policy (R5.12).
///
/// Batching is off by default because one HTTP request then carries many
/// operations, which defeats the per-request limits a proxy or a rate limiter
/// applies (R5.15). A host turns it on for clients that batch to save round
/// trips, such as Apollo's `BatchHttpLink`. Items run one after the other, in
/// order, each through the whole pipeline; they share one cost budget, so the
/// server's `maxCost` bounds the batch, not each item.
///
/// {@category http}
final class BatchPolicy {
  /// Creates a policy that accepts batches of at most [maxRequests] items.
  const BatchPolicy({this.maxRequests = 10, this.allowsMutations = false});

  /// The most items a batch may hold; a longer one, or an empty one, is
  /// refused with `422` (`GQL429`). Must be at least one.
  final int maxRequests;

  /// Whether an item may be a mutation; when it may not, the item's slot
  /// holds a `GQL431` error and the other items still run.
  final bool allowsMutations;
}
