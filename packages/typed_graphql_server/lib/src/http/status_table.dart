import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/server_outcome.dart';
import '../server/server_response.dart';
import 'response_media_type.dart';

/// The HTTP status of a pipeline result (spec section 5; GraphQL over HTTP
/// "Status Codes").
@internal
final class StatusTable {
  /// Creates the table; with [usesPartialSuccessStatus] off, a result with
  /// data and errors is `200` even for `application/graphql-response+json`.
  const StatusTable({required this.usesPartialSuccessStatus});

  /// Whether a result with errors gets `294` under
  /// `application/graphql-response+json`.
  final bool usesPartialSuccessStatus;

  /// The status of [response] written as [type].
  int of(SingleResponse response, ResponseMediaType type) =>
      switch (response.outcome) {
        ServerOutcome.executed => _executed(response.payload, type),
        ServerOutcome.requestError => _requestError(response.payload),
        ServerOutcome.methodNotAllowed => 405,
        ServerOutcome.internalError => 500,
      };

  // A legacy client keeps 200 whatever the result (deviation 6).
  int _executed(ResponsePayload payload, ResponseMediaType type) =>
      payload.errors.isNotEmpty &&
          usesPartialSuccessStatus &&
          type == ResponseMediaType.graphqlResponseJson
      ? 294
      : 200;

  // `GQL0xx`: the document does not parse; `GQL403`: CSRF prevention.
  int _requestError(ResponsePayload payload) {
    final code = switch (payload.errors) {
      [GraphQLError(extensions: JsonObject(:final fields)), ...] =>
        fields['code'],
      _ => null,
    };
    if (code is! JsonString) return 422;
    if (code.value.startsWith('GQL0')) return 400;
    return code.value == DiagnosticCode.csrfRequestBlocked.id ? 403 : 422;
  }
}
