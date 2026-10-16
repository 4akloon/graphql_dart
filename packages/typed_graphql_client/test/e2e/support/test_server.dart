import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'test_schema.dart';
import 'tick_source.dart';

/// Builds the M6 server the end-to-end tests talk to.
final class TestServer {
  /// Creates the description.
  const TestServer();

  /// A server over [TestSchema] with the production profile; its context is
  /// not used, so it is null.
  GraphQLServer<Object?> build({
    PersistedQueryStore? persistedQueries,
    TrustedDocuments? trustedDocuments,
    TickSource? ticks,
  }) => GraphQLServer<Object?>(
    schema: const TestSchema().build(ticks: ticks),
    contextFactory: (request) => null,
    persistedQueries: persistedQueries,
    trustedDocuments: trustedDocuments,
  );
}
