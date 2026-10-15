import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_hash.dart';
import 'trusted_manifest_reader.dart';

/// The only documents a server runs, by the SHA-256 of their text (R5.4).
///
/// With `GraphQLServer(trustedDocuments:)` a request names a document by its
/// hash in `extensions.persistedQuery`, or sends a text that is one of them
/// to the character; any other text is refused (`GQL414`).
///
/// {@category persisted}
final class TrustedDocuments {
  /// Creates the set from [documents], id to text.
  ///
  /// An id that is not the lower-case hexadecimal SHA-256 of the UTF-8 of
  /// its text is an [ArgumentError].
  TrustedDocuments(Map<String, String> documents)
    : _documents = Map.unmodifiable(documents) {
    for (final MapEntry(key: id, value: text) in documents.entries) {
      if (const DocumentHash().of(text) != id) {
        throw ArgumentError.value(
          id,
          'documents',
          'is not the SHA-256 of its text',
        );
      }
    }
  }

  /// Reads the persisted-operations manifest that `typed_graphql_codegen`
  /// writes (`apollo-persisted-query-manifest`, version 1).
  ///
  /// A malformed manifest, or an id that is not the SHA-256 of its body, is
  /// a [DecodeFailure] with its path.
  static DecodeResult<TrustedDocuments> decode(JsonValue manifest) =>
      switch (const TrustedManifestReader().read(manifest)) {
        DecodeSuccess(:final value) => DecodeSuccess(TrustedDocuments(value)),
        final DecodeFailure failure => failure,
      };

  final Map<String, String> _documents;

  /// The number of documents.
  int get length => _documents.length;

  /// The text of the document [id] names, or null when none is trusted.
  String? textOf(String id) => _documents[id];
}
