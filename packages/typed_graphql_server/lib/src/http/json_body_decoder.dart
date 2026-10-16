import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'batch_policy.dart';
import 'failure_description.dart';
import 'request_decoding.dart';

/// Turns the bytes of a `application/json` POST body into a request, a batch
/// or a refusal (spec section 4, steps 7 and 8).
@internal
final class JsonBodyDecoder {
  /// Creates a decoder that accepts JSON nested at most [maxJsonDepth] deep
  /// and arrays as the [batching] policy allows, or not at all when it is null.
  const JsonBodyDecoder({required this.maxJsonDepth, required this.batching});

  /// The deepest nesting of arrays and objects accepted.
  final int maxJsonDepth;

  /// The policy for an array of requests, or null to refuse arrays.
  final BatchPolicy? batching;

  /// Decodes [bytes], never throwing.
  RequestDecoding decode(Uint8List bytes) {
    // JSON forbids a byte-order mark (RFC 8259 section 8.1), and the UTF-8
    // decoder would drop it silently, so it is looked for in the bytes.
    if (_hasByteOrderMark(bytes)) {
      return const DecodingRefusal(
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body is not valid JSON: it starts with a byte-order '
        'mark.',
      );
    }
    final String text;
    try {
      text = const Utf8Decoder().convert(bytes);
    } on FormatException {
      return const DecodingRefusal(
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body is not valid UTF-8.',
      );
    }
    return switch (JsonReader(maxDepth: maxJsonDepth).parse(text)) {
      DecodeSuccess(:final value) => decodeValue(value),
      DecodeFailure(:final message) => DecodingRefusal(
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body is not valid JSON: $message.',
      ),
    };
  }

  bool _hasByteOrderMark(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;

  /// Decodes a [value] that is already parsed, such as the `operations` field
  /// of a multipart request: an object is a request, an array a batch.
  RequestDecoding decodeValue(JsonValue value) => switch (value) {
    JsonObject() => _decodeRequest(value),
    JsonArray() => _decodeBatch(value),
    _ => const DecodingRefusal(
      422,
      DiagnosticCode.malformedRequestParameters,
      'The request body must be a JSON object.',
    ),
  };

  // The items are not decoded here: a batch over the size limit must cost
  // nothing more than counting them.
  RequestDecoding _decodeBatch(JsonArray array) {
    final policy = batching;
    if (policy == null) {
      return const DecodingRefusal(
        422,
        DiagnosticCode.batchingDisabled,
        'Batched requests are not enabled.',
      );
    }
    if (array.items.isEmpty || array.items.length > policy.maxRequests) {
      return DecodingRefusal(
        422,
        DiagnosticCode.invalidBatchSize,
        'A batch must hold between 1 and ${policy.maxRequests} requests.',
      );
    }
    return DecodedBatch(array.items);
  }

  RequestDecoding _decodeRequest(JsonObject object) =>
      switch (GraphQLRequest.decode(object)) {
        DecodeSuccess(:final value) => DecodedRequest(value),
        DecodeFailure() && final failure => DecodingRefusal(
          422,
          DiagnosticCode.malformedRequestParameters,
          'The request is malformed: ${const FailureDescription().of(failure)}',
        ),
      };
}
