import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Role { admin, member }

final class UrlCodec implements ScalarCodec<Uri> {
  const UrlCodec();

  @override
  DecodeResult<Uri> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(Uri.parse(value)),
    _ => const DecodeFailure('Url must be a string'),
  };

  @override
  JsonValue encode(Uri value) => JsonString('$value');
}

base class Entity {
  const Entity(this.id);
  final String id;
}

final class Account extends Entity {
  const Account(super.id, this.name);
  final String name;
}

final class Team extends Entity {
  const Team(super.id);
}

final class Filter {
  const Filter(this.role, this.tags);
  final Role role;
  final List<String> tags;
}

final class Lookup {
  const Lookup();
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();

  final url = b.scalar<Uri>(
    'Url',
    const UrlCodec(),
    description: 'A web address.',
    specifiedByUrl: 'https://url.spec.whatwg.org/',
  );
  final role = b.enumType<Role>(
    'Role',
    Role.values,
    description: 'What an account may do.',
    mapping: EnumValueMapping<Role>(
      nameOf: (value) => value.name.toUpperCase(),
      descriptionOf: (value) => value == Role.admin ? 'Can do all.' : null,
      deprecationReasonOf: (value) =>
          value == Role.member ? 'Use ADMIN.' : null,
    ),
  );
  final roleField = Arg('role', role, defaultValue: Role.member);
  final tagsField = Arg(
    'tags',
    b.inputList(b.string),
    defaultValue: ['a', 'b'],
  );
  final filter = b.inputObject<Filter>(
    'Filter',
    description: 'Narrows a list.',
    fields: () => [roleField, tagsField],
    decode: (values) => Filter(values.get(roleField), values.get(tagsField)),
    encode: (value) => JsonObject({
      'role': JsonString(value.role.name.toUpperCase()),
      'tags': JsonArray([for (final tag in value.tags) JsonString(tag)]),
    }),
  );
  final lookupId = Arg('id', b.id.nullable);
  final lookupEmail = Arg('email', b.string.nullable);
  final lookup = b.oneOfInputObject<Lookup>(
    'Lookup',
    fields: () => [lookupId, lookupEmail],
    decode: (_) => const Lookup(),
  );
  final entity = b.interface<Entity>(
    'Entity',
    description: 'Something with an id.',
    fields: (t) => [
      t.field('id', b.id).pure((value) => value.id),
      t.field('label', b.string).declareOnly(),
    ],
  );
  final account = b.object<Account>(
    'Account',
    interfaces: [entity],
    fields: (t) => [
      t.field('name', b.string).pure((value) => value.name),
      t.field('label', b.string).pure((value) => value.name),
    ],
  );
  final team = b.object<Team>(
    'Team',
    interfaces: [entity],
    fields: (t) => [
      t.field('label', b.string).pure((value) => value.id),
      t.field('id', b.id, description: 'The team id.').pure((v) => v.id),
    ],
  );
  final searchResult = b.union<Entity>(
    'SearchResult',
    description: 'Anything a search finds.',
    members: [account, team],
  );
  final first = Arg(
    'first',
    b.int,
    defaultValue: 10,
    description: 'Page size.',
  );
  final minimumRole = Arg(
    'minimumRole',
    role.nullable,
    defaultValue: Role.admin,
  );
  final filterArg = Arg(
    'filter',
    filter,
    defaultValue: const Filter(Role.member, ['x']),
  );
  final legacyArg = Arg(
    'legacy',
    b.boolean.nullable,
    deprecationReason: 'Not used.',
  );
  final after = Arg.optional('after', b.string.nullable);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field(
            'accounts',
            b.list(account),
            args: [first, minimumRole, filterArg, legacyArg, after],
            description: 'All accounts.',
          )
          .resolve((parent, args, context, info) => const <Account>[]),
      t
          .field('legacy', b.string.nullable)
          .deprecated('Use accounts.')
          .pure((parent) => null),
      t
          .field('search', b.list(searchResult))
          .pure((_) => const <Entity>[Team('t')]),
      t.field('home', url).pure((_) => Uri.parse('https://example.com')),
      t
          .field('find', account.nullable, args: [Arg('by', lookup)])
          .resolve((parent, args, context, info) => null),
      t.field('node', entity).pure((_) => const Account('1', 'a')),
    ],
  );
  final mutation = b.object<Object?>(
    'Mutation',
    fields: (t) => [t.field('ping', b.boolean).pure((_) => true)],
  );

  group('build', () {
    test('prints the SDL of every kind of definition', () {
      final built = b.build(query: query, mutation: mutation);
      expect(const SchemaPrinter().print(built.schema.schema), '''
"""A web address."""
scalar Url @specifiedBy(url: "https://url.spec.whatwg.org/")

"""What an account may do."""
enum Role {
  """Can do all."""
  ADMIN
  MEMBER @deprecated(reason: "Use ADMIN.")
}

"""Narrows a list."""
input Filter {
  role: Role! = MEMBER
  tags: [String!]! = ["a", "b"]
}

input Lookup @oneOf {
  id: ID
  email: String
}

"""Something with an id."""
interface Entity {
  id: ID!
  label: String!
}

type Account implements Entity {
  name: String!
  label: String!
  id: ID!
}

type Team implements Entity {
  label: String!

  """The team id."""
  id: ID!
}

"""Anything a search finds."""
union SearchResult = Account | Team

type Query {
  """All accounts."""
  accounts(
    """Page size."""
    first: Int! = 10
    minimumRole: Role = ADMIN
    filter: Filter! = { role: MEMBER, tags: ["x"] }
    legacy: Boolean @deprecated(reason: "Not used.")
    after: String
  ): [Account!]!
  legacy: String @deprecated(reason: "Use accounts.")
  search: [SearchResult!]!
  home: Url!
  find(by: Lookup!): Account
  node: Entity!
}

type Mutation {
  ping: Boolean!
}''');
    });

    test('the schema carries the roots and the options', () {
      // Its own builder: a subscribe field breaks every build that lacks
      // the subscription root.
      final c = ExecutableSchemaBuilder<Object?>();
      final ticks = c.object<Object?>(
        'Ticks',
        fields: (t) => [
          t
              .field('tick', c.int)
              .subscribe((parent, args, context, info) => Stream.value(1)),
        ],
      );
      final root = c.object<Object?>(
        'Query',
        fields: (t) => [t.field('ok', c.boolean).pure((_) => true)],
      );
      final built = c.build(
        query: root,
        subscription: ticks,
        options: const BuildOptions(
          description: 'The API.',
          includesDeferAndStream: true,
        ),
      );
      final schema = built.schema.schema;
      expect(schema.queryTypeName, 'Query');
      expect(schema.mutationTypeName, isNull);
      expect(schema.subscriptionTypeName, 'Ticks');
      expect(schema.description, 'The API.');
      expect(schema.includesDeferAndStream, isTrue);
    });

    test('declared directives are part of the schema', () {
      final built = b.build(
        query: query,
        options: BuildOptions(
          directives: [
            SchemaDirective(
              'audited',
              locations: const [DirectiveLocation.fieldDefinition],
            ),
          ],
        ),
      );
      expect(built.schema.schema.directiveNamed('audited'), isNotNull);
    });

    test('the built-in scalars are not declared types', () {
      final built = b.build(query: query);
      final names = [for (final type in built.schema.schema.types) type.name];
      expect(names, isNot(contains('Int')));
      expect(names, isNot(contains('String')));
    });

    test('a definition made after a build does not change that schema', () {
      final own = ExecutableSchemaBuilder<Object?>();
      final root = own.object<Object?>(
        'Query',
        fields: (t) => [t.field('a', own.int).pure((_) => 1)],
      );
      final first = own.build(query: root);
      own.object<Object?>(
        'Extra',
        fields: (t) => [t.field('b', own.int).pure((_) => 1)],
      );
      final second = own.build(query: root);
      expect(first.schema.schema.typeNamed('Extra'), isNull);
      expect(second.schema.schema.typeNamed('Extra'), isNotNull);
    });
  });

  group('bindings', () {
    final bindings = b.build(query: query, mutation: mutation).bindings;
    List<String> namesOf(String abstractName) => [
      for (final type in bindings.abstractTypes[abstractName]!.possibleTypes)
        type.name,
    ];

    test('keep the object types and their fields, inherited ones last', () {
      expect(bindings.objects.keys, ['Account', 'Team', 'Query', 'Mutation']);
      expect(bindings.fields['Account']!.keys, ['name', 'label', 'id']);
      expect(bindings.fields['Team']!.keys, ['label', 'id']);
    });

    test('inherit the interface field with its resolver', () {
      final inherited = bindings.fields['Account']!['id']!;
      expect(inherited, same(entity.fields.first));
    });

    test('list the possible types of abstract types in schema order', () {
      expect(bindings.abstractTypes.keys, ['Entity', 'SearchResult']);
      expect(namesOf('Entity'), ['Account', 'Team']);
      expect(namesOf('SearchResult'), ['Account', 'Team']);
    });

    test('keep the leaves, then the introspection enums, and the inputs', () {
      expect(bindings.leaves.keys, [
        'Url',
        'Role',
        '__TypeKind',
        '__DirectiveLocation',
      ]);
      expect(bindings.inputObjects.keys, ['Filter', 'Lookup']);
    });
  });
}
