import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../../server/support/server_fixture.dart';

/// A schema whose subscription is fed by a controller the test owns.
final class ControlledSource {
  ControlledSource() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('events', b.string)
            .subscribeWith<int>(
              (parent, args, context, info) => controller.stream,
              (event, args, context, info) => 'event $event',
            ),
      ],
    );
    schema = b.build(query: query, subscription: subscription);
  }

  bool isCancelled = false;
  late final StreamController<int> controller = StreamController<int>(
    onCancel: () => isCancelled = true,
  );
  late final ExecutableSchema<Ctx> schema;

  Future<void> close() => controller.close();

  GraphQLServer<Ctx> server() => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory: (_) => const Ctx('source'),
  );
}
