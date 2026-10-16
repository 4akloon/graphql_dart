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

  /// The last entry that is a [T], or null when there is none.
  T? entry<T extends ContextEntry>() {
    for (final entry in entries.reversed) {
      if (entry is T) {
        return entry;
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
