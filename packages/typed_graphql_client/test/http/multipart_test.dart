import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_transport.dart';

/// Draws 0 every time, so every boundary is 32 `A`s.
final class ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

void main() {
  final boundary = 'A' * 32;
  late FakeTransport transport;

  setUp(() => transport = FakeTransport()..answer('{"data":{"upload":true}}'));

  HttpLink link({bool usesGetForQueries = false}) => HttpLink(
    uri: Uri.parse('https://example.com/graphql'),
    transport: transport,
    usesGetForQueries: usesGetForQueries,
    random: ZeroRandom(),
  );

  LinkRequest upload(
    JsonObject variables,
    List<UploadFile> files, {
    OperationType type = OperationType.mutation,
  }) => LinkRequest(
    document: OperationDocument(
      name: 'Upload',
      type: type,
      text: r'mutation Upload($file:Upload!){upload(file:$file)}',
      sha256: '0' * 64,
    ),
    variables: variables,
    context: LinkContext([UploadFiles(files)]),
  );

  Future<List<LinkResult>> send(HttpLink link, LinkRequest request) =>
      link.request(request, (request) => const Stream.empty()).toList();

  test('writes the operations, the map and the file as parts', () async {
    final file = UploadFile.fromBytes(
      utf8.encode('hello'),
      filename: 'a.txt',
      contentType: 'text/plain',
    );
    await send(
      link(),
      upload(JsonObject({'file': JsonString(file.marker)}), [file]),
    );
    expect(
      transport.bodies.single,
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="operations"\r\n'
      'Content-Type: application/json\r\n'
      '\r\n'
      r'{"query":"mutation Upload($file:Upload!){upload(file:$file)}",'
      '"operationName":"Upload","variables":{"file":null}}\r\n'
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="map"\r\n'
      'Content-Type: application/json\r\n'
      '\r\n'
      '{"0":["variables.file"]}\r\n'
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="0"; filename="a.txt"\r\n'
      'Content-Type: text/plain\r\n'
      '\r\n'
      'hello\r\n'
      '--$boundary--\r\n',
    );
  });

  test('sends a POST with the boundary, the length and the preflight '
      'header', () async {
    final file = UploadFile.fromBytes([1, 2, 3], filename: 'a.bin');
    await send(
      link(),
      upload(JsonObject({'file': JsonString(file.marker)}), [file]),
    );
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.headers['content-type'],
      'multipart/form-data; boundary=$boundary',
    );
    expect(request.headers['graphql-require-preflight'], 'true');
    expect(request.contentLength, utf8.encode(transport.bodies.single).length);
  });

  test('lists a file used twice with both paths and numbers files in the '
      'order given', () async {
    final first = UploadFile.fromBytes([1], filename: 'a');
    final second = UploadFile.fromBytes([2], filename: 'b');
    await send(
      link(),
      upload(
        JsonObject({
          'files': JsonArray([
            JsonString(second.marker),
            JsonString(first.marker),
          ]),
          'again': JsonObject({'file': JsonString(first.marker)}),
        }),
        [first, second],
      ),
    );
    expect(
      transport.bodies.single,
      contains(
        '{"0":["variables.files.1","variables.again.file"],'
        '"1":["variables.files.0"]}',
      ),
    );
  });

  test('escapes quotes and line ends in a file name', () async {
    final file = UploadFile.fromBytes([1], filename: 'a"b\r\nc');
    await send(
      link(),
      upload(JsonObject({'file': JsonString(file.marker)}), [file]),
    );
    expect(transport.bodies.single, contains('filename="a%22b%0D%0Ac"'));
  });

  test('streams a file opened for the request', () async {
    var openCount = 0;
    final file = UploadFile.fromStream(
      () {
        openCount++;
        return Stream.fromIterable([
          [104, 105],
          [33],
        ]);
      },
      length: 3,
      filename: 'a.txt',
    );
    await send(
      link(),
      upload(JsonObject({'file': JsonString(file.marker)}), [file]),
    );
    expect(openCount, 1);
    expect(transport.bodies.single, contains('\r\n\r\nhi!\r\n'));
  });

  test('sends a query with files as a POST, never a GET', () async {
    final file = UploadFile.fromBytes([1], filename: 'a');
    await send(
      link(usesGetForQueries: true),
      upload(
        JsonObject({'file': JsonString(file.marker)}),
        [file],
        type: OperationType.query,
      ),
    );
    expect(transport.requests.single.method, 'POST');
  });

  test('refuses a marker the context does not list', () {
    final listed = UploadFile.fromBytes([1], filename: 'a');
    final unlisted = UploadFile.fromBytes([2], filename: 'b');
    expect(
      send(
        link(),
        upload(
          JsonObject({
            'a': JsonString(listed.marker),
            'b': JsonString(unlisted.marker),
          }),
          [listed],
        ),
      ),
      throwsArgumentError,
    );
  });

  test('refuses a listed file no variable holds', () {
    final file = UploadFile.fromBytes([1], filename: 'a');
    expect(
      send(link(), upload(JsonObject(const {}), [file])),
      throwsArgumentError,
    );
  });
}
