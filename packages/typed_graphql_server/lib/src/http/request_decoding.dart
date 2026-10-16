import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// What decoding the GraphQL parameters of an HTTP request gave: a request, a
/// batch, or the refusal to write.
@internal
sealed class RequestDecoding {
  /// Creates a decoding.
  const RequestDecoding();
}

/// One request, ready for the pipeline.
@internal
final class DecodedRequest extends RequestDecoding {
  /// Creates the decoding of [request].
  const DecodedRequest(this.request);

  /// The decoded parameters.
  final GraphQLRequest request;
}

/// A JSON array of requests whose items are not decoded yet, because the
/// batch policy decides first whether they are wanted at all.
@internal
final class DecodedBatch extends RequestDecoding {
  /// Creates the decoding of a batch of [items].
  const DecodedBatch(this.items);

  /// The array's items, in order.
  final List<JsonValue> items;
}

/// A request the transport refuses before the pipeline.
@internal
final class DecodingRefusal extends RequestDecoding {
  /// Creates a refusal with the HTTP [status], the [code] of the error and its
  /// [message].
  const DecodingRefusal(this.status, this.code, this.message);

  /// The HTTP status of the response.
  final int status;

  /// The code in the error's `extensions`.
  final DiagnosticCode code;

  /// The message of the error.
  final String message;
}
