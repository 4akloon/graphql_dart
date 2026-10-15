# Schema Builder

`ExecutableSchemaBuilder<C>` declares a GraphQL schema in typed Dart code.
`C` is the type of the per-request context every resolver receives. Every
definition you make through a builder belongs to the schema it builds, in
creation order; `build` checks them and returns an `ExecutableSchema<C>`
(`typed_graphql`'s own `SchemaBuilder` builds a schema from SDL text, hence
the different name).

The package cannot execute a request yet: execution arrives in M5b. What
works today is declaring, checking and printing a schema.

## Refs and nullability

Every type you declare, and the five built-in scalars (`b.int`, `b.float`,
`b.string`, `b.boolean`, `b.id`), is a ref, and a ref carries its Dart type.
A ref is non-null by default, as a Dart type is: `b.string` is `String!` and
stands for a Dart `String`. `.nullable` gives `String` (no `!`) and a Dart `String?`.
`b.list(item)` is a non-null list of `item`, so `b.list(b.string.nullable)`
is `[String]!` and `b.list(b.string).nullable` is `[String!]`.

## Objects and fields

A field is declared in two steps: `t.field(name, type, ...)` fixes the Dart
result type from the ref, and `pure` or `resolve` then takes the closure.
Because the type is known before the closure is inferred, a getter that
returns a `String?` for a `b.string` field, or an `int` for a `String`
field, does not compile, and a field without a resolver is not a field at
all.

- `pure((parent) => value)` reads a value from the parent object, with no
  arguments, no context and no waiting.
- `resolve((parent, args, context, info) => result)` may return a value or a
  `Future` of one, and reads the field's arguments and the context.
- `declareOnly()` completes an interface field: every implementing object
  declares its own resolver.
- `.deprecated(reason)` and `.withDirectives(...)` modify the stub before
  it is completed.

An object's `fields` thunk runs once, when the schema is built or first
used, so two types may refer to each other through `late final` variables
or class fields.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Book {
  const Book(this.title, this.pages);

  final String title;
  final int? pages;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<Book>(
    'Book',
    description: 'A book on the shelf.',
    fields: (t) => [
      t.field('title', b.string).pure((book) => book.title),
      t.field('pages', b.int.nullable).pure((book) => book.pages),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('books', b.list(book)).pure((_) => const [Book('Dune', 412)]),
      t
          .field('motto', b.string.nullable)
          .deprecated('Not used.')
          .pure((_) => null),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
"""A book on the shelf."""
type Book {
  title: String!
  pages: Int
}

type Query {
  books: [Book!]!
  motto: String @deprecated(reason: "Not used.")
}
```

## Scalars and enums

`b.scalar<T>(name, codec)` declares a custom scalar over a `ScalarCodec<T>`
of the core. `b.enumType<E>(name, values)` declares an enum over a Dart
enum: the value of an enum field is the Dart enum value itself. An
`EnumValueMapping` renames values and gives them descriptions and
deprecations; the default name is `Enum.name`.

## Arguments

An `Arg<T>` declares a field argument: `Arg('first', b.int, defaultValue: 10)`.
Pass the arguments to the field with `args:` and read them in `resolve`
through `args.get(arg)`, which returns a `T`, so the read is checked at
compile time like the result. A default value is written into the schema.

`Arg.optional('after', b.string.nullable)` is for an argument whose absence
differs from `null`, as in a partial update: its value is an `Optional<T>`,
`Present(value)` when the request gave one and `Absent()` when it did not.
`Arg.optional` keeps the nullability of the ref it is given, so a non-null
ref makes a required argument; `b.string.nullable` is the usual choice.

When a field has many arguments, `resolveWith(definition, resolve)` takes an
`ArgumentsDef<A>`: the arguments and a function that builds your own
arguments class from them, so the resolver gets an `A`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Genre { fantasy, scienceFiction }

final class Search {
  const Search(this.genre, this.limit);

  final Genre? genre;
  final int limit;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final genre = b.enumType<Genre>(
    'Genre',
    Genre.values,
    mapping: EnumValueMapping<Genre>(
      nameOf: (value) => switch (value) {
        Genre.fantasy => 'FANTASY',
        Genre.scienceFiction => 'SCIENCE_FICTION',
      },
    ),
  );
  final genreArg = Arg('genre', genre.nullable);
  final limitArg = Arg('limit', b.int, defaultValue: 10);
  final afterArg = Arg.optional('after', b.string.nullable);
  final search = ArgumentsDef<Search>([
    genreArg,
    limitArg,
  ], (args) => Search(args.get(genreArg), args.get(limitArg)));
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('count', b.int, args: [limitArg, afterArg]).resolve((
        parent,
        args,
        context,
        info,
      ) {
        final limit = args.get(limitArg);
        return switch (args.get(afterArg)) {
          Present() => limit,
          Absent() => limit * 2,
        };
      }),
      t
          .field('titles', b.list(b.string))
          .resolveWith(
            search,
            (parent, args, context, info) => [
              'at most ${args.limit} of ${args.genre}',
            ],
          ),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
enum Genre {
  FANTASY
  SCIENCE_FICTION
}

type Query {
  count(limit: Int! = 10, after: String): Int!
  titles(genre: Genre, limit: Int! = 10): [String!]!
}
```

## Input objects

`b.inputObject<T>(name, fields: ..., decode: ...)` declares an input object
decoded to your class `T`. Its fields are `Arg`s, read in `decode` through
the same `Arguments`. `encode` is needed only when an `Arg` of this type has
a default value, which the schema writes as a literal.
`b.oneOfInputObject` declares an input object with `@oneOf`: exactly one of
its fields is given. `b.inputList(item)` is the list type for inputs.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Range {
  const Range(this.from, this.to);

  final int from;
  final int to;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final from = Arg('from', b.int, defaultValue: 0);
  final to = Arg('to', b.int);
  final range = b.inputObject<Range>(
    'Range',
    fields: () => [from, to],
    decode: (values) => Range(values.get(from), values.get(to)),
  );
  final byId = Arg('id', b.id.nullable);
  final byName = Arg('name', b.string.nullable);
  final lookup = b.oneOfInputObject<String>(
    'Lookup',
    fields: () => [byId, byName],
    decode: (values) => values.get(byId) ?? values.get(byName) ?? '',
  );
  final rangeArg = Arg('range', range);
  final lookupArg = Arg('by', lookup);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('width', b.int, args: [rangeArg]).resolve((
        parent,
        args,
        context,
        info,
      ) {
        final value = args.get(rangeArg);
        return value.to - value.from;
      }),
      t
          .field('find', b.string.nullable, args: [lookupArg])
          .resolve((parent, args, context, info) => args.get(lookupArg)),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
input Range {
  from: Int! = 0
  to: Int!
}

input Lookup @oneOf {
  id: ID
  name: String
}

type Query {
  width(range: Range!): Int!
  find(by: Lookup!): String
}
```

## Interfaces and unions

`b.interface<P>(name, fields: ...)` declares an interface over the Dart type
`P`. An object that lists it in `interfaces:` inherits the fields it does
not declare itself (an interface field completed with `declareOnly` is
never inherited), and the build checks that the object's Dart type is a
subtype of `P`. `b.union<P>(name, members: [...])` takes object types whose
Dart types are subtypes of `P`; the compiler checks that, because an
`ObjectTypeDef<Cat>` is an `ObjectTypeDef<Pet>`.

Both pick the object type of a value at run time. Give `resolveType` to
choose it yourself; without it the first possible type whose `accepts` takes
the value is used, which is enough when the Dart types differ. When two
possible types overlap in Dart, the build asks for an explicit `isTypeOf`
on both (`ObjectOptions`), or for `resolveType`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Pet {
  const Pet(this.name);

  final String name;
}

final class Cat extends Pet {
  const Cat(super.name);
}

final class Dog extends Pet {
  const Dog(super.name, this.goodBoy);

  final bool goodBoy;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final named = b.interface<Pet>(
    'Named',
    fields: (t) => [t.field('name', b.string).pure((pet) => pet.name)],
  );
  final cat = b.object<Cat>('Cat', interfaces: [named], fields: (t) => []);
  final dog = b.object<Dog>(
    'Dog',
    interfaces: [named],
    fields: (t) => [t.field('goodBoy', b.boolean).pure((dog) => dog.goodBoy)],
  );
  final animal = b.union<Pet>('Animal', members: [cat, dog]);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('pets', b.list(named)).pure((_) => const <Pet>[Cat('Tom')]),
      t.field('animal', animal).pure((_) => const Dog('Rex', true)),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
interface Named {
  name: String!
}

type Cat implements Named {
  name: String!
}

type Dog implements Named {
  goodBoy: Boolean!
  name: String!
}

union Animal = Cat | Dog

type Query {
  pets: [Named!]!
  animal: Animal!
}
```

## Building and SchemaBuildError

`build({required query, mutation, subscription, options})` assembles every
definition made through the builder, in creation order. It runs the
builder's own checks and then the core's schema validator over the result.
A schema is code, so a problem is a programmer error: `build` throws one
`SchemaBuildError` holding every diagnostic, the builder's first. The
builder's own codes are `GQL300` (an object's Dart type is not a subtype of
the interface it lists), `GQL301` (two possible types of an abstract type
overlap in Dart without an explicit `isTypeOf` on both) and `GQL302` (a
default value cannot be written as a literal). `BuildOptions` holds the extra
directive definitions, `includesDeferAndStream` and the schema description.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Named {}

final class Thing {}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final node = b.interface<Named>(
    'Node',
    fields: (t) => [t.field('id', b.id).pure((_) => '1')],
  );
  b.object<Thing>(
    'Thing',
    interfaces: [node],
    fields: (t) => [t.field('id', b.id).pure((_) => '1')],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
  );
  try {
    b.build(query: query);
  } on Object catch (error) {
    if (error is! SchemaBuildError) rethrow;
    for (final diagnostic in error.diagnostics) {
      print('${diagnostic.code.id}: ${diagnostic.message}');
    }
  }
}
```

It prints:

```text
GQL300: Type "Thing" (Dart type Thing) cannot implement interface "Node": Thing is not a subtype of Named.
```

## Services in the context

The builder never creates your resolvers or services: it takes closures.
Whatever a resolver needs comes from the context `C`, which the caller
supplies for each request, so a dependency injection container, a service
locator or a plain class all fit, and a host framework keeps ownership of
its objects. The context type is a parameter of the builder, so a resolver
that reads `context.library` is checked by the compiler.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Library {
  String titleOf(String id) => 'Title $id';
}

final class Services {
  Services(this.library);

  final Library library;
}

void main() {
  final b = ExecutableSchemaBuilder<Services>();
  final id = Arg('id', b.id);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('title', b.string, args: [id])
          .resolve(
            (parent, args, context, info) =>
                context.library.titleOf(args.get(id)),
          ),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
type Query {
  title(id: ID!): String!
}
```
