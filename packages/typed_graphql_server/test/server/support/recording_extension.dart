import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// Writes `name:phase` when a hook is entered and `/name:phase` when it
/// returns, into a shared log.
final class RecordingExtension extends ServerExtension<Ctx> {
  const RecordingExtension(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) async {
    log.add('$name:request');
    final response = await next(request);
    log.add('/$name:request');
    return response;
  }

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    log.add('$name:document');
    final result = await next(request);
    log.add('/$name:document');
    return result;
  }

  @override
  Future<ServerResponse> onExecute(
    ExecutionRequest<Ctx> request,
    ExecutionHandler<Ctx> next,
  ) async {
    log.add('$name:execute');
    final response = await next(request);
    log.add('/$name:execute');
    return response;
  }
}
