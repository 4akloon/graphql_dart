import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/sse/event_stream.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A reader of the chunks of an event stream body.
final class ChunkReader {
  ChunkReader(HttpResponseData response) {
    final body = response.body as StreamedBody;
    _subscription = body.chunks.listen(
      (chunk) => chunks.add(utf8.decode(chunk)),
    );
  }

  // Late: set in the constructor body, before anything reads it.
  late final StreamSubscription<List<int>> _subscription;
  final List<String> chunks = [];

  /// Completes when the body is done.
  Future<void> get finished => _subscription.asFuture<void>();

  Future<void> cancel() => _subscription.cancel();

  void pause() => _subscription.pause();

  void resume() => _subscription.resume();
}

const Duration _tick = Duration(milliseconds: 20);

void main() {
  late StreamController<JsonValue> source;
  late bool isSourceCancelled;
  late bool isSourcePaused;

  setUp(() {
    isSourceCancelled = false;
    isSourcePaused = false;
    source = StreamController<JsonValue>(
      onCancel: () => isSourceCancelled = true,
      onPause: () => isSourcePaused = true,
      onResume: () => isSourcePaused = false,
    );
  });

  EventStream stream({bool sendsComplete = true, Duration? keepAlive}) =>
      EventStream(
        source.stream,
        keepAliveInterval: keepAlive ?? const Duration(hours: 1),
        sendsComplete: sendsComplete,
      );

  group('EventStream', () {
    test('answers 200 with the event stream headers and no connection', () {
      final response = stream().response();
      expect(response.status, 200);
      expect(response.headers, {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
      });
    });

    test('keeps the headers an extension added', () {
      final response = stream().response(
        extraHeaders: const {'X-Extension': 'y'},
      );
      expect(response.headers['x-extension'], 'y');
    });

    test('writes a comment before anything else', () async {
      final reader = ChunkReader(stream().response());
      await Future<void>.delayed(Duration.zero);
      expect(reader.chunks, [':\n\n']);
      await reader.cancel();
    });

    test('writes a comment every keep-alive interval while idle', () async {
      final reader = ChunkReader(stream(keepAlive: _tick).response());
      while (reader.chunks.length < 3) {
        await Future<void>.delayed(_tick);
      }
      expect(reader.chunks.length, greaterThanOrEqualTo(3));
      expect(reader.chunks, everyElement(':\n\n'));
      await reader.cancel();
    });

    test('an event postpones the next keep-alive comment', () async {
      final reader = ChunkReader(
        stream(keepAlive: _tick * 10).response(),
      );
      await Future<void>.delayed(_tick * 2);
      source.add(const JsonString('x'));
      await Future<void>.delayed(_tick * 2);
      expect(reader.chunks, [':\n\n', 'event: next\ndata: "x"\n\n']);
      await reader.cancel();
    });

    test('writes the events in order and then complete', () async {
      final reader = ChunkReader(stream().response());
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

    test('ends without complete when it is not asked to send one', () async {
      final reader = ChunkReader(stream(sendsComplete: false).response());
      source.add(JsonNumber(1));
      await source.close();
      await reader.finished;
      expect(reader.chunks, [':\n\n', 'event: next\ndata: 1\n\n']);
    });

    test('ends without complete when the source fails', () async {
      final reader = ChunkReader(stream().response());
      source.addError(StateError('boom'));
      await reader.finished;
      expect(reader.chunks, [':\n\n']);
      expect(isSourceCancelled, isTrue);
    });

    test('cancelling the body cancels the source', () async {
      final reader = ChunkReader(stream().response());
      await Future<void>.delayed(Duration.zero);
      await reader.cancel();
      expect(isSourceCancelled, isTrue);
    });

    test('cancelling the body stops the keep-alive comments', () async {
      final reader = ChunkReader(stream(keepAlive: _tick).response());
      await Future<void>.delayed(_tick * 2);
      await reader.cancel();
      final seen = reader.chunks.length;
      await Future<void>.delayed(_tick * 3);
      expect(reader.chunks, hasLength(seen));
    });

    test('pausing the body pauses the source and resuming resumes', () async {
      final reader = ChunkReader(stream().response());
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
