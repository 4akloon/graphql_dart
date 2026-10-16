import 'package:typed_graphql/typed_graphql.dart';

import '../server/graphql_server.dart';
import '../sse/distinct_stream.dart';
import '../sse/single_connection_routes.dart';
import '../sse/sse_options.dart';
import '../upload/multipart_result.dart';
import 'accept_negotiation.dart';
import 'batch_runner.dart';
import 'content_type.dart';
import 'get_parameters.dart';
import 'http_options.dart';
import 'http_options_check.dart';
import 'http_request_data.dart';
import 'http_response_data.dart';
import 'json_body_decoder.dart';
import 'json_exchange.dart';
import 'multipart_post.dart';
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
      _writer = ResultWriter(
        usesPartialSuccessStatus: options.usesPartialSuccessStatus,
      ) {
    const HttpOptionsCheck().check(options);
    final sse = options.sse;
    final limits = sse?.singleConnection;
    if (sse != null && limits != null) {
      _routes = SingleConnectionRoutes<C>(
        server: server,
        limits: limits,
        keepAliveInterval: sse.keepAliveInterval,
        errors: _errors,
        writer: ResultWriter(
          usesPartialSuccessStatus: options.usesPartialSuccessStatus,
        ),
      );
    }
  }

  /// The pipeline requests are sent to.
  final GraphQLServer<C> server;

  /// The limits and settings of the handler.
  final HttpOptions options;

  final TransportErrors _errors;
  final ResultWriter _writer;

  // `late`: built on first use, from the `_writer` that the initializer list
  // cannot read.
  late final JsonExchange<C> _exchange = JsonExchange<C>(server, _writer);

  // `late` for the same reason as `_exchange`.
  late final DistinctStream<C> _distinct = DistinctStream<C>(
    server,
    (options.sse ?? const SseOptions()).keepAliveInterval,
    _writer,
  );

  // Null without a batch policy: the decoder refuses a batch then, so no
  // runner is needed.
  late final BatchRunner<C>? _batches = switch (options.batching) {
    final policy? => BatchRunner<C>(server, policy, _writer),
    null => null,
  };

  // Null when single connection mode is off; set at most once, in the
  // constructor body, after the options were checked.
  SingleConnectionRoutes<C>? _routes;

  static const List<ResponseMediaType> _offered = [
    ResponseMediaType.graphqlResponseJson,
    ResponseMediaType.json,
  ];

  static const List<ResponseMediaType> _offeredWithEventStream = [
    ..._offered,
    ResponseMediaType.eventStream,
  ];

  /// Answers [request]; it never throws, so a host can always write what it
  /// returns.
  Future<HttpResponseData> handle(HttpRequestData request) async {
    try {
      return await _handle(request);
    } on Object catch (error, stackTrace) {
      // The outermost boundary, like `GraphQLServer.handle`: a bug anywhere
      // below must still be a response, so it is reported through the hook
      // and never rethrown.
      return _errors.reported(error, stackTrace, options.onError);
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
    final early = _routes?.early(request, method);
    if (early != null) return early;
    if (method != 'GET' && method != 'POST') return _unsupportedMethod();
    final negotiation = AcceptNegotiation(_offeredFor(request, method));
    final type = negotiation.choose(request.header('accept'));
    if (type == null) {
      return _errors.refusal(
        406,
        DiagnosticCode.notAcceptable,
        'The Accept header allows none of ${negotiation.description}.',
      );
    }
    if (method == 'GET') {
      final decoding = GetParameters(options.maxJsonDepth).decode(request.uri);
      return _answer(request, decoding, type);
    }
    final multipart = _multipart;
    if (multipart != null && multipart.isMultipart(request)) {
      return _answerMultipart(request, multipart, type);
    }
    return _answer(request, await PostBody(options).decode(request), type);
  }

  HttpResponseData _unsupportedMethod() => _routes == null
      ? _errors.refusal(
          405,
          DiagnosticCode.unsupportedHttpMethod,
          'Only GET and POST requests are supported.',
          headers: const {'allow': 'GET, POST'},
        )
      : _errors.refusal(
          405,
          DiagnosticCode.unsupportedHttpMethod,
          'Only GET, POST, PUT and DELETE requests are supported.',
          headers: const {'allow': 'GET, POST, PUT, DELETE'},
        );

  // A multipart body cannot start an event stream (spec section 5).
  List<ResponseMediaType> _offeredFor(HttpRequestData request, String method) {
    final isMultipartPost =
        method == 'POST' &&
        ContentType.parse(request.header('content-type'))?.mediaType ==
            'multipart/form-data';
    return options.sse == null || isMultipartPost
        ? _offered
        : _offeredWithEventStream;
  }

  MultipartPost? get _multipart {
    final uploads = options.uploads;
    return uploads == null
        ? null
        : MultipartPost(options, uploads, server.profile.csrfPrevention);
  }

  // The files of the request wait in the storage until the response is
  // built, whatever happened to the request.
  Future<HttpResponseData> _answerMultipart(
    HttpRequestData request,
    MultipartPost multipart,
    ResponseMediaType type,
  ) async {
    switch (await multipart.read(request)) {
      case MultipartRefusal(:final refusal):
        return _answer(request, refusal, type);
      case MultipartContent(:final operations, :final stored):
        try {
          final decoding = JsonBodyDecoder(
            maxJsonDepth: options.maxJsonDepth,
            batching: options.batching,
          ).decodeValue(operations);
          return await _answer(request, decoding, type);
        } finally {
          await stored.release();
        }
    }
  }

  Future<HttpResponseData> _answer(
    HttpRequestData request,
    RequestDecoding decoding,
    ResponseMediaType type,
  ) async {
    final routes = _routes;
    if (routes != null &&
        routes.carriesOperation(request, request.method.toUpperCase())) {
      return routes.operation(request, decoding, type);
    }
    if (type == ResponseMediaType.eventStream) {
      return _answerEventStream(request, decoding);
    }
    return switch (decoding) {
      DecodedRequest(request: final params) => await _exchange.run(
        request,
        params,
        type,
      ),
      DecodedBatch(:final items) => await _runBatch(request, items, type),
      DecodingRefusal(:final status, :final code, :final message) =>
        _errors.refusal(status, code, message),
    };
  }

  // A refusal of the transport stays JSON: the stream starts only for a
  // request the pipeline can run.
  Future<HttpResponseData> _answerEventStream(
    HttpRequestData request,
    RequestDecoding decoding,
  ) async => switch (decoding) {
    DecodedRequest(request: final params) => await _distinct.run(
      request,
      params,
    ),
    DecodedBatch() => _errors.refusal(
      406,
      DiagnosticCode.notAcceptable,
      'A batch cannot be answered as an event stream.',
    ),
    DecodingRefusal(:final status, :final code, :final message) =>
      _errors.refusal(status, code, message),
  };

  Future<HttpResponseData> _runBatch(
    HttpRequestData request,
    List<JsonValue> items,
    ResponseMediaType type,
  ) {
    final batches = _batches;
    if (batches == null) {
      throw StateError('A batch was decoded without a batch policy.');
    }
    return batches.run(request, items, type);
  }
}
