import '../link/context_entry.dart';

/// Marks a mutation as safe to send again, so that `RetryLink` retries it
/// (R8.4).
///
/// Put it in the context of the call: a mutation without it is sent once,
/// because a lost answer does not say whether the server applied it.
///
/// {@category policy}
final class const Idempotent() extends ContextEntry {
  /// Creates the marker.
  this;

  @override
  String toString() => 'Idempotent()';
}
