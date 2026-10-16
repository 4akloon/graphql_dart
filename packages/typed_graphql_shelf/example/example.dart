import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

/// Serves a small schema at `http://localhost:8080/` (or the port in `PORT`):
/// queries and mutations over HTTP, a `ticks` subscription over graphql-ws or
/// server-sent events, and the GraphiQL page for a browser that opens the
/// address.
Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('hello', b.string).pure((_) => 'Hello from shelf!'),
    ],
  );
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      t
          .field('ticks', b.int)
          .subscribeWith<int>(
            (parent, args, context, info) =>
                Stream.periodic(const Duration(seconds: 1), (count) => count),
            (event, args, context, info) => event,
          ),
    ],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query, subscription: subscription),
    contextFactory: (request) => null,
    // The development profile also switches the GraphiQL page on.
    profile: ServerProfile.development,
  );
  final handler = GraphQLShelfHandler<Object?>(
    server,
    webSocket: const GraphQLWsOptions(),
  );

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final httpServer = await shelf_io.serve(
    handler.call,
    InternetAddress.loopbackIPv4,
    port,
  );
  stdout.writeln('GraphQL on http://localhost:${httpServer.port}/');
}
