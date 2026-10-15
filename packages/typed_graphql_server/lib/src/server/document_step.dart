import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'document_cache.dart';
import 'document_compiler.dart';
import 'document_length.dart';
import 'document_request.dart';
import 'document_result.dart';
import 'pipeline_errors.dart';

/// The core step of the document phase: the text becomes a validated
/// document or its errors, through the cache (R5.2).
@internal
final class DocumentStep {
  /// Creates the step over [cache] and [compiler], checking the text with
  /// [length] and refusing through [errors].
  const DocumentStep(this.cache, this.compiler, this.length, this.errors);

  /// Where compiled texts are kept.
  final DocumentCache cache;

  /// Compiles a text the cache does not hold.
  final DocumentCompiler compiler;

  /// Checks the length again: an extension may have supplied the text.
  final DocumentLength length;

  /// Makes the errors of a missing text.
  final PipelineErrors errors;

  /// The result for the text of [request].
  Future<DocumentResult> run(DocumentRequest request) async {
    final text = request.text;
    if (text == null || text.isEmpty) {
      return DocumentRejected([
        errors.coded(
          DiagnosticCode.queryRequired,
          'Must provide query string.',
        ),
      ]);
    }
    if (length.violation(text) case final violation?) {
      return DocumentRejected([violation]);
    }
    return cache.resultFor(text, compiler);
  }
}
