# Schema

The schema layer turns SDL into an immutable `Schema`, extends it, and prints it
back. A schema is plain data: named types, directive definitions and the names
of the root types. It has no behaviour; the codecs of its scalars are held
apart (see the Scalars & Codecs topic).

## Building a schema from SDL

Parse the SDL with the language layer, then build:
`SchemaBuilder().fromSdl(document, source:)` returns a sealed `BuildResult`:

- `BuildSuccess(schema)` when the SDL has no construction problem.
- `BuildFailure(partial, diagnostics)` when it has. `partial` is everything that
  could be built; what an error is about is left out. `diagnostics` holds every
  problem, `GQL1xx` codes with the place in the document, ordered by position.

`source` is the text the document was parsed from. It gives every element and
every diagnostic its span; without it the spans are null. The built-in scalars,
directives and introspection types are in every schema without being declared
(see Built-ins below). Extensions (`extend type`, `extend schema`, ...) in the
document are applied while building.

```dart
import 'package:typed_graphql/typed_graphql.dart';

const sdl = '''
"A character of the saga."
interface Character {
  id: ID!
  name: String!
}

type Human implements Character {
  id: ID!
  name: String!
  homePlanet: String @deprecated(reason: "Use origin.")
}

type Droid implements Character {
  id: ID!
  name: String!
  primaryFunction: String
}

union SearchResult = Human | Droid

enum Episode {
  NEWHOPE
  EMPIRE
  JEDI
}

type Query {
  hero(episode: Episode = JEDI): Character
  search(text: String!): [SearchResult!]!
}
''';

void main() {
  final source = Source(sdl, name: 'schema.graphql');
  final document = const Parser().parse(source).requireDocument();
  final result = const SchemaBuilder().fromSdl(document, source: source);
  if (result case BuildSuccess(:final schema)) {
    print('query root: ${schema.queryTypeName}');
    print('mutation root: ${schema.mutationTypeName}');
    for (final type in schema.types) {
      print('${type.name}: ${describe(type)}');
    }
  }
}

String describe(SchemaType type) => switch (type) {
  ScalarType() => 'scalar',
  ObjectType(:final fields) => 'object with ${fields.length} fields',
  InterfaceType(:final fields) => 'interface with ${fields.length} fields',
  UnionType(:final memberTypes) => 'union of ${memberTypes.length}',
  EnumType(:final values) => 'enum of ${values.length}',
  InputObjectType(:final fields) => 'input object with ${fields.length}',
};
```

It prints:

```text
query root: Query
mutation root: null
Character: interface with 2 fields
Human: object with 3 fields
Droid: object with 3 fields
SearchResult: union of 2
Episode: enum of 3
Query: object with 2 fields
```

`SchemaBuilder(includesDeferAndStream: true)` adds `@defer` and `@stream`, which
graphql-js defines and the specification does not yet.

## Reading a schema

`Schema` lists what was declared, in declaration order: `types`, `directives`,
and the names of the roots (`queryTypeName`, `mutationTypeName`,
`subscriptionTypeName`; `rootTypeName(operation)` picks one by `OperationType`).
`typeNamed(name)` and `directiveNamed(name)` find an element, the built-ins
included, or return null.

The elements of the model:

| Class | Is |
|---|---|
| `SchemaType` | The sealed family of named types: `ScalarType`, `ObjectType`, `InterfaceType`, `UnionType`, `EnumType`, `InputObjectType` |
| `SchemaField` | A field of an object or interface: `name`, `type`, `arguments`, `description` |
| `InputValue` | An argument or an input field, with its `defaultValue` |
| `SchemaEnumValue` | A value of an enum |
| `SchemaDirective` | A directive definition: `arguments`, `isRepeatable`, `locations` (`DirectiveLocation` values, whose `spelling` is the SDL name) |
| `AppliedDirective` | A directive applied to an element, with its arguments as written |

The spec's own names, `FieldDefinition`, `EnumValueDefinition` and
`DirectiveDefinition`, already name syntax tree nodes, so the schema's elements
take a `Schema` prefix.

Types are references by name: a field's `type` is a language `TypeRef`
(`NamedType`, `ListType`, `NonNullType`), and `typeNamed` resolves it. A cyclic
schema therefore needs no special handling. Default values and the arguments of
applied directives are constant `Value` nodes, which `Printer` prints. Every
element has a `span`, and `deprecationReason`, `specifiedByUrl` and `isOneOf`
read the applied directives for you.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
enum Episode { NEWHOPE EMPIRE JEDI }

type Human {
  name: String!
  homePlanet: String @deprecated(reason: "Use origin.")
}

type Query {
  "The hero of an episode."
  hero(episode: Episode = JEDI, limit: Int): Human
}
''');
  final document = const Parser().parse(source).requireDocument();
  final schema = switch (const SchemaBuilder().fromSdl(document)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };
  const printer = Printer();

  final query = schema.typeNamed(schema.queryTypeName!) as ObjectType;
  final hero = query.fieldNamed('hero')!;
  print('${hero.name}: ${printer.print(hero.type)} (${hero.description})');
  for (final argument in hero.arguments) {
    final defaultValue = argument.defaultValue;
    print(
      '  ${argument.name}: ${printer.print(argument.type)}'
      '${defaultValue == null ? '' : ' = ${printer.print(defaultValue)}'}',
    );
  }

  // A reference is a name: resolve it with typeNamed.
  if (hero.type case NamedType(:final name)) {
    print(schema.typeNamed(name.value)?.name);
  }

  final human = schema.typeNamed('Human') as ObjectType;
  print(human.fieldNamed('homePlanet')?.deprecationReason);
  print(human.fieldNamed('name')?.deprecationReason);
  print(schema.typeNamed('Droid'));
}
```

It prints:

```text
hero: Human (The hero of an episode.)
  episode: Episode = JEDI
  limit: Int
Human
Use origin.
null
null
```

## Built-ins

Every schema has the five built-in scalars (`String`, `Int`, `Float`, `Boolean`,
`ID`), the five specified directives (`@include`, `@skip`, `@deprecated`,
`@specifiedBy`, `@oneOf`) and the introspection types (`__Schema`, `__Type`, ...)
without declaring them. `Schema.types` lists only what was declared; `typeNamed`
and `directiveNamed` fall back to `BuiltIns`, which reads their definitions once
from the Appendix of the specification. They have no spans. A document cannot
redefine or extend them (`GQL103`).

`@defer` and `@stream` exist only in a schema built with
`includesDeferAndStream`.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final schema = Schema();

  // Nothing was declared, yet the built-ins are there.
  print(schema.types.length);
  print(schema.typeNamed('String')?.name);
  print(schema.typeNamed('__Schema')?.name);
  final deprecated = schema.directiveNamed('deprecated');
  print(deprecated?.arguments.map((argument) => argument.name).toList());
  print(deprecated?.locations.map((location) => location.spelling).toList());

  // @defer and @stream are opt-in.
  print(schema.directiveNamed('defer'));
  print(Schema(includesDeferAndStream: true).directiveNamed('defer')?.name);

  print(const BuiltIns().scalars.map((scalar) => scalar.name).toList());
  print(const BuiltIns().directives.map((d) => d.name).toList());
}
```

It prints:

```text
0
String
__Schema
[reason]
[FIELD_DEFINITION, ARGUMENT_DEFINITION, INPUT_FIELD_DEFINITION, ENUM_VALUE]
null
defer
[String, Int, Float, Boolean, ID]
[include, skip, deprecated, specifiedBy, oneOf]
```

## Problems in the SDL

A construction problem is a diagnostic, and the build goes on without the
offending part: the first definition of a name wins, a repeated member is
dropped, an extension of a missing type is ignored. A repeat points at its own
name and relates to the definition it repeats. The messages are graphql-js's
SDL-rule messages.

| Code | Reported for |
|---|---|
| `GQL100` | an operation or fragment in the document |
| `GQL101`, `GQL102` | a repeated type or directive name |
| `GQL103` | a definition or extension of a built-in |
| `GQL104`, `GQL105`, `GQL106` | a repeated field, argument or enum value |
| `GQL107`, `GQL108` | a second schema definition, a second root of one operation |
| `GQL109`, `GQL110` | an extension of a missing type, or of a type of another kind |

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
type Query { a: Int }
type Query { b: Int }
extend type Missing { x: Int }
type Other { y: Int }
''', name: 'broken.graphql');
  final document = const Parser().parse(source).requireDocument();

  switch (const SchemaBuilder().fromSdl(document, source: source)) {
    case BuildSuccess():
      print('built');
    case BuildFailure(:final partial, :final diagnostics):
      diagnostics.forEach(print);
      final query = partial.typeNamed('Query') as ObjectType;
      print('Query keeps ${query.fields.map((field) => field.name)}');
      print(partial.types.map((type) => type.name));
  }
}
```

It prints:

```text
broken.graphql:2:6: error GQL101: There can be only one type named "Query".
broken.graphql:3:13: error GQL109: Cannot extend type "Missing" because it is not defined.
Query keeps (a)
(Query, Other)
```

## Extending a schema

Extensions in the same document are applied while building. To extend a schema
that already exists, call `SchemaBuilder().extend(schema, document, source:)`,
graphql-js's `extendSchema`: it applies the definitions and extensions of a
document to a schema and returns a new one, or the same schema when the document
has none. The original is not changed. An extension appends its members,
interfaces, union members and directives after the type's own, in document
order, and the type keeps the span of its definition. A member the schema
already has is an error: `GQL104` for a field, `GQL106` for an enum value. A
type that the schema already has cannot be defined again (`GQL101`).

```dart
import 'package:typed_graphql/typed_graphql.dart';

Schema build(String text) {
  final source = Source(text);
  final document = const Parser().parse(source).requireDocument();
  return switch (const SchemaBuilder().fromSdl(document, source: source)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };
}

void main() {
  final base = build('''
type Query { hero: String }
extend type Query { villain: String }
''');
  final query = base.typeNamed('Query') as ObjectType;
  print(query.fields.map((field) => field.name).toList());

  // A later document extends a schema that already exists.
  final source = Source('''
extend type Query { sidekick: String }
enum Side { LIGHT DARK }
''', name: 'more.graphql');
  final document = const Parser().parse(source).requireDocument();
  final result = const SchemaBuilder().extend(base, document, source: source);
  if (result case BuildSuccess(:final schema)) {
    final extended = schema.typeNamed('Query') as ObjectType;
    print(extended.fields.map((field) => field.name).toList());
    print(schema.types.map((type) => type.name).toList());
  }
  print((base.typeNamed('Query') as ObjectType).fields.length);

  // A member the schema already has is an error.
  final repeated = Source(
    'extend type Query { hero: Int }',
    name: 'dup.graphql',
  );
  const SchemaBuilder()
      .extend(
        base,
        const Parser().parse(repeated).requireDocument(),
        source: repeated,
      )
      .diagnostics
      .forEach(print);
}
```

It prints:

```text
[hero, villain]
[hero, villain, sidekick]
[Query, Side]
2
dup.graphql:1:21: error GQL104: Field "Query.hero" already exists in the schema. It cannot also be defined in this type extension.
```

## Printing a schema

`SchemaPrinter().print(schema)` prints a schema as SDL, laid out as graphql-js's
`printSchema`: the schema definition when it says more than the default root
names (a description, directives, a root with another name, or a type named
`Query`, `Mutation` or `Subscription` that is not a root), then the directive
definitions and the types, in declaration order, separated by a blank line. Unlike
graphql-js, it prints every applied directive as written, so SDL to schema to SDL loses
nothing. `SchemaPrinter(includesBuiltIns: true)` prints the built-in directives,
scalars and introspection types too.

An empty schema prints an empty string, which does not parse: an empty document
is a syntax error.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
"The saga."
schema { query: Root }

directive @cost(units: Int = 1) on FIELD_DEFINITION

type Root {
  hero(episode: Episode = JEDI): String @cost(units: 2)
}

enum Episode {
  NEWHOPE
  JEDI @deprecated(reason: "Retired.")
}
''');
  final document = const Parser().parse(source).requireDocument();
  final schema = switch (const SchemaBuilder().fromSdl(document)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };

  final text = const SchemaPrinter().print(schema);
  print(text);

  // The printed SDL builds the same schema again.
  final again = const Parser().parse(Source(text)).requireDocument();
  if (const SchemaBuilder().fromSdl(again) case BuildSuccess(schema: final s)) {
    print(const SchemaPrinter().print(s) == text);
  }

  // The built-ins are printed only when asked for.
  final full = const SchemaPrinter(includesBuiltIns: true).print(schema);
  print(text.contains('directive @include'));
  print(full.contains('directive @include'));
}
```

It prints:

```text
"""The saga."""
schema {
  query: Root
}

directive @cost(units: Int = 1) on FIELD_DEFINITION

type Root {
  hero(episode: Episode = JEDI): String @cost(units: 2)
}

enum Episode {
  NEWHOPE
  JEDI @deprecated(reason: "Retired.")
}
true
false
true
```

## What building does not check

Building a schema does not validate it. A field may name a type that does not
exist, a root may name a type of the wrong kind, and an object may claim to
implement an interface without its fields; the builder keeps them all as
written. The build reports only what it cannot represent: the problems above.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
type Query { hero: Unknown }
schema { mutation: Query }
''');
  final document = const Parser().parse(source).requireDocument();
  final result = const SchemaBuilder().fromSdl(document);

  // It builds: nothing here is a construction problem.
  print(result is BuildSuccess);
  if (result case BuildSuccess(:final schema)) {
    print(schema.typeNamed('Unknown'));
    print(schema.mutationTypeName);
  }
}
```

It prints:

```text
true
null
Query
```

Checking a schema against the rules of the specification arrives in a later
release of this package.
