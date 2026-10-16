import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A schema with a failing field, an upload mutation and a subscription whose
/// source the test emits into, for the end-to-end tests.
final class EndToEndFixture {
  EndToEndFixture({Uploads? uploads})
    : uploads = uploads ?? Uploads(),
      ticks = StreamController<int>.broadcast() {
    final b = ExecutableSchemaBuilder<Object?>();
    final upload = b.scalar<Upload>(
      Uploads.scalarName,
      this.uploads.codec,
    );
    final file = Arg('file', upload);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'world'),
        t
            .field('broken', b.string.nullable)
            .pure((_) => throw const GraphQLException('boom')),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('upload', b.string, args: [file]).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          final received = args.get(file);
          final bytes = await received.openRead().expand((c) => c).toList();
          return '${received.filename}: ${utf8.decode(bytes)}';
        }),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('ticks', b.string)
            .subscribeWith<int>(
              (parent, args, context, info) => ticks.stream,
              (event, args, context, info) => 'tick $event',
            ),
      ],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  /// The uploads shared by the schema's scalar and the HTTP options.
  final Uploads uploads;

  /// The source of the `ticks` subscription.
  final StreamController<int> ticks;

  /// Ends the subscription source.
  Future<void> close() => ticks.close();

  // Set by the constructor body, before anything reads it.
  late final ExecutableSchema<Object?> schema;

  GraphQLServer<Object?> server({
    ServerProfile profile = ServerProfile.development,
  }) => GraphQLServer<Object?>(
    schema: schema,
    contextFactory: (_) => null,
    profile: profile,
  );
}
