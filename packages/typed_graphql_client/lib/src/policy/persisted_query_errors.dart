import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_result.dart';

/// Reads the two answers of a server that stores persisted queries: "I do
/// not know this hash" and "I do not store queries" (M6 section 11).
///
/// A server says either with a message (the Apollo convention) or with an
/// `extensions.code`: `GQL410` and `GQL412` for this repository's server.
final class const PersistedQueryErrors() {
  /// Creates the reader.
  this;

  /// Whether [result] says the hash is unknown, so the text must follow.
  bool isNotFound(LinkResult result) => _says(
    result,
    'PersistedQueryNotFound',
    const {'GQL410', 'PERSISTED_QUERY_NOT_FOUND'},
  );

  /// Whether [result] says the server stores no queries, so the text must
  /// be sent every time.
  bool isNotSupported(LinkResult result) => _says(
    result,
    'PersistedQueryNotSupported',
    const {'GQL412', 'PERSISTED_QUERY_NOT_SUPPORTED'},
  );

  bool _says(LinkResult result, String message, Set<String> codes) {
    if (result is! LinkPayload) {
      return false;
    }
    return result.payload.errors.any(
      (error) =>
          error.message == message ||
          switch (error.extensions?['code']) {
            JsonString(:final value) => codes.contains(value),
            _ => false,
          },
    );
  }
}
