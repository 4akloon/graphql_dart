import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/header_names.dart';
import '../server/server_response.dart';
import 'http_response_body.dart';
import 'http_response_data.dart';
import 'json_bytes.dart';
import 'response_media_type.dart';
import 'status_table.dart';

/// Writes the results of the pipeline as HTTP responses (spec section 5).
@internal
final class ResultWriter {
  /// Creates a writer; see [StatusTable.usesPartialSuccessStatus].
  const ResultWriter({required this.usesPartialSuccessStatus});

  /// Whether a result with errors gets `294` under
  /// `application/graphql-response+json`.
  final bool usesPartialSuccessStatus;

  StatusTable get _statuses =>
      StatusTable(usesPartialSuccessStatus: usesPartialSuccessStatus);

  /// [response] as an HTTP response of media type [type]: the response's
  /// headers, then our `content-type`, which wins over any header an
  /// extension set.
  HttpResponseData single(SingleResponse response, ResponseMediaType type) =>
      HttpResponseData(
        _statuses.of(response, type),
        headers: _headers(response.headers, type),
        body: FixedBody(const JsonBytes().of(response.body)),
      );

  /// The `200` response to a batch: a JSON array of the [payloads], in order.
  HttpResponseData batch(
    List<ResponsePayload> payloads,
    ResponseMediaType type,
  ) => HttpResponseData(
    200,
    headers: _headers(const {}, type),
    body: FixedBody(
      const JsonBytes().of(
        JsonArray([for (final payload in payloads) payload.toJson()]),
      ),
    ),
  );

  Map<String, String> _headers(
    Map<String, String> base,
    ResponseMediaType type,
  ) => const HeaderNames().merged(base, {'content-type': type.contentType});
}
