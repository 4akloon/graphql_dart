import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Encodes the events of GraphQL over server-sent events as UTF-8 bytes
/// (spec section 10).
@internal
final class EventStreamWriter {
  /// Creates the writer.
  const EventStreamWriter();

  /// A `next` event carrying [payload].
  ///
  /// The data is on one line because `jsonEncode` escapes every line break.
  List<int> next(JsonValue payload) =>
      utf8.encode('event: next\ndata: ${jsonEncode(payload.toJson())}\n\n');

  /// A `complete` event; its `data` is empty, but present, so that an
  /// `EventSource` fires it.
  List<int> complete() => utf8.encode('event: complete\ndata:\n\n');

  /// A comment, which clients ignore; it flushes the headers through proxies
  /// and keeps an idle connection open.
  List<int> comment() => utf8.encode(':\n\n');

  /// A `next` event of single connection mode: [payload] tagged with the id
  /// of the operation it belongs to.
  List<int> operationNext(String id, JsonValue payload) => utf8.encode(
    'event: next\ndata: ${jsonEncode({'id': id, 'payload': payload.toJson()})}'
    '\n\n',
  );

  /// A `complete` event of single connection mode: the id of the operation
  /// that has no more results.
  List<int> operationComplete(String id) =>
      utf8.encode('event: complete\ndata: ${jsonEncode({'id': id})}\n\n');
}
