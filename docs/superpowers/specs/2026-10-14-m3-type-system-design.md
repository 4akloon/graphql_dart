# M3 Type system: stage design

Status: approved in conversation 2026-10-14; refines section 3 of
[the architecture](2026-10-13-typed-graphql-design.md) and never overrides it
silently. Deviations from it are listed in the last section. Requirements:
R0.1–R0.3, R0.7, R2.1–R2.9, R10.3, R10.4 ([requirements](../../requirements.md)).

## 1. Scope and delivery

M3 builds the `schema/` layer of `packages/typed_graphql` and grows
`packages/typed_graphql_conformance`. One spec, **two plans**, merged one after
the other:

| Plan | Content |
|---|---|
| **M3a** | Schema model; built-in scalars and directives; SDL → `Schema` with every kind of `extend`, and extension of an existing `Schema`; `Schema` → SDL; `ScalarCodec`; conformance table `mapping/schema.csv` and the ported graphql-js `buildASTSchema`, `extendSchema` and `schemaPrinter` suites; the SDL round-trip fuzzer |
| **M3b** | Schema validation (`ValidSchema` / `InvalidSchema`); introspection query and introspection JSON → `Schema` (and `Schema` → introspection JSON); resolving schema coordinates; ported `validateSchema`, `buildClientSchema`, `introspectionFromSchema`, `getIntrospectionQuery` suites; hostile-input fuzzers for SDL, introspection JSON and coordinates; CHANGELOG, `CLAUDE.md`, docs |

Out of scope: the typed builder and `ExecutableSchema` (M5), value coercion at
execution (M5), `SchemaDiff` (M13), `@defer` / `@stream` (M14).

## 2. Layering

`schema/` follows `protocol/` in the layer order (diagnostics < language <
protocol < schema < validation). It may import `diagnostics`, `language` and
`protocol` (`JsonValue`, `DecodeResult` for introspection). It imports no
platform library and no package but `meta`.

## 3. Schema model (M3a; R2.1)

An immutable `Schema` holds, in declaration order, its named types, its
directive definitions and its root operation types (query, mutation,
subscription: each a type name or absent), and an optional description.

- `sealed class SchemaType` with `ScalarType`, `ObjectType`, `InterfaceType`,
  `UnionType`, `EnumType`, `InputObjectType`.
- Members: `SchemaField` (object and interface fields),
  `InputValue` (arguments and input-object fields), `SchemaEnumValue`,
  `SchemaDirective` (arguments, repeatable flag, locations). The `Schema*`
  prefix avoids the names of the language nodes (`NamedType`, `FieldDefinition`,
  `EnumValueDefinition`, `DirectiveDefinition`) that the barrel already exports.
- **References are names.** A field's type is a `TypeRef` (the language-layer
  type node: `NamedType` / `ListType` / `NonNullType`), and `schema.typeNamed(name)`
  resolves it. A cyclic graph stays immutable and needs no `late`.
- **Provenance.** Every element has `SourceSpan? span`: set when the element
  came from SDL, `null` for introspection and the typed builder. The model
  holds no AST besides the const `Value` below, and no resolvers or codecs.
- **Values.** A default value and the arguments of an applied directive are
  const `Value` nodes of the language layer. `AppliedDirective(name,
  arguments)` carries them. SDL printing is exact (`ENUM` is not `"ENUM"`),
  introspection strings go through `Parser.parseValue`, and coercion to a
  JSON-like value happens at execution, by the field's type.
- Descriptions, `@deprecated(reason:)`, `@specifiedBy(url:)` and `@oneOf` are
  read from applied directives into typed accessors (`deprecationReason`,
  `specifiedByUrl`, `isOneOf`) and stay in the applied-directive list so
  printing is faithful.
- Output is deterministic: collections keep declaration order and are never
  hash-ordered.

**Built-ins (R2.6).** `Int`, `Float`, `String`, `Boolean`, `ID` and the
directives `@skip`, `@include`, `@deprecated`, `@specifiedBy`, `@oneOf` exist in
every schema without being declared; `@defer` and `@stream` are added only by
an opt-in. An SDL document may redeclare none of them (a diagnostic).

## 4. Building a schema (M3a; R2.2)

`SchemaBuilder`:

- `fromSdl(Document)` builds a `Schema`; `extend(Schema, Document)` applies the
  type-system definitions and extensions of a document to an existing schema
  (graphql-js `extendSchema`). Executable definitions in the document are a
  diagnostic.
- Every kind of `extend` is applied: schema, scalar, object, interface, union,
  enum, input object.
- **Building does not validate.** An unknown type reference is kept as a name.
  Only problems of the construction itself are reported: a duplicate type or
  directive definition, a duplicate member inside one definition, `extend` of a
  type that does not exist or has another kind, a redeclared built-in. Each is a
  diagnostic `GQL1xx` with a span.
- The result is sealed like `ParseResult`: `BuildSuccess(schema)` or
  `BuildFailure(partial, diagnostics)`, where `partial` holds everything that
  built. Bad input never throws (R0.3).

## 5. Printing (M3a; R2.5)

`SchemaPrinter` prints a `Schema` as graphql-js `printSchema` does: the schema
definition only when it departs from the default root names, types in
declaration order, descriptions as block strings, `@deprecated` and
`@specifiedBy` printed as directives, built-ins omitted. An option includes the
introspection types and built-ins. Printing reuses the language `Printer` for
values and types. SDL → `Schema` → SDL → `Schema` is stable.

## 6. Scalars (M3a; R2.9)

`ScalarCodec<T>`: `DecodeResult<T> decode(JsonValue json)` and `JsonValue
encode(T value)`; bad input is a `DecodeFailure`, not an exception. A literal
`Value` is first converted to a `JsonValue`, so there is no `parseLiteral`.
The five built-in codecs have exact boundaries: `Int` is a signed 32-bit
integer (a float with a fractional part, an out-of-range number and a string
are failures), `Float` is finite, `ID` accepts a string or an integer and
encodes a string. A codec is **not** a field of `ScalarType`: the model has no
behaviour, and the server and client register codecs by scalar name.

## 7. Validation (M3b; R2.3, R2.4)

`SchemaValidator` checks every type-system rule of the specification in one
pass; each rule family is a separate class in `schema/validation/`:

- root operation types exist, are object types and are distinct;
- every referenced type exists: the type of a field, an argument or an input
  field, an implemented interface, a union member, a root type (the builder
  keeps references as names, so it builds a schema with an unknown one);
- names: no `__` prefix outside the introspection types, valid name syntax;
- object and interface types have at least one field; field and argument types
  are output / input types as the position requires;
- interface implementation, including transitive interfaces, field type
  covariance, argument compatibility, additional arguments being optional;
- union members are distinct object types; enums have at least one value;
- input objects: at least one field, no cycle through non-null fields;
- `@oneOf` input objects: fields are nullable and without defaults;
- directives: argument types, uniqueness of non-repeatable directives, valid
  locations, no self-referencing directive definition, `@deprecated` only
  where allowed, applied-directive arguments checked against the definition;
  every applied directive is defined (graphql-js checks this and the unique,
  known and required directive arguments on SDL before building; here the
  validator checks them on any schema).

The result is the sealed `SchemaValidationResult`: `ValidSchema` or
`InvalidSchema(diagnostics)`. `ValidSchema` is a `final class` with a private
constructor, obtainable from `SchemaValidator.validate` or from
`ValidSchema.assumeValid(schema)` (trusted schemas). Diagnostics carry a code,
the element's span where it has one, and the schema coordinate of the element
in the message.

## 8. Introspection (M3b; R2.7)

- `IntrospectionQuery` generates the query. Options switch the
  working-draft fields (`isOneOf`, `specifiedByUrl`, descriptions of inputs, the
  deprecation of arguments and input fields) on and off.
- `SchemaBuilder.fromIntrospection(JsonValue)` builds a `Schema` and returns
  the same sealed `BuildResult` as SDL; nothing throws. A malformed response
  (a missing member, a wrong JSON type, an unknown kind or type, a type deeper
  than the query read) is a `GQL150`-`GQL155` diagnostic whose message starts
  with the JSON path, as a `DecodeFailure` prints it (deviation 7). Kind
  misuse (an input type as a field type, a root of the wrong kind) builds and
  is left to schema validation.
- `Schema.toIntrospection()` produces the response (`introspectionFromSchema`).
  Default values are printed as GraphQL literals, as the introspection format
  requires.

## 9. Schema coordinates (M3b; R2.8)

`schema.resolve(SchemaCoordinate)` returns a sealed `CoordinateTarget`
(`TypeTarget`, `FieldTarget`, `ArgumentTarget`, `DirectiveTarget`,
`DirectiveArgumentTarget`, `EnumValueTarget`, `InputFieldTarget`) or `null` when
nothing is there. A `SchemaCoordinate` is the M2b language node. Meta-fields
and introspection types have no coordinate.

## 10. Diagnostics

New `GQL1xx` codes go into `DiagnosticCode` in id order, each with a doc
comment, in the commit that first reports them. Families: SDL construction
(duplicate, unknown extension target, wrong kind, redeclared built-in,
executable definition), validation (one family per rule class of section 7),
introspection decoding.

## 11. Conformance and fuzzing (R0.7, R10.3, R10.4)

- `mapping/schema.csv` lists every test of the graphql-js `utilities` and
  `type` suites we consider, with the statuses of M2 (`ported`, `adapted`,
  `skipped`) and a reason; the coverage test of M2 is extended to this table.
  `skipped` is for behaviour we do not have (resolvers, `GraphQLScalarType`
  hooks, `extensions` bags) and for the experimental features of the
  specification we do not enable.
- Ported tests live under `test/schema/`, one Dart test per graphql-js test with
  the same name.
- Fuzzing, seeded, fixed count in CI and a larger one behind the M2
  environment variables: (1) a random valid `Schema` printed, built and
  compared is stable, and the same through introspection JSON; (2) arbitrary and
  mutated SDL, introspection JSON and coordinate text never throws, always
  terminates, and yields at most `maxErrors + 1` diagnostics.

## 12. Testing and platforms

As in M2: tests with the code, the VM, AOT, dart2js and dart2wasm suites, tests
that need `dart:io` are `@TestOn('vm')`, the quality ratchet and the layer test
stay green after every task, no allowlist grows.

## 13. Deviations from the architecture spec

1. `fromSdl` and `fromIntrospection` return a sealed `BuildResult` instead of
   throwing: an SDL file or a remote response is user input (R0.3). The typed
   builder of M5 still throws `SchemaBuildError`, because its input is code.
2. The model holds const language-layer `Value` nodes for defaults and directive
   arguments; the architecture spec left the representation open.
3. `ScalarCodec` is a separate registry entry, not a field of `ScalarType`
   (the model has no behaviour).
4. `extend(Schema, Document)` is part of M3a, as graphql-js `extendSchema`.
5. The model family is `SchemaType` (not `NamedType`) and the members carry the
   `Schema` prefix (section 3); the architecture spec's names clash with
   language nodes.
6. The hostile-SDL fuzzer for `fromSdl` / `extend` ships with M3a, the
   introspection and coordinate fuzzers with M3b.
7. A malformed introspection response is not a `DecodeFailure`: one response
   can have many problems, so `fromIntrospection` reports them all as
   diagnostics in its `BuildResult`, with the JSON path in each message (M3b
   plan, ruling 2).
7. The printer prints every applied directive as written; graphql-js prints
   only `@deprecated`, `@specifiedBy` and `@oneOf`. SDL to schema to SDL then
   loses nothing.
8. The default-roots check of the printer is stricter than graphql-js's
   `isSchemaOfCommonNames`: a non-root type named `Query`, `Mutation` or
   `Subscription` also forces the schema block, so building the printed SDL
   infers the same roots.
9. Roots named by `extend schema` are not overridden by types named `Query`,
   `Mutation` or `Subscription`; graphql-js's `buildASTSchema` without a
   schema definition does override them.
10. An empty argument description prints the arguments one per line;
    graphql-js, which tests `!description`, keeps them on one line. Matching
    it would lose the empty description when the printed SDL is built again.
11. `extend scalar String` (any built-in) is `GQL103`.
12. `GQL109` has no "Did you mean" suggestion; it also covers an unknown
    `extend directive` target.
