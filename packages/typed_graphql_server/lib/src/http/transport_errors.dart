import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

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
  HttpResponseData refusal(
    int status,
    DiagnosticCode code,
    String message, {
    Map<String, String> headers = const {},
  }) => HttpResponseData(
    status,
    headers: const HeaderNames().merged(headers, {
      'content-type': ResponseMediaType.json.contentType,
    }),
    body: FixedBody(
      const JsonBytes().of(
        RequestErrorResult(
          errors: [
            GraphQLError(
              message,
              extensions: JsonObject({'code': JsonString(code.id)}),
            ),
          ],
        ).toJson(),
      ),
    ),
  );

  /// The `500` for a bug in the handler: `GQL330`, with the message of
  /// [error] unless errors are masked.
  HttpResponseData unexpected(Object error) => refusal(
    500,
    DiagnosticCode.unexpectedError,
    maskErrors ? const MaskedMessage().text : _describe(error),
  );

  // A `toString()` that throws must not turn the report into a failure.
  String _describe(Object error) {
    try {
      return error.toString();
    } on Object {
      return const MaskedMessage().text;
    }
  }
}
