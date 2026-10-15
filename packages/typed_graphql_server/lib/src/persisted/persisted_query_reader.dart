import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/pipeline_errors.dart';
import 'persisted_query_reference.dart';

/// Reads `extensions.persistedQuery` of a request (R5.4).
@internal
final class PersistedQueryReader {
  /// Creates the reader.
  const PersistedQueryReader();

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// The persisted query [extensions] name; a JSON `null` names none.
  PersistedQueryReference read(JsonObject? extensions) =>
      switch (extensions?.fields['persistedQuery']) {
        null || JsonNull() => const NoPersistedQuery(),
        JsonObject(:final fields) => _read(fields),
        _ => const InvalidPersistedQuery('it must be an object'),
      };

  /// The `GQL413` error for [invalid].
  GraphQLError errorOf(InvalidPersistedQuery invalid, PipelineErrors errors) =>
      errors.coded(
        DiagnosticCode.invalidPersistedQuery,
        'Invalid persisted query: ${invalid.reason}.',
      );

  PersistedQueryReference _read(Map<String, JsonValue> fields) {
    if (fields['version'] case JsonNumber(:final value) when value == 1) {
      return switch (fields['sha256Hash']) {
        JsonString(:final value) when _sha256.hasMatch(value) =>
          PersistedQueryHash(value),
        _ => const InvalidPersistedQuery(
          'sha256Hash must be 64 lower-case hexadecimal digits',
        ),
      };
    }
    return const InvalidPersistedQuery('version must be 1');
  }
}
