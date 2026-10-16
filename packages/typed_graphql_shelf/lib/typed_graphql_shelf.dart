/// The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket
/// handlers for shelf, with an optional GraphiQL page in development.
///
/// Under construction: `GraphQLShelfHandler` serves GraphQL over HTTP (queries,
/// mutations, batching, uploads, server-sent events and the GraphiQL page of
/// `ServerProfile.development`, as configured by `HttpOptions`) and, with
/// `webSocket` set, graphql-ws over WebSocket. Temporary-file uploads come
/// with the rest of M7. See the package README.
library;

export 'src/graphql_shelf_handler.dart';
