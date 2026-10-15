import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Pic {
  const _Pic(this.url, this.width, this.height);

  final String url;
  final int? width;
  final int? height;
}

final class _Author {
  const _Author();

  _Pic pic(int? width, int? height) => _Pic('cdn://123', width, height);

  _Article recentArticle() => const _Article(1);
}

final class _Article {
  const _Article(this.id);

  final int id;

  _Author get author => const _Author();

  String get title => 'My Article $id';
}

// Ported from graphql-js src/execution/__tests__/schema-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles execution with a complex schema', () {
    test('executes using a schema', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final width = Arg('width', b.int.nullable);
      final height = Arg('height', b.int.nullable);
      final image = b.object<_Pic>(
        'Image',
        fields: (t) => [
          t.field('url', b.string.nullable).pure((pic) => pic.url),
          t.field('width', b.int.nullable).pure((pic) => pic.width),
          t.field('height', b.int.nullable).pure((pic) => pic.height),
        ],
      );
      late final ObjectTypeDef<_Author> author;
      late final ObjectTypeDef<_Article> article;
      author = b.object<_Author>(
        'Author',
        fields: (t) => [
          t.field('id', b.string.nullable).pure((_) => '123'),
          t.field('name', b.string.nullable).pure((_) => 'John Smith'),
          t
              .field('pic', image.nullable, args: [width, height])
              .resolve(
                (obj, args, context, info) =>
                    obj.pic(args.get(width), args.get(height)),
              ),
          t
              .field('recentArticle', article.nullable)
              .pure((obj) => obj.recentArticle()),
        ],
      );
      article = b.object<_Article>(
        'Article',
        fields: (t) => [
          t.field('id', b.string).pure((article) => '${article.id}'),
          t.field('isPublished', b.boolean.nullable).pure((_) => true),
          t.field('author', author.nullable).pure((article) => article.author),
          t.field('title', b.string.nullable).pure((article) => article.title),
          t.field('body', b.string.nullable).pure((_) => 'This is a post'),
          t
              .field('keywords', b.list(b.string.nullable).nullable)
              .pure((_) => ['foo', 'bar', '1', 'true', null]),
        ],
      );
      final articleId = Arg('id', b.id.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field('article', article.nullable, args: [articleId])
                .resolve(
                  (_, args, context, info) =>
                      _Article(int.parse(args.get(articleId)!)),
                ),
            t
                .field('feed', b.list(article.nullable).nullable)
                .pure(
                  (_) => [for (var id = 1; id <= 10; id++) _Article(id)],
                ),
          ],
        ),
      );

      // Note: this is intentionally not validating to ensure appropriate
      // behavior occurs when executing an invalid query.
      final result = await port.json(schema, '''
      {
        feed {
          id,
          title
        },
        article(id: "1") {
          ...articleFields,
          author {
            id,
            name,
            pic(width: 640, height: 480) {
              url,
              width,
              height
            },
            recentArticle {
              ...articleFields,
              keywords
            }
          }
        }
      }

      fragment articleFields on Article {
        id,
        isPublished,
        title,
        body,
        hidden,
        notDefined
      }
    ''');
      expect(
        result,
        equals({
          'data': {
            'feed': [
              for (var id = 1; id <= 10; id++)
                {'id': '$id', 'title': 'My Article $id'},
            ],
            'article': {
              'id': '1',
              'isPublished': true,
              'title': 'My Article 1',
              'body': 'This is a post',
              'author': {
                'id': '123',
                'name': 'John Smith',
                'pic': {'url': 'cdn://123', 'width': 640, 'height': 480},
                'recentArticle': {
                  'id': '1',
                  'isPublished': true,
                  'title': 'My Article 1',
                  'body': 'This is a post',
                  'keywords': ['foo', 'bar', '1', 'true', null],
                },
              },
            },
          },
        }),
      );
    });
  });
}
