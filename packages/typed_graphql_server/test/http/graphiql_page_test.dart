import 'package:test/test.dart';
import 'package:typed_graphql_server/src/http/graphiql_page.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();
  const browser = {
    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  // A GET without a query that passes CSRF prevention, so a refusal is the
  // pipeline's GQL400 and not GQL403.
  HttpRequestData getWithoutQuery(String accept) => http.get(
    const {},
    headers: {...HttpFixture.preflight, 'accept': accept},
  );

  Future<String> pageOf(String path) =>
      http.text(const GraphiQLPage().response(path));

  group('the page', () {
    test('names React with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'src="https://cdn.jsdelivr.net/npm/react@18.3.1/umd/'
          'react.production.min.js" '
          'integrity="sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiD'
          'rcHkMLKI6fiB/Z" crossorigin="anonymous"',
        ),
      );
    });

    test('names ReactDOM with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'src="https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/'
          'react-dom.production.min.js" '
          'integrity="sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVd'
          'sSH1fSDUf5YJj1" crossorigin="anonymous"',
        ),
      );
    });

    test('names the GraphiQL style with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'href="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/'
          'graphiql.min.css" '
          'integrity="sha384-QMux00XgRtwRLSYIY3kw2rj1ovk5AuuliAchk+HSQbqdbGFnz9'
          'GYuqIlOqxhwCE2" crossorigin="anonymous"',
        ),
      );
    });

    test('names the GraphiQL script with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'src="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/'
          'graphiql.min.js" '
          'integrity="sha384-8NGfVj4CVlqHajlZj+bPJT4thxPMHMJYn7DWK2CvtopLd02E7q'
          'sPHazniBYvVjOO" crossorigin="anonymous"',
        ),
      );
    });

    test('loads no script from anywhere else', () async {
      final html = await pageOf('/graphql');
      final sources = RegExp(
        '(?:src|href)="(https?:[^"]*)"',
      ).allMatches(html).map((match) => match.group(1)!);
      expect(
        sources.every((url) => url.startsWith('https://cdn.jsdelivr.net/npm/')),
        true,
      );
      expect(sources, hasLength(4));
    });

    test('posts to the endpoint with the response types', () async {
      final html = await pageOf('/graphql');
      expect(html, contains('const endpoint = "/graphql";'));
      expect(html, contains("method: 'POST'"));
      expect(html, contains("'content-type': 'application/json'"));
      expect(
        html,
        contains(
          'accept: '
          "'application/graphql-response+json, application/json;q=0.9'",
        ),
      );
      expect(html, contains('React.createElement(GraphiQL, {fetcher})'));
    });

    test('escapes what could close the script or end the line', () async {
      final html = await pageOf('/</script>&\u2028\u2029');
      expect(
        html,
        contains(
          r'const endpoint = "/\u003c/script\u003e\u0026\u2028\u2029";',
        ),
      );
      expect(html, isNot(contains('/</script>')));
      expect(html, isNot(contains('\u2028')));
      expect(html, isNot(contains('\u2029')));
    });

    test('has the security headers', () {
      final response = const GraphiQLPage().response('/graphql');
      expect(response.status, 200);
      expect(response.headers, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'vary': 'accept',
        'x-content-type-options': 'nosniff',
        'referrer-policy': 'no-referrer',
        'x-frame-options': 'DENY',
      });
    });
  });

  group('the handler', () {
    test('serves the page to a browser in development', () async {
      final response = await http.handler().handle(
        http.get(const {}, headers: browser),
      );
      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(
        await http.text(response),
        contains('const endpoint = "/graphql"'),
      );
    });

    test('does not serve the page in production', () async {
      final response = await http
          .handler(profile: ServerProfile.production)
          .handle(http.get(const {}, headers: browser));
      expect(response.headers['content-type'], isNot(contains('text/html')));
      expect(await http.code(response), 'GQL403');
    });

    test('answers a production browser without a query as before', () async {
      final response = await http
          .handler(profile: ServerProfile.production)
          .handle(getWithoutQuery('application/graphql-response+json'));
      expect(await http.code(response), 'GQL400');
    });

    test('serves the page again when GraphiQL is switched on', () async {
      final profile = ServerProfile.production.withGraphiQL(true);
      final response = await http
          .handler(profile: profile)
          .handle(
            http.get(const {}, headers: browser),
          );
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    });

    test('does not serve the page for Accept application/json', () async {
      final response = await http.handler().handle(
        getWithoutQuery('application/json'),
      );
      expect(await http.code(response), 'GQL400');
    });

    test('does not serve the page without Accept', () async {
      final response = await http.handler().handle(http.get(const {}));
      expect(await http.code(response), 'GQL400');
    });

    test('does not serve the page for */*', () async {
      final response = await http.handler().handle(
        getWithoutQuery('*/*'),
      );
      expect(await http.code(response), 'GQL400');
    });

    test('does not serve the page when JSON ranks as high', () async {
      final response = await http.handler().handle(
        getWithoutQuery('text/html, application/json'),
      );
      expect(await http.code(response), 'GQL400');
    });

    test('serves the page when html outranks JSON', () async {
      final response = await http.handler().handle(
        getWithoutQuery('application/json;q=0.5, text/html'),
      );
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    });

    test('does not serve the page for a GET with a query', () async {
      final response = await http.handler().handle(
        http.get(
          {'query': '{ hello }'},
          headers: {...HttpFixture.preflight, 'accept': 'text/html'},
        ),
      );
      expect(response.status, 406);
    });

    test('does not serve the page for a POST', () async {
      final response = await http.handler().handle(
        http.post({'query': '{ hello }'}, headers: {'accept': 'text/html'}),
      );
      expect(response.status, 406);
    });

    test('serves the page at the path of the request', () async {
      final response = await http.handler().handle(
        HttpRequestData(
          method: 'GET',
          uri: Uri.parse('/api/graphql?x=1'),
          headers: browser,
        ),
      );
      expect(
        await http.text(response),
        contains('const endpoint = "/api/graphql";'),
      );
    });
  });
}
