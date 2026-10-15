import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_handler.dart';
import '../server/document_hash.dart';
import '../server/document_request.dart';
import '../server/document_result.dart';
import '../server/pipeline_errors.dart';
import '../server/server_extension.dart';
import 'persisted_query_reader.dart';
import 'persisted_query_reference.dart';
import 'trusted_documents.dart';

/// The document-phase step of trusted documents (R5.4): only a document in
/// [documents] reaches the core step.
///
/// A hash alone runs its trusted text (`GQL415` when there is none); a text
/// runs only when its SHA-256 is trusted (`GQL414`), so any change to a
/// trusted text, whitespace included, is refused. A request with no text and
/// no hash goes on to the core step, which reports `GQL400`.
@internal
final class TrustedDocumentsCheck<C> extends ServerExtension<C> {
  /// Creates the step over [documents], refusing through [errors].
  const TrustedDocumentsCheck(this.documents, this.errors);

  /// The documents the server runs.
  final TrustedDocuments documents;

  /// Makes the errors.
  final PipelineErrors errors;

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    const reader = PersistedQueryReader();
    final reference = reader.read(request.request.params.extensions);
    if (reference case final InvalidPersistedQuery invalid) {
      return DocumentRejected([reader.errorOf(invalid, errors)]);
    }
    final text = request.text;
    if (text == null || text.isEmpty) {
      return switch (reference) {
        PersistedQueryHash(:final hash) => _trusted(request, hash, next),
        _ => next(request),
      };
    }
    final textHash = const DocumentHash().of(text);
    if (reference case PersistedQueryHash(:final hash) when hash != textHash) {
      return _refused(
        DiagnosticCode.persistedQueryHashMismatch,
        'provided sha does not match query',
      );
    }
    // The manifest's own text runs, not the client's: a text with a lone
    // surrogate hashes like the same text with U+FFFD, so it can carry the
    // trusted hash without being the trusted text.
    return switch (documents.textOf(textHash)) {
      final trusted? => next(request.withText(trusted)),
      null => _refused(
        DiagnosticCode.untrustedDocument,
        'Only trusted documents are allowed.',
      ),
    };
  }

  Future<DocumentResult> _trusted(
    DocumentRequest request,
    String hash,
    DocumentHandler next,
  ) async => switch (documents.textOf(hash)) {
    final text? => await next(request.withText(text)),
    null => _refused(
      DiagnosticCode.unknownTrustedDocument,
      'No trusted document has the id "$hash".',
    ),
  };

  DocumentRejected _refused(DiagnosticCode code, String message) =>
      DocumentRejected([errors.coded(code, message)]);
}
