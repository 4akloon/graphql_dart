@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

import 'support/end_to_end_fixture.dart';
import 'support/loopback_server.dart';

void main() {
  late EndToEndFixture fixture;
  late LoopbackServer server;
  late HttpClient client;
  late Directory directory;

  // Waits for the server to catch up with an event the test cannot observe;
  // the test's own timeout is the deadline.
  Future<void> until(bool Function() isDone) async {
    while (!isDone()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    fixture = EndToEndFixture();
    client = HttpClient();
    directory = Directory.systemTemp.createTempSync('typed_graphql_e2e_');
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    await fixture.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> serve({
    ServerProfile profile = ServerProfile.development,
    HttpOptions http = const HttpOptions(),
  }) async {
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(
        fixture.server(profile: profile),
        http: http,
      ).call,
    );
  }

  Future<(HttpClientResponse, String)> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) async {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    request.add(body);
    final response = await request.close();
    return (response, await utf8.decodeStream(response));
  }

  Future<(HttpClientResponse, String)> post(
    String query, {
    Map<String, String> headers = const {},
  }) => send(
    'POST',
    server.httpUri,
    headers: {'content-type': 'application/json', ...headers},
    body: utf8.encode(jsonEncode({'query': query})),
  );

  test('answers a JSON query over POST', () async {
    await serve();
    final (response, body) = await post('{ hello }');
    expect(response.statusCode, 200);
    expect(jsonDecode(body), {
      'data': {'hello': 'world'},
    });
  });

  test('answers a query over GET', () async {
    await serve();
    final uri = server.httpUri.replace(
      queryParameters: {'query': '{ hello }'},
    );
    final (response, body) = await send(
      'GET',
      uri,
      headers: {'graphql-require-preflight': 'true'},
    );
    expect(response.statusCode, 200);
    expect(jsonDecode(body), {
      'data': {'hello': 'world'},
    });
  });

  test(
    'sends status 294 for a partial result under graphql-response+json',
    () async {
      await serve();
      final (response, _) = await post(
        '{ hello broken }',
        headers: {'accept': 'application/graphql-response+json'},
      );
      expect(response.statusCode, 294);
    },
  );

  test('refuses a body larger than the limit with 413', () async {
    await serve(http: const HttpOptions(maxBodyBytes: 64));
    final (response, _) = await post('{ hello ${'x' * 200} }');
    expect(response.statusCode, 413);
  });

  Future<void> serveUploads(UploadLimits limits) async {
    final uploads = Uploads(
      storage: TempFileUploadStorage(directory: directory),
      limits: limits,
    );
    await fixture.close();
    fixture = EndToEndFixture(uploads: uploads);
    await serve(http: HttpOptions(uploads: uploads));
  }

  Future<(HttpClientResponse, String)> upload(
    String filename,
    String content,
  ) {
    const boundary = 'e2eBoundary';
    final body = [
      '--$boundary',
      'content-disposition: form-data; name="operations"',
      '',
      jsonEncode({
        'query': r'mutation ($file: Upload!) { upload(file: $file) }',
        'variables': {'file': null},
      }),
      '--$boundary',
      'content-disposition: form-data; name="map"',
      '',
      '{"0":["variables.file"]}',
      '--$boundary',
      'content-disposition: form-data; name="0"; filename="$filename"',
      'content-type: text/plain',
      '',
      content,
      '--$boundary--',
      '',
    ].join('\r\n');
    return send(
      'POST',
      server.httpUri,
      headers: {
        'content-type': 'multipart/form-data; boundary=$boundary',
        'graphql-require-preflight': 'true',
      },
      body: utf8.encode(body),
    );
  }

  test('stores an uploaded file and releases it after the response', () async {
    await serveUploads(const UploadLimits());
    final (response, answer) = await upload('notes.txt', 'hello');
    expect(response.statusCode, 200);
    expect(jsonDecode(answer), {
      'data': {'upload': 'notes.txt: hello'},
    });
    expect(directory.listSync(), isEmpty);
  });

  test('keeps a path-like upload file name out of the file system', () async {
    await serveUploads(const UploadLimits());
    final (response, answer) = await upload('../../escape.txt', 'hi');
    expect(response.statusCode, 200);
    expect(jsonDecode(answer), {
      'data': {'upload': '../../escape.txt: hi'},
    });
    expect(directory.listSync(), isEmpty);
    expect(
      File('${directory.parent.parent.path}/escape.txt').existsSync(),
      isFalse,
    );
  });

  test('leaves no file behind when an upload is over its limit', () async {
    await serveUploads(const UploadLimits(maxFileBytes: 8));
    final (response, _) = await upload('big.txt', 'x' * 100);
    expect(response.statusCode, 413);
    expect(directory.listSync(), isEmpty);
  });

  test('removes the file of an upload whose client disconnects', () async {
    await serveUploads(const UploadLimits());
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    const boundary = 'cutBoundary';
    final head = [
      '--$boundary',
      'content-disposition: form-data; name="operations"',
      '',
      jsonEncode({
        'query': r'mutation ($file: Upload!) { upload(file: $file) }',
        'variables': {'file': null},
      }),
      '--$boundary',
      'content-disposition: form-data; name="map"',
      '',
      '{"0":["variables.file"]}',
      '--$boundary',
      'content-disposition: form-data; name="0"; filename="cut.txt"',
      'content-type: text/plain',
      '',
      'the first bytes of a file that never ends',
    ].join('\r\n');
    socket.write(
      'POST /graphql HTTP/1.1\r\n'
      'host: 127.0.0.1\r\n'
      'content-type: multipart/form-data; boundary=$boundary\r\n'
      'graphql-require-preflight: true\r\n'
      'content-length: ${head.length + 100000}\r\n'
      '\r\n'
      '$head',
    );
    await socket.flush();
    await until(() => directory.listSync().isNotEmpty);
    socket.destroy();
    await until(() => directory.listSync().isEmpty);
  });

  test('answers a batch of two queries with two results', () async {
    await serve(http: const HttpOptions(batching: BatchPolicy()));
    final (response, body) = await send(
      'POST',
      server.httpUri,
      headers: {'content-type': 'application/json'},
      body: utf8.encode(
        jsonEncode([
          {'query': '{ hello }'},
          {'query': '{ __typename }'},
        ]),
      ),
    );
    expect(response.statusCode, 200);
    expect(jsonDecode(body), [
      {
        'data': {'hello': 'world'},
      },
      {
        'data': {'__typename': 'Query'},
      },
    ]);
  });

  test('serves the GraphiQL page to a browser in development', () async {
    await serve();
    final (response, body) = await send(
      'GET',
      server.httpUri,
      headers: {'accept': 'text/html'},
    );
    expect(
      (response.statusCode, response.headers.contentType?.mimeType),
      (
        200,
        'text/html',
      ),
    );
    expect(body, contains('GraphiQL'));
  });

  test('does not serve the GraphiQL page in production', () async {
    await serve(profile: ServerProfile.production);
    final (response, _) = await send(
      'GET',
      server.httpUri,
      headers: {'accept': 'text/html'},
    );
    expect(response.headers.contentType?.mimeType, isNot('text/html'));
  });
}
