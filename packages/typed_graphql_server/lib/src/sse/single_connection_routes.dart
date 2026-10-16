import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/accept_negotiation.dart';
import '../http/http_request_data.dart';
import '../http/http_response_body.dart';
import '../http/http_response_data.dart';
import '../http/request_decoding.dart';
import '../http/response_media_type.dart';
import '../http/result_writer.dart';
import '../http/transport_errors.dart';
import '../server/graphql_server.dart';
import 'connect_outcome.dart';
import 'plain_text_accept.dart';
import 'single_connection_options.dart';
import 'stream_operations.dart';
import 'stream_refusals.dart';
import 'stream_reservations.dart';
import 'stream_token_reader.dart';

/// The requests of single connection mode (spec section 10): reserving a
/// stream, connecting it, posting operations to it and cancelling them.
///
/// State lives here, in one [StreamReservations] per handler.
@internal
final class SingleConnectionRoutes<C> {
  /// Creates the routes over [server]; streams send a comment every
  /// [keepAliveInterval] and follow [limits]. Refusals are made by [errors] and
  /// request errors written by [writer].
  SingleConnectionRoutes({
    required GraphQLServer<C> server,
    required SingleConnectionOptions limits,
    required Duration keepAliveInterval,
    required this.errors,
    required ResultWriter writer,
  }) : _reservations = StreamReservations(
         limits,
         keepAliveInterval: keepAliveInterval,
       ) {
    _operations = StreamOperations<C>(server, _reservations, errors, writer);
  }

  /// Makes the JSON refusals.
  final TransportErrors errors;

  final StreamReservations _reservations;

  // Set in the constructor body, which needs the reservations first.
  late final StreamOperations<C> _operations;

  static const StreamTokenReader _tokens = StreamTokenReader();

  static const List<ResponseMediaType> _connecting = [
    ResponseMediaType.graphqlResponseJson,
    ResponseMediaType.json,
    ResponseMediaType.eventStream,
  ];

  /// Whether [request], a `POST` with a token, carries an operation.
  bool carriesOperation(HttpRequestData request, String method) =>
      method == 'POST' && _tokens.tokenOf(request) != null;

  /// The answer to an operation `POST` decoded as [decoding].
  Future<HttpResponseData> operation(
    HttpRequestData request,
    RequestDecoding decoding,
    ResponseMediaType type,
  ) => _operations.run(request, decoding, type);

  /// The answer to a request that needs nothing from the body, or null when
  /// the request is an ordinary one: `PUT`, `DELETE`, a `GET` that connects
  /// a stream and a `POST` whose token no reservation holds.
  HttpResponseData? early(HttpRequestData request, String method) {
    if (method == 'PUT') return _reserve(request);
    if (method == 'DELETE') return _cancel(request);
    final token = _tokens.tokenOf(request);
    if (token == null || (method != 'GET' && method != 'POST')) return null;
    // Only a `GET` connects; a `POST` with a token is an operation.
    if (method == 'GET' && _asksForEventStream(request)) {
      return _connect(token);
    }
    if (method == 'POST' && _reservations.lookup(token) == null) {
      return StreamRefusals(errors).notFound();
    }
    return null;
  }

  bool _asksForEventStream(HttpRequestData request) =>
      const AcceptNegotiation(_connecting).choose(request.header('accept')) ==
      ResponseMediaType.eventStream;

  HttpResponseData _reserve(HttpRequestData request) {
    if (!const PlainTextAccept().allows(request.header('accept'))) {
      return errors.refusal(
        406,
        DiagnosticCode.notAcceptable,
        'The Accept header allows none of text/plain.',
      );
    }
    final token = _reservations.reserve();
    if (token == null) {
      return errors.refusal(
        503,
        DiagnosticCode.tooManyReservations,
        'The server holds too many event stream reservations.',
      );
    }
    return HttpResponseData(
      201,
      headers: const {'content-type': PlainTextAccept.contentType},
      body: FixedBody(utf8.encode(token)),
    );
  }

  HttpResponseData _connect(String token) => switch (_reservations.connect(
    token,
  )) {
    Connected(:final stream) => stream.response(),
    UnknownToken() => StreamRefusals(errors).notFound(),
    AlreadyOpen() => errors.refusal(
      409,
      DiagnosticCode.eventStreamAlreadyOpen,
      'The event stream for this token is already open.',
    ),
  };

  // An unknown operation id is `200` as well, as the reference answers: the
  // client wanted it gone and it is.
  HttpResponseData _cancel(HttpRequestData request) {
    final token = _tokens.tokenOf(request);
    final connection = token == null ? null : _reservations.lookup(token);
    if (connection == null) return StreamRefusals(errors).notFound();
    final id = _tokens.operationIdOf(request);
    if (id == null) {
      return errors.refusal(
        400,
        DiagnosticCode.operationIdRequired,
        'A cancellation on an event stream needs the operationId parameter, '
        'at most ${StreamTokenReader.maxOperationIdLength} characters.',
      );
    }
    connection.cancelOperation(id);
    return HttpResponseData(200, body: const FixedBody([]));
  }
}
