import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_hash.dart';

/// Reads the persisted-operations manifest M10 writes (Apollo's
/// `apollo-persisted-query-manifest`, version 1) into ids and texts.
///
/// Only `id` and `body` of an operation are read; an id that is not the
/// SHA-256 of its body is a failure, so a forged manifest entry cannot make
/// one hash stand for another text.
@internal
final class TrustedManifestReader {
  /// Creates the reader.
  const TrustedManifestReader();

  static const String _format = 'apollo-persisted-query-manifest';

  /// The documents of [manifest], id to text, or where it is malformed.
  DecodeResult<Map<String, String>> read(JsonValue manifest) =>
      switch (manifest) {
        JsonObject(:final fields) => _manifest(fields),
        _ => const DecodeFailure('expected an object'),
      };

  DecodeResult<Map<String, String>> _manifest(Map<String, JsonValue> fields) {
    if (fields['format'] != const JsonString(_format)) {
      return const DecodeFailure(
        'expected "$_format"',
      ).inside(const PathKey('format'));
    }
    if (fields['version'] != JsonNumber(1)) {
      return const DecodeFailure(
        'expected 1',
      ).inside(const PathKey('version'));
    }
    return switch (fields['operations']) {
      JsonArray(:final items) => _operations(
        items,
      ).inside(const PathKey('operations')),
      _ => const DecodeFailure(
        'expected an array',
      ).inside(const PathKey('operations')),
    };
  }

  DecodeResult<Map<String, String>> _operations(List<JsonValue> items) {
    final documents = <String, String>{};
    for (final (index, item) in items.indexed) {
      switch (_operation(item)) {
        case DecodeSuccess(value: (final id, final body)):
          documents[id] = body;
        case final DecodeFailure failure:
          return failure.inside(PathIndex(index));
      }
    }
    return DecodeSuccess(documents);
  }

  DecodeResult<(String, String)> _operation(JsonValue item) {
    if (item case JsonObject(
      fields: {
        'id': JsonString(value: final id),
        'body': JsonString(value: final body),
      },
    )) {
      if (const DocumentHash().of(body) == id) return DecodeSuccess((id, body));
      return const DecodeFailure(
        'expected the SHA-256 of the body',
      ).inside(const PathKey('id'));
    }
    return const DecodeFailure('expected an object with a string id and body');
  }
}
