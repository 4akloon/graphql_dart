import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The batches one test observed: which request's loader asked, and for what.
final class BatchLog {
  final List<(String, List<String>)> batches = [];
}

/// The context of one request: its user and its own loader.
final class LoaderContext {
  LoaderContext(this.user, this.values);

  final String user;
  final BatchLoader<String, String> values;
}

void main() {
  final builder = ExecutableSchemaBuilder<LoaderContext>();
  final query = builder.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('values', builder.list(builder.string))
          .resolve(
            (parent, args, context, info) => context.values.loadMany([
              '${context.user}:a',
              '${context.user}:b',
            ]),
          ),
    ],
  );
  final schema = builder.build(query: query);
  const badUser = 'bad';

  GraphQLServer<LoaderContext> serverLogging(BatchLog log) =>
      GraphQLServer<LoaderContext>(
        schema: schema,
        profile: ServerProfile.development,
        contextFactory: (request) {
          final user = request.header('x-user')!;
          return LoaderContext(
            user,
            BatchLoader<String, String>((keys) async {
              log.batches.add((user, keys));
              await Future<void>.delayed(Duration.zero);
              if (user == badUser) throw StateError('batch of $user failed');
              return {for (final key in keys) key: 'value of $key'};
            }),
          );
        },
      );

  ServerRequest requestFor(String user) => ServerRequest(
    params: const GraphQLRequest(query: '{ values }'),
    info: RequestInfo(
      method: 'POST',
      uri: Uri.parse('/graphql'),
      headers: {'x-user': user, 'content-type': 'application/json'},
    ),
  );

  Map<String, Object?> bodyOf(ServerResponse response) =>
      (response as SingleResponse).body.toJson();

  test('50 concurrent requests each get only their own values', () async {
    final log = BatchLog();
    final server = serverLogging(log);
    final users = [for (var index = 0; index < 50; index++) 'user$index'];

    final responses = await Future.wait([
      for (final user in users) server.handle(requestFor(user)),
    ]);

    for (final (index, response) in responses.indexed) {
      final user = users[index];
      expect(bodyOf(response)['data'], {
        'values': ['value of $user:a', 'value of $user:b'],
      });
    }
  });

  test('no batch mixes the keys of two requests', () async {
    final log = BatchLog();
    final server = serverLogging(log);
    final users = [for (var index = 0; index < 50; index++) 'user$index'];

    await Future.wait([
      for (final user in users) server.handle(requestFor(user)),
    ]);

    expect(log.batches, hasLength(50), reason: 'one batch per request');
    for (final (user, keys) in log.batches) {
      expect(keys, ['$user:a', '$user:b']);
    }
  });

  test('a failed batch does not affect another request', () async {
    final log = BatchLog();
    final server = serverLogging(log);

    final responses = await Future.wait([
      server.handle(requestFor('good1')),
      server.handle(requestFor(badUser)),
      server.handle(requestFor('good2')),
    ]);

    expect(bodyOf(responses[0])['data'], {
      'values': ['value of good1:a', 'value of good1:b'],
    });
    expect(bodyOf(responses[2])['data'], {
      'values': ['value of good2:a', 'value of good2:b'],
    });
    expect(bodyOf(responses[1])['errors'], isNotEmpty);
  });

  test('a failed batch leaves no uncaught error', () async {
    final log = BatchLog();
    final server = serverLogging(log);
    final uncaught = <Object>[];

    await runZonedGuarded(
      () async {
        await Future.wait([
          for (var index = 0; index < 10; index++)
            server.handle(requestFor(badUser)),
          server.handle(requestFor('good')),
        ]);
        // Give a stray error time to surface in the zone: a few turns of the
        // event loop, after the microtasks that deliver it.
        for (var turn = 0; turn < 5; turn++) {
          await Future<void>.delayed(Duration.zero);
        }
      },
      (error, stackTrace) => uncaught.add(error),
    );

    expect(uncaught, isEmpty);
  });
}
