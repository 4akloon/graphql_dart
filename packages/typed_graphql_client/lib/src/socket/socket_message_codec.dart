import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'socket_message.dart';

/// Reads the text frames a server sends (R0.3): bad input is a
/// [DecodeFailure] with a path, never an exception.
///
/// Only the kinds a server sends are valid; `connection_init` and
/// `subscribe` are the client's.
@internal
final class const SocketMessageCodec() {
  /// Creates the codec.
  this;

  /// The message in [text], or why it is not one.
  DecodeResult<SocketMessage> decode(String text) =>
      switch (const JsonReader().parse(text)) {
        DecodeSuccess(value: final JsonObject message) => _read(message),
        DecodeSuccess() => const DecodeFailure('expected an object'),
        final DecodeFailure failure => failure,
      };

  DecodeResult<SocketMessage> _read(JsonObject message) =>
      switch (message['type']) {
        JsonString(:final value) => _readKind(value, message),
        null => const DecodeFailure(
          'missing "type"',
          path: [PathKey('type')],
        ),
        _ => const DecodeFailure(
          '"type" must be a string',
          path: [PathKey('type')],
        ),
      };

  DecodeResult<SocketMessage> _readKind(String kind, JsonObject message) =>
      switch (kind) {
        'connection_ack' => _withPayload(message, ConnectionAckMessage.new),
        'ping' => _withPayload(message, PingMessage.new),
        'pong' => _withPayload(message, PongMessage.new),
        'next' => _withId(message, _next),
        'error' => _withId(message, _error),
        'complete' => _withId(
          message,
          (id, _) => DecodeSuccess(CompleteMessage(id)),
        ),
        'connection_init' || 'subscribe' => DecodeFailure(
          'a server cannot send "$kind"',
          path: const [PathKey('type')],
        ),
        _ => DecodeFailure(
          'unknown message type "${_clip(kind)}"',
          path: const [PathKey('type')],
        ),
      };

  /// Server text is echoed into a message, so it is cut: a hostile server
  /// could otherwise put megabytes into every failure.
  String _clip(String text) =>
      text.length <= 100 ? text : '${text.substring(0, 100)}...';

  DecodeResult<SocketMessage> _withPayload(
    JsonObject message,
    SocketMessage Function(JsonObject? payload) create,
  ) => switch (message['payload']) {
    null || JsonNull() => DecodeSuccess(create(null)),
    final JsonObject payload => DecodeSuccess(create(payload)),
    _ => const DecodeFailure(
      '"payload" must be an object',
      path: [PathKey('payload')],
    ),
  };

  DecodeResult<SocketMessage> _withId(
    JsonObject message,
    DecodeResult<SocketMessage> Function(String id, JsonValue? payload) read,
  ) => switch (message['id']) {
    JsonString(:final value) => read(value, message['payload']),
    null => const DecodeFailure('missing "id"', path: [PathKey('id')]),
    _ => const DecodeFailure('"id" must be a string', path: [PathKey('id')]),
  };

  DecodeResult<SocketMessage> _next(String id, JsonValue? payload) {
    if (payload == null) {
      return const DecodeFailure(
        'missing "payload"',
        path: [PathKey('payload')],
      );
    }
    return switch (ResponsePayload.decode(payload)) {
      DecodeSuccess(value: final ExecutionResult result) => DecodeSuccess(
        NextMessage(id, result),
      ),
      DecodeSuccess() => const DecodeFailure(
        'a "next" payload must hold "data"',
        path: [PathKey('payload')],
      ),
      final DecodeFailure failure => failure.inside(const PathKey('payload')),
    };
  }

  DecodeResult<SocketMessage> _error(String id, JsonValue? payload) {
    if (payload is! JsonArray || payload.items.isEmpty) {
      return const DecodeFailure(
        'an "error" payload must be a list of errors, at least one',
        path: [PathKey('payload')],
      );
    }
    final errors = <GraphQLError>[];
    for (final (index, item) in payload.items.indexed) {
      switch (GraphQLError.decode(item)) {
        case DecodeSuccess(:final value):
          errors.add(value);
        case final DecodeFailure failure:
          return failure
              .inside(PathIndex(index))
              .inside(const PathKey('payload'));
      }
    }
    return DecodeSuccess(ErrorMessage(id, errors));
  }
}
