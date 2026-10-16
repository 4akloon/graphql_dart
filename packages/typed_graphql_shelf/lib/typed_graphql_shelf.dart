/// The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket
/// handlers for shelf, with an optional GraphiQL page in development.
///
/// Under construction: `GraphQLShelfHandler` serves GraphQL over HTTP (queries,
/// mutations, batching, uploads, server-sent events and the GraphiQL page of
/// `ServerProfile.development`, as configured by `HttpOptions`) and, with
/// `webSocket` set, graphql-ws over WebSocket; `TempFileUploadStorage` keeps
/// multipart uploads in temporary files. See the package README.
library;

export 'src/graphql_shelf_handler.dart';
export 'src/temp_file_upload_storage.dart';
