import 'dart:convert';

import 'package:meta/meta.dart';

import 'http_response_body.dart';
import 'http_response_data.dart';

/// The GraphiQL page `GraphQLHttpHandler` serves to a browser in development
/// (R5.9, R5.15).
///
/// Every asset is pinned by version and by Subresource Integrity, so a
/// compromised CDN cannot run code in the page. GraphiQL 3.9.0 is the last
/// release with a UMD build that sets `window.GraphiQL`.
@internal
final class GraphiQLPage {
  /// Creates the page.
  const GraphiQLPage();

  /// The Subresource Integrity values of the four assets, computed from the
  /// downloaded files on 2026-10-16.
  static const String reactIntegrity =
      'sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiDrcHkMLKI6fiB/Z';

  /// See [reactIntegrity].
  static const String reactDomIntegrity =
      'sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVdsSH1fSDUf5YJj1';

  /// See [reactIntegrity].
  static const String styleIntegrity =
      'sha384-QMux00XgRtwRLSYIY3kw2rj1ovk5AuuliAchk+HSQbqdbGFnz9GYuqIlOqxhwCE2';

  /// See [reactIntegrity].
  static const String scriptIntegrity =
      'sha384-8NGfVj4CVlqHajlZj+bPJT4thxPMHMJYn7DWK2CvtopLd02E7qsPHazniBYvVjOO';

  /// The page, which sends its queries to [path] (the path of the request
  /// that opened it).
  HttpResponseData response(String path) => HttpResponseData(
    200,
    headers: const {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'vary': 'accept',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      'x-frame-options': 'DENY',
    },
    body: FixedBody(utf8.encode(_html(path))),
  );

  // The path goes into a script, so it is a JSON string literal in which
  // nothing can close the script element or end the line early.
  String _endpointLiteral(String path) =>
      jsonEncode(path)
          .replaceAll('<', r'\u003c')
          .replaceAll('>', r'\u003e')
          .replaceAll('&', r'\u0026')
          .replaceAll('\u2028', r'\u2028')
          .replaceAll('\u2029', r'\u2029');

  String _html(String path) =>
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GraphiQL</title>
<style>body { height: 100vh; margin: 0; overflow: hidden; } #graphiql { height: 100vh; }</style>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/graphiql.min.css" integrity="$styleIntegrity" crossorigin="anonymous">
</head>
<body>
<div id="graphiql">Loading...</div>
<script src="https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js" integrity="$reactIntegrity" crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js" integrity="$reactDomIntegrity" crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/graphiql.min.js" integrity="$scriptIntegrity" crossorigin="anonymous"></script>
<script>
const endpoint = ${_endpointLiteral(path)};
const fetcher = async (params) => (await fetch(endpoint, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    accept: 'application/graphql-response+json, application/json;q=0.9',
  },
  body: JSON.stringify(params),
})).json();
ReactDOM.createRoot(document.getElementById('graphiql')).render(
  React.createElement(GraphiQL, {fetcher}),
);
</script>
</body>
</html>
''';
}
