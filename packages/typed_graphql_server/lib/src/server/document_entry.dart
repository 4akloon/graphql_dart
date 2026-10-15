import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// The outcome of compiling one document text, as the cache keeps it:
/// [AcceptedEntry] or [RejectedEntry]. Both know the [hash] of the text.
@internal
sealed class DocumentEntry {
  /// Creates an entry for the text whose hash is [hash].
  const DocumentEntry(this.hash);

  /// The SHA-256 of the text, computed by the server.
  final String hash;
}

/// A text that parsed and validated.
@internal
final class AcceptedEntry extends DocumentEntry {
  /// Creates an entry holding the [document] and the [source] it came from.
  const AcceptedEntry(super.hash, this.document, this.source);

  /// The validated document; the same object for every request with the same
  /// text.
  final ValidDocument document;

  /// The text, for locations in later messages.
  final Source source;
}

/// A text that did not parse or validate; failures are cached too.
@internal
final class RejectedEntry extends DocumentEntry {
  /// Creates an entry holding the [errors] of the text.
  const RejectedEntry(super.hash, this.errors);

  /// The errors, never empty.
  final List<GraphQLError> errors;
}
