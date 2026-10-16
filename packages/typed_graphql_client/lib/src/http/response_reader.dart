import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import '../link/http_response_info.dart';
import '../link/link_context.dart';
import '../link/link_result.dart';
import 'media_type.dart';
import 'transport_response.dart';

/// Turns an HTTP answer into a [LinkResult]: the GraphQL over HTTP rules
/// for status codes and media types, a byte limit counted while the body
/// streams, strict UTF-8, bounded JSON nesting (spec section 9, R0.3).
///
/// It never throws for a hostile answer; an `Exception` of the body stream
/// goes to the caller, which reports it as a network failure.
@internal
final class const ResponseReader({
  /// The most bytes a body may have.
  required final int maxBytes,

  /// The deepest JSON nesting a body may have.
  required final int maxDepth,
}) {
  /// Creates a reader.
  this;

  /// Reads [response]: a payload with an `HttpResponseInfo` in its
  /// context, or the failure that explains why there is none.
  Future<LinkResult> read(TransportResponse response) async {
    final type = MediaType.parse(response.headers['content-type']);
    if (_refusal(response, type) case final failure?) {
      return LinkFailure(failure);
    }
    final bytes = await _collect(response.body);
    if (bytes == null) {
      return LinkFailure(
        ResponseFormatFailure(
          .responseTooLarge,
          'The response is longer than $maxBytes bytes.',
        ),
      );
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return LinkFailure(
        ResponseFormatFailure(.malformedResponse, 'The response is not UTF-8.'),
      );
    }
    final info = HttpResponseInfo(
      response.statusCode,
      headers: response.headers,
    );
    return resultOf(text, LinkContext([info]));
  }

  /// The payload [text] holds, with [context], or the `GQL464` failure
  /// that says where it is malformed.
  LinkResult resultOf(String text, LinkContext context) {
    final decoded = switch (JsonReader(maxDepth: maxDepth).parse(text)) {
      DecodeSuccess(:final value) => ResponsePayload.decode(value),
      final DecodeFailure failure => failure,
    };
    return switch (decoded) {
      DecodeSuccess(:final value) => LinkPayload(value, context: context),
      final DecodeFailure failure => LinkFailure(
        ResponseFormatFailure(
          .malformedResponse,
          'The response is not a GraphQL response: $failure',
          path: failure.path,
        ),
      ),
    };
  }

  /// Why [response] is not read, or null to read it: a GraphQL response
  /// is read whatever its status, JSON only with a 2xx status.
  ClientFailure? _refusal(TransportResponse response, MediaType type) {
    final status = response.statusCode;
    final isSuccess = status >= 200 && status < 300;
    final isReadable =
        type.essence == MediaType.graphQLResponse ||
        (type.essence == MediaType.json && isSuccess);
    if (!isReadable) {
      return isSuccess
          ? ResponseFormatFailure(.unsupportedResponseType, _typeMessage(type))
          : HttpStatusFailure(status, headers: response.headers);
    }
    if (!type.isUtf8) {
      return ResponseFormatFailure(
        .unsupportedResponseType,
        'The response is in charset "${type.charset}"; only UTF-8 is read.',
      );
    }
    return null;
  }

  String _typeMessage(MediaType type) => switch (type.essence) {
    null => 'The response has no content type.',
    final essence =>
      'The response has content type "$essence", which is not a GraphQL '
          'response.',
  };

  /// The body's bytes, or null as soon as they pass [maxBytes]; leaving
  /// the loop cancels the body stream.
  Future<Uint8List?> _collect(Stream<List<int>> body) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body) {
      if (bytes.length + chunk.length > maxBytes) {
        return null;
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}
