import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Ctx {
  Ctx(this.names);

  final BatchLoader<int, String> names;
}

void main() {
  test('a list of users loads its names in one batch', () async {
    final calls = <List<int>>[];
    final b = ExecutableSchemaBuilder<Ctx>();
    final user = b.object<int>(
      'User',
      fields: (t) => [
        t
            .field('name', b.string)
            .resolve(
              (parent, args, context, info) => context.names.load(parent),
            ),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('users', b.list(user)).pure((_) => const [1, 2, 3]),
      ],
    );
    final schema = b.build(query: query);
    final document = ValidDocument.assumeValid(
      schema.schema,
      const Parser().parse(Source('{ users { name } }')).requireDocument(),
    );
    final context = Ctx(
      BatchLoader<int, String>((keys) {
        calls.add(keys);
        return {for (final key in keys) key: 'user $key'};
      }),
    );

    final result = await schema.execute(document, context: context);

    expect(calls, [
      [1, 2, 3],
    ]);
    expect((result as ExecutionResult).toJson().toJson(), {
      'data': {
        'users': [
          {'name': 'user 1'},
          {'name': 'user 2'},
          {'name': 'user 3'},
        ],
      },
    });
  });
}
