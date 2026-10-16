import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/sse/event_stream_writer.dart';

void main() {
  const writer = EventStreamWriter();

  group('EventStreamWriter', () {
    test('writes a next event with the payload on one line', () {
      final bytes = writer.next(
        JsonObject({'data': const JsonString('a\nb')}),
      );
      expect(utf8.decode(bytes), 'event: next\ndata: {"data":"a\\nb"}\n\n');
    });

    test('writes a complete event with an empty data field', () {
      expect(utf8.decode(writer.complete()), 'event: complete\ndata:\n\n');
    });

    test('writes a comment', () {
      expect(utf8.decode(writer.comment()), ':\n\n');
    });

    test('encodes non-ASCII text as UTF-8', () {
      final bytes = writer.next(const JsonString('é'));
      expect(bytes, utf8.encode('event: next\ndata: "é"\n\n'));
    });

    test('escapes the line separators the SSE parser treats as breaks', () {
      final text = utf8.decode(writer.next(const JsonString('a\rb')));
      expect(text, 'event: next\ndata: "a\\rb"\n\n');
    });
  });
}
