import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/graphql_exception.dart';
import '../execution/masked_message.dart';
import 'server_outcome.dart';
import 'server_response.dart';

/// Makes the responses a refusal or a failure of the pipeline ends with.
@internal
final class PipelineErrors {
  /// Creates the factory for a server whose profile masks errors when
  /// [maskErrors] is on and whose error hook is [onError].
  const PipelineErrors({required this.maskErrors, this.onError});

  /// Whether an unexpected error is replaced by a generic message.
  final bool maskErrors;

  /// The server's error hook, null when there is none.
  final ErrorHook? onError;

  /// A refusal with one error coded [code].
  SingleResponse refusal(
    DiagnosticCode code,
    String message, {
    ServerOutcome outcome = ServerOutcome.requestError,
    Map<String, String> headers = const {},
  }) => SingleResponse(
    RequestErrorResult(errors: [coded(code, message)]),
    outcome: outcome,
    headers: headers,
  );

  /// A request error carrying [errors].
  SingleResponse rejected(List<GraphQLError> errors) => SingleResponse(
    RequestErrorResult(errors: errors),
    outcome: ServerOutcome.requestError,
  );

  /// A request error with the message and extensions of [exception].
  SingleResponse exception(GraphQLException exception) => rejected([
    GraphQLError(exception.message, extensions: exception.extensions),
  ]);

  /// The response to an unexpected [error]: offered to the hook, then
  /// masked (`GQL330`) or shown by its `toString()`.
  SingleResponse internal(Object error, StackTrace stackTrace) {
    final reported = coded(
      DiagnosticCode.unexpectedError,
      _describe(error),
    );
    return SingleResponse(
      RequestErrorResult(errors: [_hooked(error, stackTrace, reported)]),
      outcome: ServerOutcome.internalError,
    );
  }

  // A `toString()` that throws must not turn the report into a failure.
  String _describe(Object error) {
    if (maskErrors) return const MaskedMessage().text;
    try {
      return error.toString();
    } on Object {
      return const MaskedMessage().text;
    }
  }

  GraphQLError _hooked(
    Object error,
    StackTrace stackTrace,
    GraphQLError reported,
  ) {
    final hook = onError;
    if (hook == null) {
      return reported;
    }
    try {
      return hook(error, stackTrace, reported) ?? reported;
    } on Object {
      return coded(DiagnosticCode.unexpectedError, const MaskedMessage().text);
    }
  }

  /// One error with [message] and `extensions.code` of [code].
  GraphQLError coded(DiagnosticCode code, String message) => GraphQLError(
    message,
    extensions: JsonObject({'code': JsonString(code.id)}),
  );
}
