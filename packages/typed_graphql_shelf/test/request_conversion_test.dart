import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_shelf/src/request_conversion.dart';

void main() {
  const conversion = RequestConversion();

  Request request({
    String method = 'POST',
    String url = 'http://example.test/graphql?a=1',
    Map<String, Object> headers = const {},
    Object? body,
  }) => Request(method, Uri.parse(url), headers: headers, body: body);

  test('keeps the method', () {
    expect(conversion.convert(request(method: 'GET')).method, 'GET');
  });

  test('uses the requested URI with its query', () {
    final data = conversion.convert(request());
    expect(data.uri, Uri.parse('http://example.test/graphql?a=1'));
  });

  test('lower-cases header names', () {
    final data = conversion.convert(request(headers: {'Content-Type': 'x/y'}));
    expect(data.headers['content-type'], 'x/y');
    expect(data.headers.keys.every((name) => name == name.toLowerCase()), true);
  });

  test('joins repeated header values with a comma and a space', () {
    final data = conversion.convert(
      request(
        headers: {
          'Accept': ['text/html', 'application/json'],
        },
      ),
    );
    expect(data.header('accept'), 'text/html, application/json');
  });

  test('reads the body as bytes', () async {
    final data = conversion.convert(request(body: 'hello'));
    expect(
      utf8.decode(await data.body.expand((chunk) => chunk).toList()),
      'hello',
    );
  });

  test('hands the shelf request over as the source', () {
    final original = request();
    expect(conversion.convert(original).source, same(original));
  });

  test('gives no cancel signal, because shelf reports no disconnect', () {
    expect(conversion.convert(request()).cancelSignal, isNull);
  });
}
