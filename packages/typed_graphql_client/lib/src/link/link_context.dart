import 'context_entry.dart';

/// The per-request information that travels with a request through the
/// links and back with its result: a list of [ContextEntry] values.
///
/// It is immutable: [withEntry] gives a new context. The client's cache
/// (M12) will carry its fetch policy here too.
///
/// {@category link}
final class LinkContext {
  /// Creates a context holding [entries], copied.
  LinkContext(Iterable<ContextEntry> entries)
    : entries = List.unmodifiable(entries);

  /// The context without entries.
  const LinkContext.empty() : entries = const [];

  /// The entries, in the order they were added.
  final List<ContextEntry> entries;

  /// The last entry whose exact type is [T], or null when there is none.
  ///
  /// The rule is the one of [withEntry], so that what was added is what is
  /// read: a subclass of [T] is another kind of entry.
  T? entry<T extends ContextEntry>() {
    for (final entry in entries.reversed) {
      if (entry.runtimeType == T) {
        return entry as T;
      }
    }
    return null;
  }

  /// This context with [entry] in place of the entries of its exact type.
  LinkContext withEntry(ContextEntry entry) => LinkContext([
    for (final existing in entries)
      if (existing.runtimeType != entry.runtimeType) existing,
    entry,
  ]);

  @override
  String toString() => 'LinkContext($entries)';
}
