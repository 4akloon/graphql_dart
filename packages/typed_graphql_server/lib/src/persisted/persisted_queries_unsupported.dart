import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_handler.dart';
import '../server/document_request.dart';
import '../server/document_result.dart';
import '../server/pipeline_errors.dart';
import '../server/server_extension.dart';
import 'persisted_query_reader.dart';
import 'persisted_query_reference.dart';

/// The document-phase step of a server that keeps neither persisted queries
/// nor trusted documents: a hash without a text is `GQL412`, whose message
/// tells Apollo clients to stop sending hashes; with a text the extension
/// is ignored.
@internal
final class PersistedQueriesUnsupported<C> extends ServerExtension<C> {
  /// Creates the step, refusing through [errors].
  const PersistedQueriesUnsupported(this.errors);

  /// Makes the error.
  final PipelineErrors errors;

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    final text = request.text;
    final reference = const PersistedQueryReader().read(
      request.request.params.extensions,
    );
    if (reference is PersistedQueryHash && (text == null || text.isEmpty)) {
      return DocumentRejected([
        errors.coded(
          DiagnosticCode.persistedQueryNotSupported,
          'PersistedQueryNotSupported',
        ),
      ]);
    }
    return next(request);
  }
}
