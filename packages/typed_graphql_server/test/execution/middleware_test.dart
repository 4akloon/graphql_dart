import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/field_lane.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Log {
  final List<String> entries = [];
}

final tag = SchemaDirective(
  'tag',
  locations: const [DirectiveLocation.fieldDefinition],
);

void main() {
  final b = ExecutableSchemaBuilder<Log>();

  /// A middleware that logs [label] before and after the resolver it wraps.
  FieldMiddleware<Log> logging(String label) =>
      (next, site) => (parent, args, context, info) async {
        context.entries.add('>$label');
        final value = await next(parent, args, context, info);
        context.entries.add('<$label');
        return value;
      };

  Future<Map<String, Object?>> run(
    ExecutableSchema<Log> built,
    String text, [
    Log? log,
  ]) async {
    final document = ValidDocument.assumeValid(
      built.schema,
      const Parser(
        options: ParserOptions(maxTokens: null, maxDepth: null),
      ).parse(Source(text)).requireDocument(),
    );
    final payload = await built.execute(document, context: log ?? Log());
    return payload.toJson().toJson();
  }

  ExecutableSchema<Log> buildWith(
    List<FieldDef<Object?, Log>> Function(FieldsBuilder<Object?, Log> t) fields,
    BuildOptions<Log> options,
  ) {
    final c = ExecutableSchemaBuilder<Log>();
    return c.build(
      query: c.object<Object?>('Query', fields: fields),
      options: options,
    );
  }

  group('field middleware', () {
    test(
      'chains run global, field, directive slots, outermost first',
      () async {
        final log = Log();
        final built = buildWith(
          (t) => [
            t
                .field('a', b.string)
                .withMiddleware([logging('f1'), logging('f2')])
                .withDirectives([AppliedDirective('tag')])
                .resolve((parent, args, context, info) {
                  context.entries.add('resolve');
                  return 'a';
                }),
          ],
          BuildOptions(
            directives: [tag],
            middleware: [logging('g1'), logging('g2')],
            directiveMiddleware: {
              'tag': (next, directive) => logging('d')(next, _site),
            },
          ),
        );
        expect(await run(built, '{ a }', log), {
          'data': {'a': 'a'},
        });
        expect(log.entries, [
          '>g1',
          '>g2',
          '>f1',
          '>f2',
          '>d',
          'resolve',
          '<d',
          '<f2',
          '<f1',
          '<g2',
          '<g1',
        ]);
      },
    );

    test('an empty chain stores the resolver itself', () {
      final c = ExecutableSchemaBuilder<Log>();
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('a', c.string).resolve((p, args, context, info) => 'a'),
        ],
      );
      final built = c.build(query: query);
      final original = (query.fields.single.lane as ResolverLane).resolve;
      final stored = built.bindings.fields['Query']!['a']!.lane as ResolverLane;
      expect(identical(stored.resolve, original), isTrue);
    });

    test('a middleware that returns next costs nothing', () {
      final c = ExecutableSchemaBuilder<Log>();
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('a', c.string)
              .withMiddleware([(next, site) => next])
              .resolve((p, args, context, info) => 'a'),
        ],
      );
      final built = c.build(
        query: query,
        options: BuildOptions(middleware: [(next, site) => next]),
      );
      final original = (query.fields.single.lane as ResolverLane).resolve;
      final stored = built.bindings.fields['Query']!['a']!.lane as ResolverLane;
      expect(identical(stored.resolve, original), isTrue);
    });

    test(
      'a directive slot applies only to fields with the directive',
      () async {
        final log = Log();
        final built = buildWith(
          (t) => [
            t
                .field('tagged', b.string)
                .withDirectives([AppliedDirective('tag')])
                .resolve((parent, args, context, info) => 'x'),
            t
                .field('plain', b.string)
                .resolve(
                  (parent, args, context, info) => 'y',
                ),
          ],
          BuildOptions(
            directives: [tag],
            directiveMiddleware: {
              'tag': (next, directive) => (parent, args, context, info) {
                context.entries.add('${directive.name}:${info.fieldName}');
                return next(parent, args, context, info);
              },
            },
          ),
        );
        await run(built, '{ tagged plain }', log);
        expect(log.entries, ['tag:tagged']);
      },
    );

    test('a middleware sees the site of each field', () async {
      final seen = <String>[];
      final built = buildWith(
        (t) => [
          t.field('a', b.string).resolve((parent, args, context, info) => 'a'),
        ],
        BuildOptions(
          middleware: [
            (next, site) {
              seen.add('${site.parentType.name}.${site.field.name}');
              return next;
            },
          ],
        ),
      );
      expect(built, isNotNull);
      expect(seen, ['Query.a']);
    });

    test('a middleware changes results and recovers from errors', () async {
      final built = buildWith(
        (t) => [
          t
              .field('word', b.string)
              .withMiddleware([
                (next, site) => (parent, args, context, info) async {
                  final value = await next(parent, args, context, info);
                  return '${value! as String}!';
                },
              ])
              .resolve((parent, args, context, info) => 'hey'),
          t
              .field('broken', b.string)
              .withMiddleware([
                (next, site) => (parent, args, context, info) async {
                  try {
                    return await next(parent, args, context, info);
                  } on FormatException {
                    return 'recovered';
                  }
                },
              ])
              .resolve(
                (parent, args, context, info) =>
                    throw const FormatException('x'),
              ),
          t
              .field('denied', b.string.nullable)
              .withMiddleware([
                (next, site) =>
                    (parent, args, context, info) =>
                        throw const GraphQLException('denied'),
              ])
              .resolve((parent, args, context, info) => 'never'),
        ],
        const BuildOptions(),
      );
      final response = await run(built, '{ word broken denied }');
      expect(response['data'], {
        'word': 'hey!',
        'broken': 'recovered',
        'denied': null,
      });
      expect(
        ((response['errors']! as List<Object?>).single!
            as Map<String, Object?>)['message'],
        'denied',
      );
    });

    test('the pure lane has no chain', () async {
      var calls = 0;
      final built = buildWith(
        (t) => [t.field('p', b.string).pure((_) => 'pure')],
        BuildOptions(
          middleware: [
            (next, site) {
              calls++;
              return next;
            },
          ],
        ),
      );
      expect(await run(built, '{ p }'), {
        'data': {'p': 'pure'},
      });
      expect(calls, 0);
    });

    test('pure with field middleware is an ArgumentError', () {
      final stub = FieldsBuilder<Object?, Log>()
          .field('p', b.string)
          .withMiddleware([(next, site) => next]);
      expect(() => stub.pure((_) => 'x'), throwsArgumentError);
    });

    test('a slot for an undefined directive is an ArgumentError', () {
      expect(
        () => buildWith(
          (t) => [
            t.field('a', b.string).resolve((p, args, context, info) => 'a'),
          ],
          BuildOptions(
            directiveMiddleware: {'missing': (next, directive) => next},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('an inherited field is composed for each implementing object', () {
      final sites = <String>[];
      final c = ExecutableSchemaBuilder<Log>();
      final node = c.interface<Object?>(
        'Node',
        fields: (t) => [
          t
              .field('id', c.string)
              .resolve((parent, args, context, info) => 'id'),
        ],
      );
      final one = c.object<Object?>(
        'One',
        interfaces: [node],
        fields: (t) => [],
      );
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [t.field('one', one).pure((_) => 1)],
      );
      c.build(
        query: query,
        options: BuildOptions(
          middleware: [
            (next, site) {
              sites.add('${site.parentType.name}.${site.field.name}');
              return next;
            },
          ],
        ),
      );
      expect(sites, ['One.id']);
    });

    test('a definition reads through a wider static type', () {
      final c = ExecutableSchemaBuilder<Log>();
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('a', c.string)
              .withMiddleware([(next, site) => next])
              .resolve((p, args, context, info) => 'a'),
        ],
      );
      final FieldDef<Object?, Object?> wide = query.fields.single;
      expect(wide.middleware, hasLength(1));
    });
  });
}

final _site = FieldSite(
  ObjectType('Query'),
  SchemaField('a', const NamedType(Name('String'))),
);
