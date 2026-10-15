import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A `Todo` of the graphql-js cancellation tests; [id] is a function so a
/// test can read the run's signal in it.
final class CancellationTodo {
  /// A todo whose `id` resolver is [id].
  CancellationTodo(this.id);

  /// A todo with a fixed id.
  CancellationTodo.of(String value) : id = ((_) => value);

  /// The `id` resolver.
  final FutureOr<String?> Function(FieldInfo info) id;
}

/// The context of a cancellation test: the data the root fields return, a
/// log of the resolvers that ran, and the gates the tests open.
final class CancellationProbe {
  /// The names of the resolvers that started, in order.
  final List<String> log = [];

  /// What `Query.todo` returns.
  FutureOr<CancellationTodo?> Function() todo = () => null;

  /// What `Query.nonNullableTodo` returns.
  FutureOr<CancellationTodo> Function() nonNullableTodo = () =>
      CancellationTodo.of('1');

  /// What `Query.aborter` returns.
  FutureOr<String?> Function() aborter = () => 'done';

  /// What `Subscription.foo` listens to.
  FutureOr<Stream<String>> Function() source = () => const Stream.empty();

  /// Completes when `Query.blocker` starts.
  final Completer<void> blockerStarted = Completer<void>();

  /// What `Query.blocker` waits for.
  final Completer<String> blockerValue = Completer<String>();
}

/// graphql-js's cancellation test schema (`Todo`, `User`, `Query`,
/// `Mutation`, `Subscription`) in the builder, driven by a
/// [CancellationProbe].
final class CancellationSchema {
  /// Builds the schema.
  CancellationSchema() {
    final b = ExecutableSchemaBuilder<CancellationProbe>();
    final user = b.object<Object?>(
      'User',
      fields: (t) => [
        t.field('id', b.id.nullable).resolve((parent, args, context, info) {
          context.log.add('user.id');
          return '1';
        }),
        t.field('name', b.string.nullable).pure((_) => 'user'),
      ],
    );
    final todo = b.object<CancellationTodo>(
      'Todo',
      fields: (t) => [
        t
            .field('id', b.id.nullable)
            .resolve((parent, args, context, info) => parent.id(info)),
        t.field('author', user.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          context.log.add('author');
          await Future<void>.delayed(Duration.zero);
          return Object();
        }),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('todo', todo.nullable)
            .resolve((parent, args, context, info) => context.todo()),
        t
            .field('nonNullableTodo', todo)
            .resolve(
              (parent, args, context, info) => context.nonNullableTodo(),
            ),
        t.field('blocker', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) {
          context.blockerStarted.complete();
          return context.blockerValue.future;
        }),
        t
            .field('aborter', b.string.nullable)
            .resolve((parent, args, context, info) => context.aborter()),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('foo', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          context.log.add('foo');
          return 'baz';
        }),
        t.field('bar', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) {
          context.log.add('bar');
          return 'bar';
        }),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('foo', b.string.nullable)
            .subscribe((parent, args, context, info) => context.source()),
      ],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  /// The executable schema.
  // `late`: assigned at the end of the constructor body.
  late final ExecutableSchema<CancellationProbe> schema;
}
