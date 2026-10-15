import 'package:meta/meta.dart';

/// What `extensions.persistedQuery` of a request says (Apollo's shape,
/// `{"version": 1, "sha256Hash": "<64 lower-case hex digits>"}`).
@internal
sealed class PersistedQueryReference {
  const PersistedQueryReference();
}

/// The request names no persisted query.
@internal
final class NoPersistedQuery extends PersistedQueryReference {
  /// Creates the reference.
  const NoPersistedQuery();
}

/// The request names the persisted query [hash].
@internal
final class PersistedQueryHash extends PersistedQueryReference {
  /// Creates the reference to [hash].
  const PersistedQueryHash(this.hash);

  /// The lower-case hex SHA-256 the request names.
  final String hash;
}

/// The extension is malformed; [reason] says how (`GQL413`).
@internal
final class InvalidPersistedQuery extends PersistedQueryReference {
  /// Creates the reference with [reason].
  const InvalidPersistedQuery(this.reason);

  /// What is wrong, a clause for the message.
  final String reason;
}
