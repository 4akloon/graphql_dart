import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Writes the graphql-ws messages a server sends, as the text of a frame.
///
/// The keys are in the order `type`, `id`, `payload`, which `jsonEncode`
/// keeps.
@internal
final class ServerMessages {
  /// Creates the writer.
  const ServerMessages();

  /// `connection_ack`, with [payload] when it is not null.
  String ack(JsonObject? payload) => _write('connection_ack', payload: payload);

  /// `pong`, with [payload] when it is not null.
  String pong(JsonObject? payload) => _write('pong', payload: payload);

  /// `next`: one execution [result] of operation [id].
  String next(String id, ExecutionResult result) =>
      _write('next', id: id, payload: result.toJson());

  /// `error`: the [errors] that stopped operation [id] before it ran.
  String error(String id, List<GraphQLError> errors) => _write(
    'error',
    id: id,
    payload: JsonArray([for (final error in errors) error.toJson()]),
  );

  /// `complete`: operation [id] has no more results.
  String complete(String id) => _write('complete', id: id);

  String _write(String type, {String? id, JsonValue? payload}) => jsonEncode(
    JsonObject({
      'type': JsonString(type),
      if (id != null) 'id': JsonString(id),
      'payload': ?payload,
    }).toJson(),
  );
}
