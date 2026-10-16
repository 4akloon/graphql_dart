import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'client_message.dart';

/// Reads the text of a frame into a [ClientMessage] (R0.3: bad input is a
/// null, never an exception).
@internal
final class ClientMessageReader {
  /// Creates a reader that accepts JSON nested at most [maxJsonDepth] deep.
  const ClientMessageReader(this.maxJsonDepth);

  /// The nesting limit of the frame's JSON.
  final int maxJsonDepth;

  /// The message in [text], or null when it is not a valid client message:
  /// not JSON, too deep, not an object, no string `type`, a field of the
  /// wrong type, or a type only a server sends. The caller closes `4400`.
  ClientMessage? read(String text) {
    final parsed = JsonReader(maxDepth: maxJsonDepth).parse(text);
    if (parsed case DecodeSuccess(value: final JsonObject json)) {
      return switch (json['type']) {
        JsonString(value: 'connection_init') => _withPayload(
          json,
          InitMessage.new,
        ),
        JsonString(value: 'ping') => _withPayload(json, PingMessage.new),
        JsonString(value: 'pong') => _withPayload(json, PongMessage.new),
        JsonString(value: 'subscribe') => _subscribe(json),
        JsonString(value: 'complete') => _complete(json),
        _ => null,
      };
    }
    return null;
  }

  ClientMessage? _withPayload(
    JsonObject json,
    ClientMessage Function(JsonObject?) create,
  ) => switch (json['payload']) {
    null || JsonNull() => create(null),
    final JsonObject payload => create(payload),
    _ => null,
  };

  ClientMessage? _subscribe(JsonObject json) {
    final id = _id(json);
    final payload = json['payload'];
    if (id == null || payload is! JsonObject) {
      return null;
    }
    return switch (GraphQLRequest.decode(payload)) {
      DecodeSuccess(value: final request) => SubscribeMessage(id, request),
      DecodeFailure() => null,
    };
  }

  ClientMessage? _complete(JsonObject json) {
    final id = _id(json);
    return id == null ? null : CompleteMessage(id);
  }

  String? _id(JsonObject json) => switch (json['id']) {
    JsonString(value: final id) when id.isNotEmpty => id,
    _ => null,
  };
}
