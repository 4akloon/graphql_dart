import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/src/response_conversion.dart';

void main() {
  const conversion = ResponseConversion();

  test('keeps the status', () {
    expect(conversion.convert(HttpResponseData(405)).statusCode, 405);
  });

  test('keeps the headers', () {
    final response = conversion.convert(
      HttpResponseData(200, headers: const {'allow': 'GET, POST'}),
    );
    expect(response.headers['allow'], 'GET, POST');
  });

  test('writes a fixed body with its length', () async {
    final response = conversion.convert(
      HttpResponseData(200, body: FixedBody(utf8.encode('{"a":1}'))),
    );
    expect(await response.readAsString(), '{"a":1}');
    expect(response.contentLength, 7);
  });

  test('writes a streamed body chunk by chunk', () async {
    final chunks = StreamController<List<int>>();
    final response = conversion.convert(
      HttpResponseData(200, body: StreamedBody(chunks.stream)),
    );
    final seen = <String>[];
    final done = response.read().map(utf8.decode).forEach(seen.add);
    chunks.add(utf8.encode('one'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen, ['one']);
    chunks.add(utf8.encode('two'));
    await chunks.close();
    await done;
    expect(seen, ['one', 'two']);
  });

  test('asks shelf_io not to buffer a streamed body', () {
    final response = conversion.convert(
      HttpResponseData(200, body: const StreamedBody(Stream.empty())),
    );
    expect(response.context['shelf.io.buffer_output'], false);
  });

  test('leaves a fixed body to the default buffering', () {
    final response = conversion.convert(HttpResponseData(200));
    expect(response.context.containsKey('shelf.io.buffer_output'), false);
  });
}
