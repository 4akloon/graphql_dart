import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_client/src/sse/event_stream_error.dart';
import 'package:typed_graphql_client/src/sse/event_stream_parser.dart';
import 'package:typed_graphql_client/src/sse/server_sent_event.dart';

void main() {
  const parser = EventStreamParser(maxEventBytes: 1024);

  Future<List<ServerSentEvent>> parseChunks(
    List<List<int>> chunks, [
    EventStreamParser using = parser,
  ]) => using.parse(Stream.fromIterable(chunks)).toList();

  Future<List<ServerSentEvent>> parse(String text) =>
      parseChunks([utf8.encode(text)]);

  List<(String, String)> pairs(List<ServerSentEvent> events) => [
    for (final event in events) (event.event, event.data),
  ];

  group('an event', () {
    test('is dispatched by a blank line', () async {
      expect(pairs(await parse('event: next\ndata: 1\n\n')), [('next', '1')]);
    });

    test('has the type message when the stream names none', () async {
      expect(pairs(await parse('data: 1\n\n')), [('message', '1')]);
    });

    test('joins data lines with a line feed', () async {
      expect(pairs(await parse('data: a\ndata: b\ndata:\ndata: c\n\n')), [
        ('message', 'a\nb\n\nc'),
      ]);
    });

    test('removes one leading space of the value only', () async {
      expect(pairs(await parse('data:  a\n\n')), [('message', ' a')]);
      expect(pairs(await parse('data:a\n\n')), [('message', 'a')]);
    });

    test('keeps a colon inside the value', () async {
      expect(pairs(await parse('data: a:b\n\n')), [('message', 'a:b')]);
    });

    test('treats a line without a colon as a field with no value', () async {
      expect(pairs(await parse('data\ndata\n\n')), [('message', '\n')]);
    });

    test('is dispatched with an event type and no data', () async {
      expect(pairs(await parse('event: complete\n\n')), [('complete', '')]);
      expect(pairs(await parse('event: complete\ndata: \n\n')), [
        ('complete', ''),
      ]);
    });

    test('is not dispatched when it has neither type nor data', () async {
      expect(await parse('id: 1\nretry: 10\nfoo: bar\n\n'), isEmpty);
      expect(await parse('\n\n\n'), isEmpty);
    });

    test('ignores id, retry and unknown fields', () async {
      expect(pairs(await parse('id: 7\nretry: 5\nx: y\ndata: 1\n\n')), [
        ('message', '1'),
      ]);
    });

    test('forgets the type after a dispatch', () async {
      expect(pairs(await parse('event: a\ndata: 1\n\ndata: 2\n\n')), [
        ('a', '1'),
        ('message', '2'),
      ]);
    });

    test('is lost when the stream ends before its blank line', () async {
      expect(await parse('data: 1\n'), isEmpty);
      expect(await parse('data: 1'), isEmpty);
    });
  });

  group('a chunk that fails', () {
    Future<(List<ServerSentEvent>, Object?)> collect(
      List<List<int>> chunks,
      EventStreamParser using,
    ) async {
      final events = <ServerSentEvent>[];
      Object? error;
      final done = Completer<void>();
      using
          .parse(Stream.fromIterable(chunks))
          .listen(
            events.add,
            onError: (Object e) => error ??= e,
            onDone: done.complete,
          );
      await done.future;
      return (events, error);
    }

    test('still yields the events completed before an invalid byte', () async {
      final (events, error) = await collect([
        [...utf8.encode('event: next\ndata: 1\n\n'), 0xFF],
      ], parser);
      expect(pairs(events), [('next', '1')]);
      expect(error, isA<EventStreamNotUtf8>());
    });

    test(
      'still yields the events completed before an oversized line',
      () async {
        final (events, error) = await collect([
          utf8.encode('event: next\ndata: 1\n\n${'x' * 30}'),
        ], const EventStreamParser(maxEventBytes: 20));
        expect(pairs(events), [('next', '1')]);
        expect(error, isA<EventStreamTooLarge>());
      },
    );
  });

  group('an event with no type', () {
    test('and empty data is ignored', () async {
      expect(await parse('data:\n\n'), isEmpty);
      expect(await parse('event\n\n'), isEmpty);
      expect(await parse('event:\ndata\n\n'), isEmpty);
    });

    test('and data is a message', () async {
      expect(pairs(await parse('data: x\n\n')), [('message', 'x')]);
    });
  });

  group('comments', () {
    test('are skipped', () async {
      expect(pairs(await parse(': ping\ndata: 1\n:\n\n')), [('message', '1')]);
    });

    test('do not dispatch an event', () async {
      expect(await parse(': ping\n\n'), isEmpty);
    });
  });

  group('line ends', () {
    test('may be CRLF, LF or CR', () async {
      expect(pairs(await parse('data: a\r\ndata: b\ndata: c\r\r')), [
        ('message', 'a\nb\nc'),
      ]);
    });

    test('count a CR then LF across two chunks once', () async {
      final events = await parseChunks([
        utf8.encode('data: a\r'),
        utf8.encode('\ndata: b\r\n\r'),
        utf8.encode('\n'),
      ]);
      expect(pairs(events), [('message', 'a\nb')]);
    });
  });

  group('text', () {
    test('drops a BOM at the start', () async {
      expect(pairs(await parse('\u{FEFF}data: 1\n\n')), [('message', '1')]);
    });

    test('keeps multi-byte characters', () async {
      expect(pairs(await parse('data: h\u00e9llo \u{1F600}\n\n')), [
        ('message', 'h\u00e9llo \u{1F600}'),
      ]);
    });

    test('is split at every byte boundary', () async {
      final bytes = utf8.encode(
        '\u{FEFF}: c\r\nevent: next\r\ndata: h\u00e9\u20ac\u{1F600}\r\n'
        'data: b\r\n\r\nevent: complete\ndata:\n\n',
      );
      for (var cut = 0; cut <= bytes.length; cut++) {
        final events = await parseChunks([
          bytes.sublist(0, cut),
          bytes.sublist(cut),
        ]);
        expect(pairs(events), [
          ('next', 'h\u00e9\u20ac\u{1F600}\nb'),
          ('complete', ''),
        ], reason: 'cut at $cut');
      }
    });

    test('is read one byte per chunk', () async {
      final bytes = utf8.encode('data: \u00e9\u{1F600}\n\n');
      final events = await parseChunks([
        for (final byte in bytes) [byte],
      ]);
      expect(pairs(events), [('message', '\u00e9\u{1F600}')]);
    });

    test('fails on invalid UTF-8', () async {
      await expectLater(
        parseChunks([
          [0x64, 0x61, 0xFF, 0x0A, 0x0A],
        ]),
        throwsA(
          isA<EventStreamNotUtf8>(),
        ),
      );
    });

    test('fails on a character cut off at the end', () async {
      await expectLater(
        parseChunks([
          [0x64, 0xE2, 0x82],
        ]),
        throwsA(
          isA<EventStreamNotUtf8>(),
        ),
      );
    });
  });

  group('the limit', () {
    const small = EventStreamParser(maxEventBytes: 20);

    Matcher tooLarge() => throwsA(
      isA<EventStreamTooLarge>(),
    );

    test('stops a line that never ends', () async {
      await expectLater(
        parseChunks([utf8.encode('x' * 21)], small),
        tooLarge(),
      );
    });

    test('stops an event with many data lines', () async {
      await expectLater(
        parseChunks([utf8.encode('data: abcdef\n' * 3)], small),
        tooLarge(),
      );
    });

    test('counts bytes, not characters', () async {
      await expectLater(
        parseChunks([utf8.encode('data: ${'\u20ac' * 5}')], small),
        tooLarge(),
      );
    });

    test('lets an event of exactly the limit through', () async {
      final events = await parseChunks([
        utf8.encode('data: 0123456789\n\n'),
      ], small);
      expect(pairs(events), [('message', '0123456789')]);
    });

    test('counts one event at a time', () async {
      final events = await parseChunks([
        utf8.encode('data: 0123456789\n\n' * 5),
      ], small);
      expect(events, hasLength(5));
    });

    test('does not count comments', () async {
      final events = await parseChunks([
        utf8.encode('${': ping\n' * 100}data: 1\n\n'),
      ], small);
      expect(pairs(events), [('message', '1')]);
    });

    test('cancels the body when it stops', () async {
      var isCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => isCancelled = true,
      )..add(utf8.encode('x' * 30));
      await expectLater(small.parse(body.stream).toList(), tooLarge());
      expect(isCancelled, isTrue);
      await body.close();
    });
  });

  test('passes an error of the body stream on unchanged', () async {
    final failure = Exception('boom');
    final body = Stream<List<int>>.fromFuture(Future.error(failure));
    await expectLater(parser.parse(body).toList(), throwsA(same(failure)));
  });
}
