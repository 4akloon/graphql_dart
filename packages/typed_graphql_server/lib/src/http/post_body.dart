import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'body_read_result.dart';
import 'body_reader.dart';
import 'content_type.dart';
import 'http_options.dart';
import 'http_request_data.dart';
import 'json_body_decoder.dart';
import 'request_decoding.dart';

/// Turns the body of a `POST` into a decoding: it checks the content type and
/// the declared length, reads the body within the limits and decodes the JSON
/// (spec section 4, steps 5 to 8).
@internal
final class PostBody {
  /// Creates the reader for a handler configured with [options].
  const PostBody(this.options);

  /// The limits to apply.
  final HttpOptions options;

  /// Decodes the body of [request]; the body is not touched when the content
  /// type or the declared length already refuse the request.
  Future<RequestDecoding> decode(HttpRequestData request) async {
    if (!_isJson(ContentType.parse(request.header('content-type')))) {
      return const DecodingRefusal(
        415,
        DiagnosticCode.unsupportedMediaType,
        'A POST request must have the content type application/json.',
      );
    }
    final length = int.tryParse(request.header('content-length')?.trim() ?? '');
    if (length != null && length > options.maxBodyBytes) return _tooLarge();
    final result = await BodyReader(
      options.maxBodyBytes,
      options.bodyTimeout,
    ).read(request.body);
    return switch (result) {
      BodyBytes(:final bytes) => JsonBodyDecoder(
        maxJsonDepth: options.maxJsonDepth,
      ).decode(bytes),
      BodyTooLarge() => _tooLarge(),
      BodyTimedOut() => DecodingRefusal(
        408,
        DiagnosticCode.requestBodyTimeout,
        'The request body did not arrive within '
        '${options.bodyTimeout.inMilliseconds} ms.',
      ),
      BodyFailed() => const DecodingRefusal(
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body could not be read.',
      ),
    };
  }

  // `application/json`, with no parameter but an optional utf-8 charset.
  bool _isJson(ContentType? type) =>
      type != null &&
      type.mediaType == 'application/json' &&
      type.parameters.keys.every((name) => name == 'charset') &&
      (type.charset == null || type.charset == 'utf-8');

  DecodingRefusal _tooLarge() => DecodingRefusal(
    413,
    DiagnosticCode.requestBodyTooLarge,
    'The request body is larger than ${options.maxBodyBytes} bytes.',
  );
}
