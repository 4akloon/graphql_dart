import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// An extension whose three hooks are given as functions; a missing one calls
/// `next`.
final class HookExtension extends ServerExtension<Ctx> {
  const HookExtension({this.request, this.document, this.execute});

  final Future<ServerResponse> Function(ServerRequest, RequestHandler)? request;
  final Future<DocumentResult> Function(DocumentRequest, DocumentHandler)?
  document;
  final Future<ServerResponse> Function(
    ExecutionRequest<Ctx>,
    ExecutionHandler<Ctx>,
  )?
  execute;

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) => (this.request ?? super.onRequest)(request, next);

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) => (document ?? super.onDocument)(request, next);

  @override
  Future<ServerResponse> onExecute(
    ExecutionRequest<Ctx> request,
    ExecutionHandler<Ctx> next,
  ) => (execute ?? super.onExecute)(request, next);
}
