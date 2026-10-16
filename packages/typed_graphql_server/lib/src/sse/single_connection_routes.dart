import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/accept_negotiation.dart';
import '../http/http_request_data.dart';
import '../http/http_response_body.dart';
import '../http/http_response_data.dart';
import '../http/response_media_type.dart';
import '../http/transport_errors.dart';
import 'connect_outcome.dart';
import 'plain_text_accept.dart';
import 'single_connection_options.dart';
import 'stream_refusals.dart';
import 'stream_reservations.dart';
import 'stream_token_reader.dart';

/// The requests of single connection mode (spec section 10): reserving a
/// stream and connecting it.
///
/// State lives here, in one [StreamReservations] per handler.
@internal
final class SingleConnectionRoutes {
  /// Creates the routes: streams send a comment every [keepAliveInterval] and
  /// follow [limits]. Refusals are made by [errors].
  SingleConnectionRoutes({
    required SingleConnectionOptions limits,
    required Duration keepAliveInterval,
    required this.errors,
  }) : _reservations = StreamReservations(
         limits,
         keepAliveInterval: keepAliveInterval,
       );

  /// Makes the JSON refusals.
  final TransportErrors errors;

  final StreamReservations _reservations;

  static const StreamTokenReader _tokens = StreamTokenReader();

  static const List<ResponseMediaType> _connecting = [
    ResponseMediaType.graphqlResponseJson,
    ResponseMediaType.json,
    ResponseMediaType.eventStream,
  ];

  /// The answer to a request that needs nothing from the body, or null when
  /// the request is an ordinary one: a `PUT` and a request that connects a
  /// stream.
  HttpResponseData? early(HttpRequestData request, String method) {
    if (method == 'PUT') return _reserve(request);
    final token = _tokens.tokenOf(request);
    if (token == null || (method != 'GET' && method != 'POST')) return null;
    return _asksForEventStream(request) ? _connect(token) : null;
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
}
