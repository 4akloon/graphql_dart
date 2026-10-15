import 'server_request.dart';
import 'server_response.dart';

/// The rest of the request phase, as an extension's `onRequest` sees it.
///
/// {@category server}
typedef RequestHandler = Future<ServerResponse> Function(ServerRequest request);
