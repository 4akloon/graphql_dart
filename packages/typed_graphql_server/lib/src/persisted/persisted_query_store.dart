import 'dart:async';

/// Where a server keeps the texts of automatic persisted queries, by the
/// lower-case hex SHA-256 of each text (R5.4).
///
/// The server writes a text only after verifying that the hash is the
/// SHA-256 of the text and after the text parsed and validated, and checks
/// the hash again when it reads, so a store shared with other processes
/// cannot make a hash name another text. An error a store throws is an
/// unexpected error of the request (`GQL330`), never a silent miss.
/// [MemoryPersistedQueryStore] keeps them in memory; a store backed by a
/// shared cache implements this interface.
///
/// {@category persisted}
abstract interface class PersistedQueryStore {
  /// The text stored for [hash], or null when there is none.
  FutureOr<String?> read(String hash);

  /// Stores [text] for [hash].
  FutureOr<void> write(String hash, String text);
}
