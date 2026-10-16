import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/masked_message.dart';
import '../server/header_names.dart';
import 'http_response_body.dart';
import 'http_response_data.dart';
import 'json_bytes.dart';
import 'response_media_type.dart';

/// Makes the responses of a refusal the transport itself decides, before or
/// instead of the pipeline.
///
/// A transport refusal is not a well-formed GraphQL-over-HTTP response, so it
/// is always `application/json`, never `application/graphql-response+json`
/// (spec section 5).
@internal
final class TransportErrors {
  /// Creates the factory for a server whose profile masks errors when
  /// [maskErrors] is on.
  const TransportErrors(this.maskErrors);

  /// Whether an unexpected error is replaced by a generic message.
  final bool maskErrors;

  /// A response with [status] and one error coded [code], with [headers] such
  /// as `allow` added.
  ///
  /// It varies on `Accept`, as every response of the handler does (the status
  /// of a refusal can depend on the negotiation), and must not be stored.
  HttpResponseData refusal(
    int status,
    DiagnosticCode code,
    String message, {
    Map<String, String> headers = const {},
  }) => _response(
    status,
    GraphQLError(
      message,
      extensions: JsonObject({'code': JsonString(code.id)}),
    ),
    headers,
  );

  /// The `500` for a bug in the handler: `GQL330`, with the message of
  /// [error] unless errors are masked.
  HttpResponseData unexpected(Object error) =>
      _response(500, unexpectedError(error), const {});

  /// The `500` for a bug caught at the outermost boundary: like [unexpected],
  /// after [onError] has seen [error] and [stackTrace] and possibly replaced
  /// the error; a hook that throws is ignored.
  HttpResponseData reported(
    Object error,
    StackTrace stackTrace,
    ErrorHook? onError,
  ) {
    final standard = unexpectedError(error);
    GraphQLError? replacement;
    if (onError != null) {
      try {
        replacement = onError(error, stackTrace, standard);
      } on Object {
        // A faulty hook must not turn the report into a failure.
        replacement = null;
      }
    }
    return _response(500, replacement ?? standard, const {});
  }

  /// Tells [onError] about an [error] that does not change the response (a
  /// release that failed); a hook that throws is ignored.
  void notify(Object error, StackTrace stackTrace, ErrorHook? onError) {
    if (onError == null) return;
    try {
      onError(error, stackTrace, unexpectedError(error));
    } on Object {
      // A faulty hook must not turn the report into a failure.
    }
  }

  /// The `GQL330` error of [error] as [unexpected] writes it, for a place
  /// that is not a whole response, such as the slot of a batch.
  GraphQLError unexpectedError(Object error) => GraphQLError(
    _unexpectedText(error),
    extensions: JsonObject({
      'code': JsonString(DiagnosticCode.unexpectedError.id),
    }),
  );

  HttpResponseData _response(
    int status,
    GraphQLError error,
    Map<String, String> headers,
  ) => HttpResponseData(
    status,
    headers: const HeaderNames().varied(
      const HeaderNames().merged(headers, {
        'content-type': ResponseMediaType.json.contentType,
        'cache-control': 'no-store',
      }),
      'accept',
    ),
    body: FixedBody(
      const JsonBytes().of(RequestErrorResult(errors: [error]).toJson()),
    ),
  );

  String _unexpectedText(Object error) =>
      maskErrors ? const MaskedMessage().text : _describe(error);

  // A `toString()` that throws must not turn the report into a failure, and a
  // long one is cut: the text is echoed to the client.
  String _describe(Object error) {
    try {
      final text = error.toString();
      if (text.length <= maxDescriptionLength) return text;
      return '${text.substring(0, maxDescriptionLength - 1)}…';
    } on Object {
      return const MaskedMessage().text;
    }
  }

  /// The longest message of an unmasked unexpected error, in characters.
  static const int maxDescriptionLength = 500;
}
