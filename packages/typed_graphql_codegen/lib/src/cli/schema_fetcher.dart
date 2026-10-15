import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'schema_fetch_result.dart';
import 'secret_redactor.dart';

/// Fetches a schema by posting the full introspection query to a URL.
///
/// It does not follow redirects: a 3xx is reported with the URL to use. What
/// the diagnostics print of the URL and of the response has the header
/// values hidden and no user information or query.
///
/// {@category codegen}
final class SchemaFetcher {
  /// Creates a fetcher; [timeout] bounds the whole exchange, [maxBodyBytes]
  /// the response body, and [clientFactory] makes the HTTP client (tests
  /// inject their own).
  const SchemaFetcher({
    this.timeout = const Duration(seconds: 30),
    this.maxBodyBytes = defaultMaxBodyBytes,
    this.clientFactory = HttpClient.new,
  });

  /// The default cap of the response body: 64 MiB.
  static const int defaultMaxBodyBytes = 64 * 1024 * 1024;

  /// How long the request, the response and the body may take together.
  final Duration timeout;

  /// The most bytes of response body the fetcher reads; it stops reading at
  /// the first byte past it.
  final int maxBodyBytes;

  /// Makes the client of one fetch; the fetcher closes it.
  final HttpClient Function() clientFactory;

  static const int _bodyExcerptLength = 200;

  /// Posts the introspection query to [url] with [headers]; never throws.
  /// [secrets] are further texts to hide from what is reported, such as the
  /// values of the environment variables the headers used.
  Future<SchemaFetchResult> fetch(
    Uri url,
    Map<String, String> headers, {
    List<String> secrets = const [],
  }) async {
    final redactor = SecretRedactor([
      ...headers.values,
      ...secrets,
      ...url.userInfo.split(':'),
      url.userInfo,
      ...url.queryParameters.values,
      url.query,
    ]);
    final client = clientFactory();
    try {
      return await _exchange(client, url, headers, redactor).timeout(timeout);
    } on TimeoutException {
      final limit = timeout.inMilliseconds % 1000 == 0
          ? '${timeout.inSeconds}s'
          : '${timeout.inMilliseconds}ms';
      return _failed(url, 'the request timed out after $limit', redactor);
    } on IOException catch (error) {
      return _failed(url, _describe(error), redactor);
    } finally {
      client.close(force: true);
    }
  }

  Future<SchemaFetchResult> _exchange(
    HttpClient client,
    Uri url,
    Map<String, String> headers,
    SecretRedactor redactor,
  ) async {
    final HttpClientRequest request;
    try {
      request = await client.postUrl(url);
      request
        ..followRedirects = false
        ..headers.contentType = ContentType.json
        ..headers.set(
          HttpHeaders.acceptHeader,
          'application/graphql-response+json, application/json',
        );
      for (final MapEntry(:key, :value) in headers.entries) {
        request.headers.set(key, value);
      }
    } on FormatException catch (error) {
      return _failed(
        url,
        'the request cannot be built: ${error.message}',
        redactor,
      );
    }
    request.add(utf8.encode(_body));
    final response = await request.close();
    return _read(url, response, redactor);
  }

  Future<SchemaFetchResult> _read(
    Uri url,
    HttpClientResponse response,
    SecretRedactor redactor,
  ) async {
    final status = response.statusCode;
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (status >= 300 && status < 400 && location != null) {
      final target = redactor.displayUrl(url.resolve(location));
      return _failed(
        url,
        'the server redirected (HTTP $status) to $target; set `schema` to '
        'that URL',
        redactor,
      );
    }
    final bytes = await _readCapped(response);
    if (bytes == null) {
      return _failed(
        url,
        'the response is larger than $maxBodyBytes bytes',
        redactor,
      );
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return _failed(url, 'the response is not valid UTF-8', redactor);
    }
    if (status >= 200 && status <= 299) {
      return SchemaFetched(
        ProjectFile('${redactor.displayUrl(url)}.json', text),
      );
    }
    return _failed(url, _statusReason(response, text, redactor), redactor);
  }

  String _statusReason(
    HttpClientResponse response,
    String text,
    SecretRedactor redactor,
  ) {
    final excerpt = redactor.escapeAll(redactor.redact(text));
    final shown = excerpt.length > _bodyExcerptLength
        ? excerpt.substring(0, _bodyExcerptLength)
        : excerpt;
    final head = 'HTTP ${response.statusCode} ${response.reasonPhrase}';
    return shown.isEmpty ? head : '$head: $shown';
  }

  // Null when the body is past the cap; reading stops there.
  Future<Uint8List?> _readCapped(Stream<List<int>> body) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    return bytes.takeBytes();
  }

  String get _body => GraphQLRequest(
    query: IntrospectionQuery.full.text,
  ).toJson().toString();

  String _describe(IOException error) => switch (error) {
    SocketException(:final message) => message,
    HttpException(:final message) => message,
    _ => error.toString(),
  };

  SchemaFetchFailed _failed(Uri url, String reason, SecretRedactor redactor) =>
      SchemaFetchFailed(
        Diagnostic(
          .inputUnreadable,
          .error,
          redactor.redact(
            "Cannot fetch the schema from '${redactor.displayUrl(url)}': "
            '$reason.',
          ),
        ),
      );
}
