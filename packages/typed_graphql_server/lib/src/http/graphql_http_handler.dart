import 'package:typed_graphql/typed_graphql.dart';

import '../server/graphql_server.dart';
import 'accept_negotiation.dart';
import 'batch_policy.dart';
import 'batch_runner.dart';
import 'get_parameters.dart';
import 'http_options.dart';
import 'http_options_check.dart';
import 'http_request_data.dart';
import 'http_response_data.dart';
import 'json_exchange.dart';
import 'post_body.dart';
import 'request_decoding.dart';
import 'response_media_type.dart';
import 'result_writer.dart';
import 'transport_errors.dart';

/// Serves GraphQL over HTTP on top of a [GraphQLServer], for any web
/// framework: the host converts its request into an [HttpRequestData], calls
/// [handle] and writes the [HttpResponseData] it gets back (R5.5).
///
/// The handler decodes `GET` and `POST` requests, negotiates the media type
/// and writes results with the status codes of the GraphQL over HTTP
/// specification. Routing, CORS and the time headers take to arrive are the
/// host's.
///
/// {@category http}
final class GraphQLHttpHandler<C> {
  /// Creates a handler that sends requests to [server].
  ///
  /// Throws an `ArgumentError` naming the option when [options] holds a limit
  /// that makes no sense.
  GraphQLHttpHandler(this.server, {this.options = const HttpOptions()})
    : _errors = TransportErrors(server.profile.maskErrors),
      _exchange = JsonExchange<C>(
        server,
        ResultWriter(
          usesPartialSuccessStatus: options.usesPartialSuccessStatus,
        ),
      ),
      // The decoder refuses a batch when there is no policy, so the default
      // here is never used to run one.
      _batches = BatchRunner<C>(
        server,
        options.batching ?? const BatchPolicy(),
        ResultWriter(
          usesPartialSuccessStatus: options.usesPartialSuccessStatus,
        ),
      ) {
    const HttpOptionsCheck().check(options);
  }

  /// The pipeline requests are sent to.
  final GraphQLServer<C> server;

  /// The limits and settings of the handler.
  final HttpOptions options;

  final TransportErrors _errors;
  final JsonExchange<C> _exchange;
  final BatchRunner<C> _batches;

  static const List<ResponseMediaType> _offered = [
    ResponseMediaType.graphqlResponseJson,
    ResponseMediaType.json,
  ];

  /// Answers [request]; it never throws, so a host can always write what it
  /// returns.
  Future<HttpResponseData> handle(HttpRequestData request) async {
    try {
      return await _handle(request);
    } on Object catch (error) {
      // The outermost boundary: a bug anywhere below must still be a response.
      return _errors.unexpected(error);
    }
  }

  Future<HttpResponseData> _handle(HttpRequestData request) async {
    if (request.uri.toString().length > options.maxUriLength) {
      return _errors.refusal(
        414,
        DiagnosticCode.requestUriTooLong,
        'The request URI is longer than ${options.maxUriLength} characters.',
      );
    }
    final method = request.method.toUpperCase();
    if (method != 'GET' && method != 'POST') {
      return _errors.refusal(
        405,
        DiagnosticCode.unsupportedHttpMethod,
        'Only GET and POST requests are supported.',
        headers: const {'allow': 'GET, POST'},
      );
    }
    final type = const AcceptNegotiation(_offered).choose(
      request.header('accept'),
    );
    if (type == null) {
      return _errors.refusal(
        406,
        DiagnosticCode.notAcceptable,
        'The Accept header allows none of application/graphql-response+json '
        'and application/json.',
      );
    }
    final decoding = method == 'GET'
        ? GetParameters(options.maxJsonDepth).decode(request.uri)
        : await PostBody(options).decode(request);
    return _answer(request, decoding, type);
  }

  Future<HttpResponseData> _answer(
    HttpRequestData request,
    RequestDecoding decoding,
    ResponseMediaType type,
  ) async => switch (decoding) {
    DecodedRequest(request: final params) => await _exchange.run(
      request,
      params,
      type,
    ),
    DecodedBatch(:final items) => await _batches.run(request, items, type),
    DecodingRefusal(:final status, :final code, :final message) =>
      _errors.refusal(status, code, message),
  };
}
