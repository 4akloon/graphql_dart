import 'document_handler.dart';
import 'document_request.dart';
import 'document_result.dart';
import 'execution_handler.dart';
import 'execution_request.dart';
import 'request_handler.dart';
import 'server_request.dart';
import 'server_response.dart';

/// A hook into the three phases of a request: the whole request, resolving
/// the document, and the execution (R5.3).
///
/// Each hook has a default that calls `next`. An extension may refuse by
/// returning without calling `next`, rewrite the value it passes on, or look
/// at what comes back. In `GraphQLServer.extensions` the first extension is
/// the outermost, so its hooks see every request, refused ones included.
///
/// {@category server}
abstract class ServerExtension<C> {
  /// Creates the extension.
  const ServerExtension();

  /// Wraps the whole request: CSRF prevention and the document phase are
  /// inside.
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) => next(request);

  /// Wraps the resolving of the document text to a validated document.
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) => next(request);

  /// Wraps the execution, which has the context and the options.
  ///
  /// The method check and the cost limit judged the request as it reached
  /// this phase: a hook that rewrites the request's operation name or
  /// variables is server code, trusted to keep within the limits.
  Future<ServerResponse> onExecute(
    ExecutionRequest<C> request,
    ExecutionHandler<C> next,
  ) => next(request);
}
