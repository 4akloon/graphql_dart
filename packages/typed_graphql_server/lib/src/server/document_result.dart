import 'package:typed_graphql/typed_graphql.dart';

/// What resolving a document text ends with: [DocumentAccepted] or
/// [DocumentRejected] (R5.2, R5.3).
///
/// {@category server}
sealed class DocumentResult {
  const DocumentResult();
}

/// A text that parsed and validated.
///
/// {@category server}
final class DocumentAccepted extends DocumentResult {
  /// Creates a result holding the [document], the [source] it came from and
  /// the [hash] of the text.
  const DocumentAccepted(this.document, this.source, this.hash);

  /// The validated document; the same object for every request with the same
  /// text while the server's cache holds it.
  final ValidDocument document;

  /// The text, for locations in later messages.
  final Source source;

  /// The SHA-256 of the text, as lower-case hex: the cache key the server
  /// computed, never a value a client sent.
  final String hash;
}

/// A text that did not resolve to a document: it is missing, too long, or it
/// did not parse or validate. The request ends as a request error.
///
/// {@category server}
final class DocumentRejected extends DocumentResult {
  /// Creates a result holding the [errors], which must not be empty.
  const DocumentRejected(this.errors);

  /// The errors the response carries.
  final List<GraphQLError> errors;
}
