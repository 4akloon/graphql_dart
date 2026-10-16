import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'counting_storage.dart';
import 'multipart_body.dart';

/// A schema with the `Upload` scalar behind a `GraphQLHttpHandler`, with the
/// requests to send it and counters for what ran.
final class UploadHttpFixture {
  UploadHttpFixture({
    bool releaseThrows = false,
    UploadLimits limits = const UploadLimits(),
  }) : storage = CountingStorage(releaseThrows: releaseThrows) {
    uploads = Uploads(storage: storage, limits: limits);
    final b = ExecutableSchemaBuilder<Object?>();
    final upload = b.scalar<Upload>(Uploads.scalarName, uploads.codec);
    final file = Arg('file', upload);
    final files = Arg('files', b.inputList(upload));
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('ok', b.string).pure((_) => 'ok')],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('upload', b.string.nullable, args: [file]).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          resolved++;
          return _describe(args.get(file));
        }),
        t.field('uploadMany', b.string.nullable, args: [files]).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          resolved++;
          final described = [
            for (final item in args.get(files)) await _describe(item),
          ];
          return described.join(',');
        }),
      ],
    );
    schema = b.build(query: query, mutation: mutation);
  }

  /// The operation of one file variable.
  static const String uploadOperation =
      r'mutation ($f: Upload!) { upload(file: $f) }';

  final CountingStorage storage;

  // `late`: assigned in the constructor body, which needs `storage` first.
  late final Uploads uploads;
  late final ExecutableSchema<Object?> schema;

  /// How many contexts were built.
  int contexts = 0;

  /// How many upload resolvers ran.
  int resolved = 0;

  Future<String> _describe(Upload received) async {
    final bytes = await received.openRead().expand((chunk) => chunk).toList();
    return '${received.filename}:${utf8.decode(bytes)}';
  }

  GraphQLHttpHandler<Object?> handler({
    ServerProfile profile = ServerProfile.development,
    BatchPolicy? batching,
    bool isUploadEnabled = true,
  }) => GraphQLHttpHandler<Object?>(
    GraphQLServer<Object?>(
      schema: schema,
      contextFactory: (_) {
        contexts++;
        return null;
      },
      profile: profile,
    ),
    options: HttpOptions(
      uploads: isUploadEnabled ? uploads : null,
      batching: batching,
    ),
  );

  /// A request with one file at `variables.f`.
  MultipartBody single({String content = 'hello'}) => MultipartBody()
      .field(
        'operations',
        jsonEncode({
          'query': uploadOperation,
          'variables': {'f': null},
        }),
      )
      .field('map', '{"0":["variables.f"]}')
      .file('0', utf8.encode(content));

  /// A `POST` of [body]; [stream] replaces the body's own bytes. A
  /// [hasPreflight] request passes CSRF prevention.
  HttpRequestData post(
    MultipartBody body, {
    Map<String, String> headers = const {},
    Stream<List<int>>? stream,
    String? contentType,
    bool hasPreflight = true,
  }) => HttpRequestData(
    method: 'POST',
    uri: Uri.parse('/graphql'),
    headers: {
      'content-type': contentType ?? body.contentType,
      if (hasPreflight) 'graphql-require-preflight': 'true',
      ...headers,
    },
    body: stream ?? body.stream(),
  );

  Future<Object?> json(HttpResponseData response) async =>
      jsonDecode(await text(response));

  Future<String> text(HttpResponseData response) async =>
      switch (response.body) {
        FixedBody(:final bytes) => utf8.decode(bytes),
        StreamedBody(:final chunks) => await utf8.decoder.bind(chunks).join(),
      };

  /// The `extensions.code` of the first error of [response].
  Future<String?> code(HttpResponseData response) async {
    final errors = ((await json(response))! as Map<String, Object?>)['errors'];
    if (errors is! List<Object?> || errors.isEmpty) return null;
    final extensions = (errors.first! as Map<String, Object?>)['extensions'];
    return (extensions! as Map<String, Object?>)['code'] as String?;
  }

  Future<String> message(HttpResponseData response) async {
    final body = (await json(response))! as Map<String, Object?>;
    final errors = body['errors']! as List<Object?>;
    return (errors.first! as Map<String, Object?>)['message']! as String;
  }

  /// Expects that nothing was stored, built or run.
  void expectUntouched() {
    expect(storage.stored + storage.failed, 0, reason: 'no file stored');
    expectNothingKept();
  }

  /// Expects that no file is held and no context or resolver ran.
  void expectNothingKept() {
    expect(storage.held, isEmpty);
    expect(uploads.registry.length, 0);
    expect(contexts, 0, reason: 'no context may be built');
    expect(resolved, 0, reason: 'no resolver may run');
  }
}
