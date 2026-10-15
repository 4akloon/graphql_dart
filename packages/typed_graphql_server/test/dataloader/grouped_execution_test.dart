import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Ctx {
  Ctx(this.posts);

  final GroupedLoader<int, String> posts;
}

void main() {
  test('a list of authors loads its posts in one batch', () async {
    final calls = <List<int>>[];
    final b = ExecutableSchemaBuilder<Ctx>();
    final author = b.object<int>(
      'Author',
      fields: (t) => [
        t
            .field('posts', b.list(b.string))
            .resolve(
              (parent, args, context, info) => context.posts.load(parent),
            ),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('authors', b.list(author)).pure((_) => const [1, 2, 3]),
      ],
    );
    final schema = b.build(query: query);
    final document = ValidDocument.assumeValid(
      schema.schema,
      const Parser().parse(Source('{ authors { posts } }')).requireDocument(),
    );
    final context = Ctx(
      GroupedLoader<int, String>((keys) {
        calls.add(keys);
        return {
          for (final key in keys.where((key) => key != 3))
            key: ['post $key a', 'post $key b'],
        };
      }),
    );

    final result = await schema.execute(document, context: context);

    expect(calls, [
      [1, 2, 3],
    ]);
    expect((result as ExecutionResult).toJson().toJson(), {
      'data': {
        'authors': [
          {
            'posts': ['post 1 a', 'post 1 b'],
          },
          {
            'posts': ['post 2 a', 'post 2 b'],
          },
          {'posts': <Object?>[]},
        ],
      },
    });
  });
}
