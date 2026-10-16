import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/sse/event_stream.dart';

import 'support/manual_timers.dart';
import 'support/sse_fixture.dart';

const Duration _keepAlive = Duration(seconds: 15);

void main() {
  late StreamController<JsonValue> source;
  late bool isSourceCancelled;
  late bool isSourcePaused;
  late ManualTimers timers;

  setUp(() {
    timers = ManualTimers();
    isSourceCancelled = false;
    isSourcePaused = false;
    source = StreamController<JsonValue>(
      onCancel: () => isSourceCancelled = true,
      onPause: () => isSourcePaused = true,
      onResume: () => isSourcePaused = false,
    );
  });

  EventStream stream() =>
      EventStream(source.stream, keepAliveInterval: _keepAlive);

  group('EventStream', () {
    test('answers 200 with the event stream headers and no connection', () {
      final response = stream().response();
      expect(response.status, 200);
      expect(response.headers, {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
        'vary': 'accept',
      });
    });

    test('keeps the headers an extension added', () {
      final response = stream().response(
        extraHeaders: const {'X-Extension': 'y'},
      );
      expect(response.headers['x-extension'], 'y');
    });

    test('writes a comment before anything else', () async {
      final reader = StreamReader(stream().response());
      await Future<void>.delayed(Duration.zero);
      expect(reader.chunks, [':\n\n']);
      await reader.cancel();
    });

    test('writes a comment every keep-alive interval while idle', () async {
      await timers.run(() async {
        final reader = StreamReader(stream().response());
        await timers.settle();
        for (var i = 0; i < 3; i++) {
          timers.armed.single.fire();
          await timers.settle();
        }
        expect(reader.chunks, [':\n\n', ':\n\n', ':\n\n', ':\n\n']);
        expect(timers.armed.single.duration, _keepAlive);
        await reader.cancel();
      });
    });

    test('an event cancels the armed keep-alive and arms another', () async {
      await timers.run(() async {
        final reader = StreamReader(stream().response());
        await timers.settle();
        final first = timers.armed.single;
        source.add(const JsonString('x'));
        await timers.settle();
        expect(first.isActive, isFalse);
        expect(timers.armed, hasLength(1));
        expect(reader.chunks, [':\n\n', 'event: next\ndata: "x"\n\n']);
        await reader.cancel();
      });
    });

    test('writes no keep-alive comment while the client is paused', () async {
      await timers.run(() async {
        final reader = StreamReader(stream().response());
        await timers.settle();
        reader.pause();
        timers.armed.single.fire();
        await timers.settle();
        expect(reader.chunks, [':\n\n']);
        expect(timers.armed, hasLength(1));
        reader.resume();
        timers.armed.single.fire();
        await timers.settle();
        expect(reader.chunks, [':\n\n', ':\n\n']);
        await reader.cancel();
      });
    });

    test('writes the events in order and then complete', () async {
      final reader = StreamReader(stream().response());
      source
        ..add(JsonNumber(1))
        ..add(JsonNumber(2));
      await source.close();
      await reader.finished;
      expect(reader.chunks, [
        ':\n\n',
        'event: next\ndata: 1\n\n',
        'event: next\ndata: 2\n\n',
        'event: complete\ndata:\n\n',
      ]);
    });

    test('a frames stream ends without complete', () async {
      final frames = StreamController<List<int>>();
      final reader = StreamReader(
        EventStream.frames(
          frames.stream,
          keepAliveInterval: _keepAlive,
        ).response(),
      );
      frames.add([65]);
      await frames.close();
      await reader.finished;
      expect(reader.chunks, [':\n\n', 'A']);
    });

    test('ends without complete when the source fails', () async {
      final reader = StreamReader(stream().response());
      source.addError(StateError('boom'));
      await reader.finished;
      expect(reader.chunks, [':\n\n']);
      expect(isSourceCancelled, isTrue);
    });

    test('cancelling the body cancels the source', () async {
      final reader = StreamReader(stream().response());
      await Future<void>.delayed(Duration.zero);
      await reader.cancel();
      expect(isSourceCancelled, isTrue);
    });

    test('cancelling the body cancels the armed keep-alive', () async {
      await timers.run(() async {
        final reader = StreamReader(stream().response());
        await timers.settle();
        await reader.cancel();
        expect(timers.armed, isEmpty);
      });
    });

    test('pausing the body pauses the source and resuming resumes', () async {
      final reader = StreamReader(stream().response());
      await Future<void>.delayed(Duration.zero);
      reader.pause();
      expect(isSourcePaused, isTrue);
      reader.resume();
      expect(isSourcePaused, isFalse);
      await reader.cancel();
    });

    test('does not listen to the source before the body is listened', () {
      stream().response();
      expect(source.hasListener, isFalse);
    });
  });
}
