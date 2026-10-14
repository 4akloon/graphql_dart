import 'decode_result.dart';
import 'json_field_reader.dart';
import 'json_value.dart';

/// A GraphQL request as it travels over a transport: the body of a GraphQL
/// over HTTP POST, the payload of a graphql-ws `subscribe` message.
///
/// Every field may be absent: an automatic persisted query sends only a
/// hash in [extensions], and the server decides what a request needs.
/// Two requests are equal when their JSON is equal.
final class const GraphQLRequest({
  /// The document text.
  final String? query,

  /// The operation to run when the document has several.
  final String? operationName,

  /// The values of the operation's variables.
  final JsonObject? variables,

  /// Extra data for the server, such as a persisted query hash.
  final JsonObject? extensions,
}) {
  /// Creates a request.
  this;

  /// Reads a request from [json]; a mistyped `query`, `operationName`,
  /// `variables` or `extensions` is a failure, other keys are ignored as
  /// GraphQL over HTTP requires.
  static DecodeResult<GraphQLRequest> decode(JsonValue json) {
    if (json is! JsonObject) {
      return const DecodeFailure('expected an object');
    }
    final fields = JsonFieldReader(json);
    return switch ((
      fields.optionalString('query'),
      fields.optionalString('operationName'),
      fields.optionalObject('variables'),
      fields.optionalObject('extensions'),
    )) {
      (
        DecodeSuccess(value: final query),
        DecodeSuccess(value: final operationName),
        DecodeSuccess(value: final variables),
        DecodeSuccess(value: final extensions),
      ) =>
        DecodeSuccess(
          GraphQLRequest(
            query: query,
            operationName: operationName,
            variables: variables,
            extensions: extensions,
          ),
        ),
      (final DecodeFailure failure, _, _, _) ||
      (_, final DecodeFailure failure, _, _) ||
      (_, _, final DecodeFailure failure, _) ||
      (_, _, _, final DecodeFailure failure) => failure,
    };
  }

  /// This request as JSON, with the fields that are set.
  JsonObject toJson() => JsonObject({
    if (query case final query?) 'query': JsonString(query),
    if (operationName case final name?) 'operationName': JsonString(name),
    'variables': ?variables,
    'extensions': ?extensions,
  });

  @override
  bool operator ==(Object other) =>
      other is GraphQLRequest && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'GraphQLRequest(${toJson()})';
}
