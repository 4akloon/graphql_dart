import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  http.StreamedResponse answer(String body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  test('sends the method, URL, headers and body', () async {
    late http.BaseRequest received;
    late List<int> receivedBody;
    final transport = PackageHttpTransport(
      MockClient.streaming((request, body) async {
        received = request;
        receivedBody = await body.toBytes();
        return answer('{}');
      }),
    );
    await transport.send(
      TransportRequest(
        method: 'POST',
        uri: Uri.parse('https://example.com/graphql'),
        headers: {'Content-Type': 'application/json'},
        body: Stream.value(utf8.encode('{"query":"{a}"}')),
        contentLength: 15,
      ),
    );
    expect(received.method, 'POST');
    expect(received.url, Uri.parse('https://example.com/graphql'));
    expect(received.headers, {'content-type': 'application/json'});
    expect(received.contentLength, 15);
    expect(utf8.decode(receivedBody), '{"query":"{a}"}');
  });

  test('sends a request without a body with an empty one', () async {
    late List<int> receivedBody;
    final transport = PackageHttpTransport(
      MockClient.streaming((request, body) async {
        receivedBody = await body.toBytes();
        return answer('{}');
      }),
    );
    await transport.send(
      TransportRequest(method: 'GET', uri: Uri.parse('https://example.com')),
    );
    expect(receivedBody, isEmpty);
  });

  test('hands the abort trigger to an abortable request', () async {
    late http.BaseRequest received;
    final transport = PackageHttpTransport(
      MockClient.streaming((request, body) async {
        received = request;
        return answer('{}');
      }),
    );
    final abort = Completer<void>();
    await transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://example.com'),
        abortTrigger: abort.future,
      ),
    );
    expect(received, isA<http.AbortableStreamedRequest>());
    expect((received as http.Abortable).abortTrigger, same(abort.future));
  });

  test('answers with the status, headers and body', () async {
    final transport = PackageHttpTransport(
      MockClient.streaming(
        (request, body) async => answer('{"a":1}', status: 201),
      ),
    );
    final response = await transport.send(
      TransportRequest(method: 'GET', uri: Uri.parse('https://example.com')),
    );
    expect(response.statusCode, 201);
    expect(response.headers, {'content-type': 'application/json'});
    expect(
      utf8.decode(await response.body.expand((chunk) => chunk).toList()),
      '{"a":1}',
    );
  });

  test('lets an exception of the client through', () {
    final transport = PackageHttpTransport(
      MockClient.streaming(
        (request, body) async => throw http.ClientException('refused'),
      ),
    );
    expect(
      transport.send(
        TransportRequest(method: 'GET', uri: Uri.parse('https://example.com')),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('lower-cases the header names of a request and a response', () {
    final request = TransportRequest(
      method: 'GET',
      uri: Uri.parse('https://example.com'),
      headers: {'X-Trace': 'a'},
    );
    final response = TransportResponse(
      statusCode: 200,
      headers: {'Content-Type': 'text/plain'},
      body: const Stream.empty(),
    );
    expect(request.headers, {'x-trace': 'a'});
    expect(response.headers, {'content-type': 'text/plain'});
  });
}
