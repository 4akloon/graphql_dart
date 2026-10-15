import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const csrf = CsrfPrevention();

  RequestInfo request(Map<String, String> headers, {String method = 'POST'}) =>
      RequestInfo(
        method: method,
        uri: Uri.parse('http://localhost/graphql'),
        headers: headers,
      );

  test('refuses a GET without headers', () {
    expect(csrf.allows(request({}, method: 'GET')), false);
  });

  for (final type in [
    'application/x-www-form-urlencoded',
    'multipart/form-data',
    'text/plain',
  ]) {
    test('refuses the simple type $type', () {
      expect(csrf.allows(request({'content-type': type})), false);
    });
  }

  test('refuses a simple type with parameters', () {
    final info = request({'content-type': 'text/plain; charset=utf-8'});
    expect(csrf.allows(info), false);
  });

  test('refuses a simple type in odd case', () {
    final info = request({'Content-Type': 'Text/Plain; charset=utf-8'});
    expect(csrf.allows(info), false);
  });

  test('allows application/json', () {
    expect(csrf.allows(request({'content-type': 'application/json'})), true);
  });

  test('allows application/graphql-response+json', () {
    final info = request({'content-type': 'application/graphql-response+json'});
    expect(csrf.allows(info), true);
  });

  for (final type in ['json', 'application/', 'a b/c']) {
    test('refuses the unparsable content type "$type" without a header', () {
      expect(csrf.allows(request({'content-type': type})), false);
    });
  }

  test('refuses a list of types that starts with a simple type', () {
    final info = request({'content-type': 'text/plain, application/json'});
    expect(csrf.allows(info), false);
  });

  test('refuses a list of types that ends with a simple type', () {
    final info = request({'content-type': 'application/json, text/plain'});
    expect(csrf.allows(info), false);
  });

  test('allows application/json with surrounding spaces', () {
    expect(csrf.allows(request({'content-type': ' application/json '})), true);
  });

  test('refuses text/plain with surrounding spaces', () {
    expect(csrf.allows(request({'content-type': ' text/plain '})), false);
  });

  test('refuses an empty content type', () {
    expect(csrf.allows(request({'content-type': ''})), false);
  });

  test('allows an unparsable content type with a non-empty header', () {
    final info = request({
      'content-type': 'a b/c',
      'graphql-require-preflight': '1',
    });
    expect(csrf.allows(info), true);
  });

  test('refuses an empty preflight header', () {
    expect(csrf.allows(request({'graphql-require-preflight': ''})), false);
  });

  test('refuses a whitespace-only preflight header', () {
    expect(csrf.allows(request({'graphql-require-preflight': '  '})), false);
  });

  test('allows a non-empty preflight header with text/plain', () {
    final info = request({
      'content-type': 'text/plain',
      'x-apollo-operation-name': 'Q',
    });
    expect(csrf.allows(info), true);
  });

  test('custom headers replace the defaults', () {
    const custom = CsrfPrevention(requestHeaders: ['x-my-header']);
    expect(custom.allows(request({'graphql-require-preflight': '1'})), false);
  });

  test('a custom header passes whatever its case in the list', () {
    const custom = CsrfPrevention(requestHeaders: ['X-My-Header']);
    expect(custom.allows(request({'x-my-header': '1'})), true);
  });

  test('the refusal names the headers and ends with a period', () {
    expect(
      csrf.refusal,
      endsWith(
        'headers: graphql-require-preflight, apollo-require-preflight, '
        'x-apollo-operation-name.',
      ),
    );
  });

  test('equal header lists are equal', () {
    expect(
      csrf,
      const CsrfPrevention(
        requestHeaders: [
          'graphql-require-preflight',
          'apollo-require-preflight',
          'x-apollo-operation-name',
        ],
      ),
    );
  });

  test('header lists in another order differ', () {
    expect(
      const CsrfPrevention(requestHeaders: ['x-a', 'x-b']),
      isNot(const CsrfPrevention(requestHeaders: ['x-b', 'x-a'])),
    );
  });

  test('header lists equal ignoring case', () {
    expect(
      const CsrfPrevention(requestHeaders: ['X-A']),
      const CsrfPrevention(requestHeaders: ['x-a']),
    );
  });

  test('with no headers, only a preflighting content type passes', () {
    const strict = CsrfPrevention(requestHeaders: []);
    expect(strict.allows(request({'content-type': 'application/json'})), true);
    expect(strict.allows(request({'x-apollo-operation-name': 'Q'})), false);
  });

  test('with no headers, the refusal names no header', () {
    const strict = CsrfPrevention(requestHeaders: []);
    expect(strict.refusal, endsWith('multipart/form-data, text/plain.'));
  });

  test('different header lists differ', () {
    expect(csrf, isNot(const CsrfPrevention(requestHeaders: ['x-a'])));
  });
}
