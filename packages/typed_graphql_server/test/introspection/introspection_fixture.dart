import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Role { admin, guest }

final class Account {
  const Account();
}

final class Robot {
  const Robot();
}

/// A schema with every kind of type, deprecations, descriptions and a
/// repeatable directive, and helpers to run queries against it.
final class IntrospectionFixture {
  IntrospectionFixture({List<FieldMiddleware<Object?>> middleware = const []}) {
    final b = ExecutableSchemaBuilder<Object?>();
    final url = b.scalar<String>(
      'Url',
      const StringCodec(),
      description: 'A web address.',
      specifiedByUrl: 'https://example.com/url',
    );
    final role = b.enumType<Role>(
      'Role',
      Role.values,
      description: 'What an account may do.',
      mapping: EnumValueMapping<Role>(
        descriptionOf: (value) => value == Role.admin ? 'Does all.' : null,
        deprecationReasonOf: (value) =>
            value == Role.guest ? 'Use admin.' : null,
      ),
    );
    final node = b.interface<Object?>(
      'Node',
      description: 'Something with an id.',
      fields: (t) => [t.field('id', b.id).declareOnly()],
    );
    final entity = b.interface<Object?>(
      'Entity',
      interfaces: [node],
      fields: (t) => [
        t.field('id', b.id).declareOnly(),
        t.field('name', b.string).declareOnly(),
      ],
    );
    final account = b.object<Account>(
      'Account',
      interfaces: [entity, node],
      fields: (t) => [
        t.field('id', b.id).pure((_) => '1'),
        t.field('name', b.string, description: 'Shown name.').pure((_) => 'a'),
        t.field('role', role).pure((_) => Role.admin),
        t.field('site', url.nullable).pure((_) => null),
      ],
    );
    final robot = b.object<Robot>(
      'Robot',
      interfaces: [node],
      fields: (t) => [
        t.field('id', b.id).pure((_) => '2'),
        t
            .field(
              'serial',
              b.string,
              args: [
                Arg<String?>(
                  'unit',
                  b.string.nullable,
                  deprecationReason: 'Not used.',
                ),
              ],
            )
            .deprecated('Use id.')
            .withDirectives([AppliedDirective('tag')])
            .resolve((parent, args, context, info) => 's'),
      ],
    );
    final search = b.union<Object?>(
      'Search',
      members: [account, robot],
      description: 'Anything findable.',
    );
    final lookupId = Arg<String?>('id', b.string.nullable);
    final lookupName = Arg<String?>('name', b.string.nullable);
    final lookup = b.oneOfInputObject<String>(
      'Lookup',
      description: 'One way to find.',
      fields: () => [lookupId, lookupName],
      decode: (values) => values.get(lookupId) ?? values.get(lookupName) ?? '',
    );
    final term = Arg<String>('term', b.string, defaultValue: 'all');
    final by = Arg<String?>('by', lookup.nullable);
    final query = b.object<Object?>(
      'Query',
      description: 'The root.',
      fields: (t) => [
        t
            .field(
              'search',
              b.list(search),
              args: [term, by],
              description: 'Finds things.',
            )
            .resolve((parent, args, context, info) => const <Object>[]),
        t.field('me', account.nullable).pure((_) => const Account()),
        t.field('old', b.string).deprecated('Use me.').pure((_) => 'x'),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('ping', b.boolean).pure((_) => true)],
    );
    built = b.build(
      query: query,
      mutation: mutation,
      options: BuildOptions(
        description: 'The API.',
        middleware: middleware,
        directives: [
          SchemaDirective(
            'tag',
            description: 'Marks a field.',
            isRepeatable: true,
            locations: const [
              DirectiveLocation.fieldDefinition,
              DirectiveLocation.object,
            ],
            arguments: [
              InputValue(
                'name',
                const NamedType(Name('String')),
                description: 'The tag.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  late final ExecutableSchema<Object?> built;

  /// The JSON of the response to [text].
  Future<Map<String, Object?>> json(
    String text, {
    ExecutionOptions options = const ExecutionOptions(),
    JsonObject? variables,
  }) async {
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument();
    final FutureOr<ResponsePayload> payload = built.execute(
      ValidDocument.assumeValid(built.schema, document),
      context: null,
      options: options,
      variables: variables,
    );
    return (await payload).toJson().toJson();
  }
}
