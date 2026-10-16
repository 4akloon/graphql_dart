import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'json_refusal.dart';
import 'request_conversion.dart';
import 'upgrade_handshake.dart';
import 'web_socket_channel_socket.dart';

/// Turns a WebSocket upgrade into a graphql-ws session.
///
/// The handshake is written here, not by `shelf_web_socket`, because that
/// package gives `dart:io` no limit on the size of a frame: a peer could make
/// the server buffer whatever size its frame header declares before the
/// session sees the first byte.
@internal
final class WebSocketUpgrade<C> {
  /// Creates the upgrade for [_handler], with WebSocket ping frames every
  /// [_pingInterval] and frames of at most the bytes that a message of
  /// [maxMessageLength] UTF-16 code units can take.
  WebSocketUpgrade(
    this._handler,
    this._pingInterval,
    int maxMessageLength, [
    this._onError,
  ]) : maxFrameBytes = maxMessageLength * 3 + 1024;

  final GraphQLWsHandler<C> _handler;
  final Duration _pingInterval;
  final ErrorHook? _onError;

  /// The largest frame payload `dart:io` accepts; a larger frame closes the
  /// socket (`dart:io` sends `1002`) before the payload is buffered. A UTF-16
  /// code unit takes at most three bytes in UTF-8; the slack is for a message
  /// that ends right at its limit.
  final int maxFrameBytes;

  /// Whether [request] asks to become a WebSocket.
  bool isUpgrade(Request request) =>
      request.method == 'GET' &&
      request.headers['upgrade']?.toLowerCase() == 'websocket';

  /// Answers the upgrade [request]: a `403` when its `Origin` is not allowed
  /// (a browser sends cookies with an upgrade and no preflight, spec section
  /// 9), a `400` when the handshake is incomplete, else the `101` that starts
  /// the session. Throws a [StateError] when the request cannot be hijacked,
  /// which the handler answers `500`.
  FutureOr<Response> handle(Request request) {
    final info = const RequestConversion().info(request);
    if (!_handler.allowsUpgrade(info)) {
      // The CSRF code, because this is the CSRF defence of the transport.
      return const JsonRefusal().of(
        403,
        DiagnosticCode.csrfRequestBlocked,
        'The Origin of this WebSocket upgrade is not allowed.',
      );
    }
    final handshake = UpgradeHandshake(request);
    final problem = handshake.problem;
    if (problem != null) {
      return const JsonRefusal().of(
        400,
        DiagnosticCode.malformedRequestParameters,
        problem,
      );
    }
    if (!request.canHijack) {
      throw StateError('A WebSocket upgrade needs a host that can hijack.');
    }
    final protocol = handshake.subprotocol(GraphQLWsHandler.protocol);
    final accept = WebSocketChannel.signKey(handshake.key!);
    request.hijack((channel) => _guarded(channel, accept, protocol, info));
  }

  // A boundary: the callback runs where nobody catches, so what it throws is
  // reported to the hook and the connection is closed, never rethrown.
  void _guarded(
    StreamChannel<List<int>> channel,
    String accept,
    String? protocol,
    RequestInfo info,
  ) {
    try {
      _start(channel, accept, protocol, info);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      try {
        channel.sink.close().ignore();
      } on Object {
        // The sink is already unusable; there is nothing left to close.
      }
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    final hook = _onError;
    if (hook == null) return;
    try {
      hook(
        error,
        stackTrace,
        const JsonRefusal().error(
          DiagnosticCode.unexpectedError,
          'The WebSocket upgrade could not be completed.',
        ),
      );
    } on Object {
      // A faulty hook must not turn the report into a failure.
    }
  }

  void _start(
    StreamChannel<List<int>> channel,
    String accept,
    String? protocol,
    RequestInfo info,
  ) {
    switch (channel.sink) {
      case final Socket socket:
        _serve(socket, accept, protocol, info);
      case _:
        throw ArgumentError('The hijacked channel must be a Socket.');
    }
  }

  void _serve(
    Socket socket,
    String accept,
    String? protocol,
    RequestInfo info,
  ) {
    socket.add(utf8.encode(_response(accept, protocol)));
    final channel = IOWebSocketChannel(
      WebSocket.fromUpgradedSocket(
        socket,
        protocol: protocol,
        serverSide: true,
        maxPayloadLength: maxFrameBytes,
      )..pingInterval = _pingInterval,
    );
    unawaited(
      _handler.serve(WebSocketChannelSocket(channel, protocol), info),
    );
  }

  String _response(String accept, String? protocol) =>
      'HTTP/1.1 101 Switching Protocols\r\n'
      'upgrade: websocket\r\n'
      'connection: Upgrade\r\n'
      'sec-websocket-accept: $accept\r\n'
      '${protocol == null ? '' : 'sec-websocket-protocol: $protocol\r\n'}'
      '\r\n';
}
