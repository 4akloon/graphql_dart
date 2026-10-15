import 'package:meta/meta.dart';

import 'document_handler.dart';
import 'execution_handler.dart';
import 'request_handler.dart';
import 'server_extension.dart';

/// Composes the hooks of an ordered list of extensions around a core step,
/// once per phase when the server is built: the first extension is the
/// outermost.
@internal
final class ExtensionChain<C> {
  /// Creates the chain over [extensions].
  const ExtensionChain(this.extensions);

  /// The extensions, outermost first.
  final List<ServerExtension<C>> extensions;

  /// [core] wrapped in every `onRequest`.
  RequestHandler request(RequestHandler core) {
    var next = core;
    for (final extension in extensions.reversed) {
      final inner = next;
      next = (request) => extension.onRequest(request, inner);
    }
    return next;
  }

  /// [core] wrapped in every `onDocument`.
  DocumentHandler document(DocumentHandler core) {
    var next = core;
    for (final extension in extensions.reversed) {
      final inner = next;
      next = (request) => extension.onDocument(request, inner);
    }
    return next;
  }

  /// [core] wrapped in every `onExecute`.
  ExecutionHandler<C> execution(ExecutionHandler<C> core) {
    var next = core;
    for (final extension in extensions.reversed) {
      final inner = next;
      next = (request) => extension.onExecute(request, inner);
    }
    return next;
  }
}
