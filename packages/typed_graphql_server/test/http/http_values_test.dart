import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('HttpRequestData', () {
    HttpRequestData request({Map<String, String> headers = const {}}) =>
        HttpRequestData(
          method: 'GET',
          uri: Uri.parse('http://localhost/graphql?query=%7Ba%7D'),
          headers: headers,
        );

    test('lower-cases the header names', () {
      expect(request(headers: {'Accept': '*/*'}).headers, {'accept': '*/*'});
    });

    test('reads a header whatever the case of the name asked for', () {
      expect(request(headers: {'x-user': 'Ada'}).header('X-User'), 'Ada');
    });

    test('answers null for a header that is absent', () {
      expect(request().header('accept'), isNull);
    });

    test('keeps the headers unmodifiable', () {
      expect(() => request().headers['a'] = 'b', throwsUnsupportedError);
    });

    test('has an empty body by default', () async {
      expect(await request().body.toList(), isEmpty);
    });

    test('keeps the source and the cancel signal it was given', () {
      final signal = CancelSignal();
      const source = Object();
      final data = HttpRequestData(
        method: 'POST',
        uri: Uri.parse('/'),
        source: source,
        cancelSignal: signal,
      );
      expect(data.source, same(source));
      expect(data.cancelSignal, same(signal));
    });
  });

  group('HttpResponseData', () {
    test('lower-cases the header names and keeps them unmodifiable', () {
      final response = HttpResponseData(204, headers: {'Allow': 'GET'});
      expect(response.headers, {'allow': 'GET'});
      expect(() => response.headers['a'] = 'b', throwsUnsupportedError);
    });

    test('has an empty fixed body by default', () {
      final body = HttpResponseData(200).body;
      expect(body, isA<FixedBody>());
      expect((body as FixedBody).bytes, isEmpty);
    });

    test('holds a streamed body', () async {
      final response = HttpResponseData(
        200,
        body: StreamedBody(Stream.value([1, 2])),
      );
      final body = response.body as StreamedBody;
      expect(await body.chunks.toList(), [
        [1, 2],
      ]);
    });
  });
}
