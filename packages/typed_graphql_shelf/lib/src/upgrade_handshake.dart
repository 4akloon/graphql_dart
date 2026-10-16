import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

/// What the client's WebSocket upgrade request says (RFC 6455 section 4.2.1).
@internal
final class UpgradeHandshake {
  /// Reads the handshake of [_request], a `GET` with `Upgrade: websocket`.
  const UpgradeHandshake(this._request);

  final Request _request;

  /// What is wrong with the request, or null when the server can answer `101`.
  String? get problem {
    if (!_listsUpgrade()) {
      return 'The Connection header must list Upgrade.';
    }
    if (_request.headers['sec-websocket-version'] != '13') {
      return 'Only WebSocket version 13 is supported.';
    }
    if (_request.protocolVersion != '1.1') {
      return 'A WebSocket upgrade needs HTTP/1.1.';
    }
    final key = this.key;
    if (key == null) {
      return 'The Sec-WebSocket-Key header is missing.';
    }
    if (!_isNonce(key)) {
      return 'The Sec-WebSocket-Key header must be 16 bytes in base64.';
    }
    return null;
  }

  /// The `Sec-WebSocket-Key` header, which the accept value is made from.
  String? get key => _request.headers['sec-websocket-key'];

  /// The first of the offered subprotocols that is [supported], or null.
  String? subprotocol(String supported) {
    final offered = _request.headers['sec-websocket-protocol'];
    if (offered == null) return null;
    for (final candidate in offered.split(',')) {
      if (candidate.trim() == supported) return supported;
    }
    return null;
  }

  // RFC 6455 section 4.2.1: the nonce is 16 bytes, base64 encoded (24
  // characters with padding).
  bool _isNonce(String key) {
    if (key.length != 24) return false;
    try {
      return base64.decode(key).length == 16;
    } on FormatException {
      return false;
    }
  }

  bool _listsUpgrade() {
    final connection = _request.headers['connection'];
    if (connection == null) return false;
    return connection
        .toLowerCase()
        .split(',')
        .map((token) => token.trim())
        .contains('upgrade');
  }
}
