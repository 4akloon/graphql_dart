import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'schema_fetch_result.dart';

/// Fetches a schema by posting the full introspection query to a URL.
///
/// {@category codegen}
final class SchemaFetcher {
  /// Creates a fetcher; [timeout] bounds the whole exchange, and
  /// [clientFactory] makes the HTTP client (tests inject their own).
  const SchemaFetcher({
    this.timeout = const Duration(seconds: 30),
    this.clientFactory = HttpClient.new,
  });

  /// How long the request, the response and the body may take together.
  final Duration timeout;

  /// Makes the client of one fetch; the fetcher closes it.
  final HttpClient Function() clientFactory;

  static const int _bodyExcerptLength = 200;

  /// Posts the introspection query to [url] with [headers]; never throws.
  Future<SchemaFetchResult> fetch(Uri url, Map<String, String> headers) async {
    final client = clientFactory();
    try {
      return await _exchange(client, url, headers).timeout(timeout);
    } on TimeoutException {
      final limit = timeout.inMilliseconds % 1000 == 0
          ? '${timeout.inSeconds}s'
          : '${timeout.inMilliseconds}ms';
      return _failed(url, 'the request timed out after $limit');
    } on IOException catch (error) {
      return _failed(url, _describe(error));
    } on FormatException {
      return _failed(url, 'the response is not valid UTF-8');
    } finally {
      client.close(force: true);
    }
  }

  Future<SchemaFetchResult> _exchange(
    HttpClient client,
    Uri url,
    Map<String, String> headers,
  ) async {
    final request = await client.postUrl(url);
    request.headers
      ..contentType = ContentType.json
      ..set(
        HttpHeaders.acceptHeader,
        'application/graphql-response+json, application/json',
      );
    for (final MapEntry(:key, :value) in headers.entries) {
      request.headers.set(key, value);
    }
    request.add(utf8.encode(_body));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode > 299) {
      final excerpt = text.length > _bodyExcerptLength
          ? text.substring(0, _bodyExcerptLength)
          : text;
      final status = '${response.statusCode} ${response.reasonPhrase}';
      return _failed(url, 'HTTP $status: $excerpt');
    }
    return SchemaFetched(ProjectFile('$url.json', text));
  }

  String get _body => GraphQLRequest(
    query: IntrospectionQuery.full.text,
  ).toJson().toString();

  String _describe(IOException error) => switch (error) {
    SocketException(:final message) => message,
    HttpException(:final message) => message,
    _ => error.toString(),
  };

  SchemaFetchFailed _failed(Uri url, String reason) => SchemaFetchFailed(
    Diagnostic(
      .inputUnreadable,
      .error,
      "Cannot fetch the schema from '$url': $reason.",
    ),
  );
}
