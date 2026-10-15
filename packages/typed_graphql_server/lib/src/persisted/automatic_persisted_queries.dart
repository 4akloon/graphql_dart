import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_handler.dart';
import '../server/document_hash.dart';
import '../server/document_length.dart';
import '../server/document_request.dart';
import '../server/document_result.dart';
import '../server/pipeline_errors.dart';
import '../server/server_extension.dart';
import 'persisted_query_reader.dart';
import 'persisted_query_reference.dart';
import 'persisted_query_store.dart';

/// The document-phase step of automatic persisted queries (R5.4): a hash
/// alone is read from [store]; a text with its hash is checked and, once
/// accepted, written to [store].
///
/// A hash always names its own text: a text whose SHA-256 is not the hash
/// is `GQL411` and never stored, a text is stored only after it parsed and
/// validated, and a stored text is checked again when read, so neither a
/// client nor a shared store can make a hash serve another document.
@internal
final class AutomaticPersistedQueries<C> extends ServerExtension<C> {
  /// Creates the step over [store], checking stored texts with [length] and
  /// refusing through [errors].
  const AutomaticPersistedQueries(this.store, this.length, this.errors);

  /// Where the texts are kept.
  final PersistedQueryStore store;

  /// The length check of a stored text, before it is hashed.
  final DocumentLength length;

  /// Makes the errors.
  final PipelineErrors errors;

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    const reader = PersistedQueryReader();
    switch (reader.read(request.request.params.extensions)) {
      case NoPersistedQuery():
        return next(request);
      case final InvalidPersistedQuery invalid:
        return DocumentRejected([reader.errorOf(invalid, errors)]);
      case PersistedQueryHash(:final hash):
        final text = request.text;
        if (text == null || text.isEmpty) return _stored(request, hash, next);
        return _register(request, text, hash, next);
    }
  }

  Future<DocumentResult> _stored(
    DocumentRequest request,
    String hash,
    DocumentHandler next,
  ) async {
    final text = await store.read(hash);
    if (text == null) return _notFound();
    if (length.violation(text) case final violation?) {
      return DocumentRejected([violation]);
    }
    if (const DocumentHash().of(text) != hash) return _notFound();
    return next(request.withText(text));
  }

  Future<DocumentResult> _register(
    DocumentRequest request,
    String text,
    String hash,
    DocumentHandler next,
  ) async {
    if (const DocumentHash().of(text) != hash) {
      return DocumentRejected([
        errors.coded(
          DiagnosticCode.persistedQueryHashMismatch,
          'provided sha does not match query',
        ),
      ]);
    }
    final result = await next(request);
    if (result case DocumentAccepted()) await store.write(hash, text);
    return result;
  }

  // The message Apollo clients match to send the text with the hash.
  DocumentRejected _notFound() => DocumentRejected([
    errors.coded(
      DiagnosticCode.persistedQueryNotFound,
      'PersistedQueryNotFound',
    ),
  ]);
}
