import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../../server/support/server_fixture.dart';

/// An extension that adds one header to every response of the pipeline.
final class HeaderExtension extends ServerExtension<Ctx> {
  const HeaderExtension();

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) async => (await next(request)).withHeaders(const {'x-extension': 'yes'});
}

/// An extension that answers every request with a stream, which only an
/// extension can do over plain JSON.
final class StreamingExtension extends ServerExtension<Ctx> {
  const StreamingExtension(this.results);

  final Stream<ExecutionResult> results;

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) async => StreamResponse(results);
}

/// The server fixture's schema behind a `GraphQLHttpHandler`, with the
/// requests to send it and readers for what comes back.
final class HttpFixture {
  /// The headers a `GET` needs so that CSRF prevention lets it through.
  static const Map<String, String> preflight = {
    'graphql-require-preflight': 'true',
  };

  /// The `Accept` header of a client that speaks the current media type.
  static const Map<String, String> modernClient = {
    'accept': 'application/graphql-response+json',
  };

  final ServerFixture fixture = ServerFixture();

  /// How many contexts the handlers made here built.
  int contexts = 0;

  GraphQLHttpHandler<Ctx> handler({
    ServerProfile profile = ServerProfile.development,
    HttpOptions options = const HttpOptions(),
    ContextFactory<Ctx>? contextFactory,
    List<ServerExtension<Ctx>> extensions = const [],
  }) => handlerOver(
    fixture.server(
      profile: profile,
      contextFactory: counting(contextFactory),
      extensions: extensions,
    ),
    options: options,
  );

  GraphQLHttpHandler<Ctx> handlerOver(
    GraphQLServer<Ctx> server, {
    HttpOptions options = const HttpOptions(),
  }) => GraphQLHttpHandler<Ctx>(server, options: options);

  /// A context factory that counts the contexts it builds and then asks
  /// [inner], or answers a default context.
  ContextFactory<Ctx> counting(ContextFactory<Ctx>? inner) => (info) {
    contexts++;
    return inner == null ? const Ctx('default') : inner(info);
  };

  HttpRequestData get(
    Map<String, String> params, {
    Map<String, String> headers = preflight,
  }) => HttpRequestData(
    method: 'GET',
    uri: Uri(path: '/graphql', queryParameters: params),
    headers: headers,
  );

  HttpRequestData post(
    Object? json, {
    Map<String, String> headers = const {},
    CancelSignal? cancelSignal,
  }) => HttpRequestData(
    method: 'POST',
    uri: Uri.parse('/graphql'),
    headers: {'content-type': 'application/json', ...headers},
    body: Stream.value(utf8.encode(jsonEncode(json))),
    cancelSignal: cancelSignal,
  );

  /// A `POST` whose headers are exactly [headers].
  HttpRequestData postBytes(
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) => postStream(Stream.value(bytes), headers: headers);

  HttpRequestData postStream(
    Stream<List<int>> body, {
    Map<String, String> headers = const {},
  }) => HttpRequestData(
    method: 'POST',
    uri: Uri.parse('/graphql'),
    headers: headers,
    body: body,
  );

  Future<String> text(HttpResponseData response) async =>
      switch (response.body) {
        FixedBody(:final bytes) => utf8.decode(bytes),
        StreamedBody(:final chunks) => await utf8.decoder.bind(chunks).join(),
      };

  Future<Object?> json(HttpResponseData response) async =>
      jsonDecode(await text(response));

  /// The `extensions.code` of the first error of [response], or null.
  Future<String?> code(HttpResponseData response) async {
    final body = await json(response);
    if (body is! Map<String, Object?>) return null;
    final errors = body['errors'];
    if (errors is! List<Object?> || errors.isEmpty) return null;
    final first = errors.first;
    if (first is! Map<String, Object?>) return null;
    final extensions = first['extensions'];
    if (extensions is! Map<String, Object?>) return null;
    return extensions['code'] as String?;
  }

  /// The message of the first error of [response].
  Future<String> message(HttpResponseData response) async {
    final body = (await json(response))! as Map<String, Object?>;
    final first = (body['errors']! as List<Object?>).first!;
    return (first as Map<String, Object?>)['message']! as String;
  }
}
