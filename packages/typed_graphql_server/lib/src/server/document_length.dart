import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'pipeline_errors.dart';

/// The `limits.maxDocumentLength` check, run on the request's query before
/// any hashing and again on a text an extension supplied (R5.4).
@internal
final class DocumentLength {
  /// Creates the check for [maximum] characters, null for no limit.
  const DocumentLength(this.maximum, this.errors);

  /// The most characters a document text may have.
  final int? maximum;

  /// Makes the error.
  final PipelineErrors errors;

  /// The `GQL401` error when [text] is longer than the maximum, else null.
  GraphQLError? violation(String? text) {
    final limit = maximum;
    if (text == null || limit == null || text.length <= limit) return null;
    return errors.coded(
      DiagnosticCode.documentTooLong,
      'The document is longer than the maximum of $limit characters.',
    );
  }
}
