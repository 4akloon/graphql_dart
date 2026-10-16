import 'package:typed_graphql/typed_graphql.dart';

/// Why a request got no GraphQL response: the transport failed, the answer
/// was not a GraphQL response, the data did not fit the operation, or the
/// caller stopped it (R8.2).
///
/// Every failure is a value with a stable [code] (`GQL460`-`GQL474`);
/// nothing a server or a network does makes the client throw (R0.3).
///
/// {@category client}
sealed class ClientFailure {
  /// Creates a failure.
  const ClientFailure();

  /// The diagnostic code of this kind of failure.
  DiagnosticCode get code;

  /// What happened, as a sentence.
  String get message;

  @override
  String toString() => '${code.id}: $message';
}

/// The transport could not send the request or read the answer (`GQL460`).
///
/// {@category client}
final class const NetworkFailure(
  /// What the HTTP client or the socket threw.
  final Exception cause,
) extends ClientFailure {
  /// Creates the failure for [cause].
  this;

  @override
  DiagnosticCode get code => .networkFailure;

  @override
  String get message => 'The request failed: $cause';
}

/// An HTTP answer with a status outside 2xx whose body is not a GraphQL
/// response (`GQL461`).
///
/// {@category client}
final class HttpStatusFailure(
  /// The HTTP status code.
  final int statusCode, {
  Map<String, String> headers = const {},
}) extends ClientFailure {
  /// Creates the failure for [statusCode]; [headers] is copied.
  this;

  /// The answer's headers, names in lower case.
  final Map<String, String> headers = Map.unmodifiable(headers);

  @override
  DiagnosticCode get code => .httpErrorStatus;

  @override
  String get message => 'The server answered with HTTP status $statusCode.';
}

/// An answer that is not a GraphQL response: an unreadable content type
/// (`GQL462`), too long (`GQL463`) or malformed (`GQL464`).
///
/// {@category client}
final class ResponseFormatFailure(
  @override final DiagnosticCode code,
  @override final String message, {
  List<PathSegment> path = const [],
}) extends ClientFailure {
  /// Creates the failure; [path] is copied.
  this;

  /// Where in the JSON body the problem is; empty for the body itself.
  final List<PathSegment> path = List.unmodifiable(path);
}

/// A response whose `data` does not have the shape of the operation's
/// generated classes (`GQL465`).
///
/// {@category client}
final class DataFormatFailure(
  /// What the generated reader found, and where in `data`.
  final DecodeFailure decodeFailure, {
  List<GraphQLError> errors = const [],
}) extends ClientFailure {
  /// Creates the failure; [errors] is copied.
  this;

  /// The errors the server sent with the data, kept for diagnosis.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  @override
  DiagnosticCode get code => .dataShapeMismatch;

  @override
  String get message => 'The data does not fit the operation: $decodeFailure';
}

/// The caller cancelled the request before its answer (`GQL466`).
///
/// {@category client}
final class const RequestCancelled([
  /// What the caller gave `CancelToken.cancel`, if anything.
  final Object? reason,
]) extends ClientFailure {
  /// Creates the failure.
  this;

  @override
  DiagnosticCode get code => .requestCancelled;

  @override
  String get message => reason == null
      ? 'The request was cancelled.'
      : 'The request was cancelled: $reason';
}

/// A link's timeout passed before the answer (`GQL467`).
///
/// {@category client}
final class const RequestTimedOut(
  /// The timeout that passed.
  final Duration timeout,
) extends ClientFailure {
  /// Creates the failure.
  this;

  @override
  DiagnosticCode get code => .requestTimedOut;

  @override
  String get message => 'No answer within ${timeout.inMilliseconds} ms.';
}

/// A link chain that cannot carry the request (`GQL468`) or that ended
/// without a result (`GQL469`).
///
/// {@category client}
final class const UnsupportedOperation(
  @override final DiagnosticCode code,
  @override final String message,
) extends ClientFailure {
  /// Creates the failure.
  this;
}

/// A graphql-transport-ws socket that broke the protocol (`GQL470`), closed
/// for good (`GQL471`) or was not acknowledged in time (`GQL472`).
///
/// {@category client}
final class const SocketFailure(
  @override final DiagnosticCode code,
  @override final String message, {

  /// The close code of the socket, when it closed.
  final int? closeCode,

  /// The close reason of the socket, when it gave one.
  final String? closeReason,
}) extends ClientFailure {
  /// Creates the failure.
  this;
}

/// A graphql-sse stream with an unknown event or without its `complete`
/// (`GQL473`).
///
/// {@category client}
final class const EventStreamFailure(@override final String message)
    extends ClientFailure {
  /// Creates the failure.
  this;

  @override
  DiagnosticCode get code => .malformedEventStream;
}

/// The callback that gives or refreshes an authentication token threw
/// (`GQL474`).
///
/// {@category client}
final class const AuthenticationFailure(
  /// What the callback threw.
  final Exception cause,
) extends ClientFailure {
  /// Creates the failure for [cause].
  this;

  @override
  DiagnosticCode get code => .authenticationFailed;

  @override
  String get message => 'Could not get a token: $cause';
}
