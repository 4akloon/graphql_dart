import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of the fixture schema.
final class Ctx {
  const Ctx(this.tag);

  final String tag;
}

/// A thrown object whose description cannot be made.
final class UnprintableError implements Exception {
  const UnprintableError();

  @override
  String toString() => throw StateError('no description');
}

/// A visitor that does nothing.
final class IdleVisitor extends AstVisitor {
  const IdleVisitor();
}

/// A validation rule that counts the runs it takes part in, to observe
/// whether a document reached validation.
final class CountingRule extends ValidationRule {
  CountingRule();

  int runs = 0;

  @override
  AstVisitor createVisitor(ValidationContext context) {
    runs++;
    return const IdleVisitor();
  }
}

/// A small executable schema and the servers and requests to test it.
final class ServerFixture {
  ServerFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final name = Arg('name', b.string);
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'world'),
        t
            .field('greet', b.string, args: [name])
            .resolve((parent, args, context, info) => args.get(name)),
        t
            .field('tag', b.string)
            .resolve((parent, args, context, info) => context.tag),
        t.field('slow', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return 'slow';
        }),
        t.field('self', query).pure((_) => const Object()),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t.field('ticks', b.string).subscribeWith<int>(
          (parent, args, context, info) => Stream.fromIterable([1, 2]),
          (event, args, context, info) async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return 'tick $event';
          },
        ),
      ],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  late final ExecutableSchema<Ctx> schema;

  GraphQLServer<Ctx> server({
    ServerProfile profile = ServerProfile.development,
    ContextFactory<Ctx>? contextFactory,
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
    ErrorHook? onError,
    int documentCacheSize = 1000,
    List<ServerExtension<Ctx>> extensions = const [],
    PersistedQueryStore? persistedQueries,
  }) => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory: contextFactory ?? (_) => const Ctx('default'),
    profile: profile,
    validationRules: validationRules,
    onError: onError,
    documentCacheSize: documentCacheSize,
    extensions: extensions,
    persistedQueries: persistedQueries,
  );

  ServerRequest request(
    String? query, {
    String method = 'POST',
    String? operationName,
    JsonObject? variables,
    CancelSignal? cancelSignal,
    Map<String, String> headers = const {'content-type': 'application/json'},
    JsonObject? extensions,
  }) => ServerRequest(
    params: GraphQLRequest(
      query: query,
      operationName: operationName,
      variables: variables,
      extensions: extensions,
    ),
    info: RequestInfo(
      method: method,
      uri: Uri.parse('/graphql'),
      headers: headers,
    ),
    cancelSignal: cancelSignal,
  );

  /// The lower-case hex SHA-256 of [text], as clients name a document.
  String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();

  /// The `extensions` of a request naming the persisted query [hash].
  JsonObject persisted(String hash) => JsonObject({
    'persistedQuery': JsonObject({
      'version': JsonNumber(1),
      'sha256Hash': JsonString(hash),
    }),
  });

  /// A query nested [depth] levels deep: `{ self { self { hello } } }`.
  String nested(int depth) => '${'{ self ' * depth}{ hello }${' }' * depth}';

  /// The JSON of a single response.
  Map<String, Object?> json(ServerResponse response) =>
      (response as SingleResponse).body.toJson();

  /// The `extensions.code` of the first error of a single response.
  String codeOf(ServerResponse response) {
    final errors = json(response)['errors']! as List<Object?>;
    final extensions =
        (errors.first! as Map<String, Object?>)['extensions']!
            as Map<String, Object?>;
    return extensions['code']! as String;
  }

  /// The message of the first error of a single response.
  String messageOf(ServerResponse response) {
    final errors = json(response)['errors']! as List<Object?>;
    return (errors.first! as Map<String, Object?>)['message']! as String;
  }
}
