import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A store whose every call fails, as a broken shared store would.
final class FailingStore implements PersistedQueryStore {
  const FailingStore();

  @override
  FutureOr<String?> read(String hash) => throw StateError('store is down');

  @override
  FutureOr<void> write(String hash, String text) =>
      throw StateError('store is down');
}
