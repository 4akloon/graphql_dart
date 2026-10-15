import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A store that reads nothing and fails when written, as a shared store does
/// when its backend rejects the write.
final class WriteFailingStore implements PersistedQueryStore {
  const WriteFailingStore();

  @override
  FutureOr<String?> read(String hash) => null;

  @override
  FutureOr<void> write(String hash, String text) =>
      throw StateError('store is down');
}

/// A store whose every call fails, as a broken shared store would.
final class FailingStore implements PersistedQueryStore {
  const FailingStore();

  @override
  FutureOr<String?> read(String hash) => throw StateError('store is down');

  @override
  FutureOr<void> write(String hash, String text) =>
      throw StateError('store is down');
}
