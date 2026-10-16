/// One piece of per-request information that links read and write, such as
/// extra headers or the HTTP status of the answer.
///
/// A link that needs its own information defines a class that extends this
/// one and reads it with `LinkContext.entry`.
///
/// {@category link}
abstract class ContextEntry {
  /// Creates an entry.
  const ContextEntry();
}
