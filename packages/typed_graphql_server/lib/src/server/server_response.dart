import 'package:typed_graphql/typed_graphql.dart';

import 'header_names.dart';
import 'server_outcome.dart';

/// What `GraphQLServer.handle` returns: a [SingleResponse] or a
/// [StreamResponse] (R5.1).
///
/// {@category server}
sealed class ServerResponse {
  /// Creates a response with [headers] (names are lower-cased).
  ServerResponse(Map<String, String> headers)
    : headers = const HeaderNames().lowerCased(headers);

  /// How the request ended.
  ServerOutcome get outcome;

  /// Headers the transport adds to its own, unmodifiable, with lower-case
  /// names.
  final Map<String, String> headers;

  /// A copy of the same kind of response with [additions] merged into the
  /// headers; names are lower-cased and the new values win.
  ServerResponse withHeaders(Map<String, String> additions);
}

/// One payload: the answer to a query or a mutation, or a refusal.
///
/// {@category server}
final class SingleResponse extends ServerResponse {
  /// Creates a response that ended as [outcome].
  SingleResponse(
    this.payload, {
    this.outcome = ServerOutcome.executed,
    Map<String, String> headers = const {},
  }) : super(headers);

  /// The result: an `ExecutionResult` or a `RequestErrorResult`.
  final ResponsePayload payload;

  @override
  final ServerOutcome outcome;

  /// The JSON body of the response, [payload] written.
  JsonObject get body => payload.toJson();

  @override
  SingleResponse withHeaders(Map<String, String> additions) => SingleResponse(
    payload,
    outcome: outcome,
    headers: const HeaderNames().merged(headers, additions),
  );
}

/// The results of a started subscription.
///
/// {@category server}
final class StreamResponse extends ServerResponse {
  /// Creates a response with the [results] of a subscription.
  StreamResponse(this.results, {Map<String, String> headers = const {}})
    : super(headers);

  /// The results, one per event of the subscription.
  final Stream<ExecutionResult> results;

  @override
  ServerOutcome get outcome => ServerOutcome.executed;

  @override
  StreamResponse withHeaders(Map<String, String> additions) => StreamResponse(
    results,
    headers: const HeaderNames().merged(headers, additions),
  );
}
