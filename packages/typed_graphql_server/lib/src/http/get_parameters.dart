import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'request_decoding.dart';

/// Reads the GraphQL parameters of a `GET` request from its query string
/// (spec section 4, step 4).
@internal
final class GetParameters {
  /// Creates a reader that accepts `variables` and `extensions` nested at most
  /// [maxJsonDepth] deep.
  const GetParameters(this.maxJsonDepth);

  /// The deepest nesting of arrays and objects accepted in a JSON parameter.
  final int maxJsonDepth;

  /// Decodes the query string of [uri], never throwing.
  ///
  /// Only `query`, `operationName`, `variables` and `extensions` are read; an
  /// empty value is absent, and a parameter given twice is refused, because
  /// two proxies could read different ones.
  RequestDecoding decode(Uri uri) {
    final Map<String, List<String>> all;
    try {
      all = uri.queryParametersAll;
    } on FormatException {
      return _refusal('The query string is not valid UTF-8.');
    }
    for (final name in _names) {
      if ((all[name]?.length ?? 0) > 1) {
        return _refusal('The parameter $name is given more than once.');
      }
    }
    return _decodeObjects(
      query: _value(all, 'query'),
      operationName: _value(all, 'operationName'),
      variables: _value(all, 'variables'),
      extensions: _value(all, 'extensions'),
    );
  }

  static const List<String> _names = [
    'query',
    'operationName',
    'variables',
    'extensions',
  ];

  String? _value(Map<String, List<String>> all, String name) {
    final value = all[name]?.single;
    return value == null || value.isEmpty ? null : value;
  }

  RequestDecoding _decodeObjects({
    required String? query,
    required String? operationName,
    required String? variables,
    required String? extensions,
  }) => switch ((
    _object('variables', variables),
    _object('extensions', extensions),
  )) {
    (DecodeFailure(:final message), _) ||
    (_, DecodeFailure(:final message)) => _refusal(message),
    (
      DecodeSuccess(value: final parsedVariables),
      DecodeSuccess(value: final parsedExtensions),
    ) =>
      DecodedRequest(
        GraphQLRequest(
          query: query,
          operationName: operationName,
          variables: parsedVariables,
          extensions: parsedExtensions,
        ),
      ),
  };

  // The object a JSON parameter holds; null for an absent parameter.
  DecodeResult<JsonObject?> _object(String name, String? text) {
    if (text == null) return const DecodeSuccess(null);
    return switch (JsonReader(maxDepth: maxJsonDepth).parse(text)) {
      DecodeSuccess(value: final JsonObject object) => DecodeSuccess(object),
      DecodeSuccess() => DecodeFailure(
        'The parameter $name is not a JSON object.',
      ),
      DecodeFailure(:final message) => DecodeFailure(
        'The parameter $name is not valid JSON: $message.',
      ),
    };
  }

  DecodingRefusal _refusal(String message) => DecodingRefusal(
    422,
    DiagnosticCode.malformedRequestParameters,
    message,
  );
}
