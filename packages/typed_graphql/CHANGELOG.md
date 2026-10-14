# Changelog

## 0.0.1 - Unreleased
- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`. Diagnostics compare by value.
- `JsonValue`, a sealed family for arbitrary JSON; `PathSegment` and
  `DecodeResult`.
- `JsonReader`: JSON text to `JsonValue`, with a nesting limit and no
  exceptions.
- `GraphQLError`: the error format of the spec, read and written.
- `GraphQLRequest` and `ResponsePayload` (`ExecutionResult`,
  `RequestErrorResult`).
- The syntax tree: `Node` (`children`, `withChildren`, `isEquivalentTo`),
  `Name`, `Document`, and the `Value` and `TypeRef` families.
- Executable nodes: `OperationDefinition`, `FragmentDefinition`, the
  `Selection` family, `SelectionSet`, `VariableDefinition`, `Argument`,
  `Directive`.
- Type system nodes: the `TypeSystemDefinition` and `TypeSystemExtension`
  families (with `TypeDefinition` and `TypeExtension`), field, input value,
  enum value and root operation type definitions.
- `Token`, `TokenKind` and `BlockString` (block string values and
  printing).
- `Lexer`: names, numbers (raw lexemes), punctuators, comments, strings
  with escapes and block strings, and a token limit, with diagnostics
  `GQL001`–`GQL006` instead of exceptions.
- `Parser` with `ParserOptions` (`maxTokens`, `maxDepth`, working-draft
  switches): `parseValue` and `parseTypeRef` return a
  `ParseElementResult`; diagnostics `GQL007`–`GQL010`.
- `Parser.parse`: operations, fragments, selections, variables and
  descriptions, with `ParseSuccess` / `ParseFailure(partial)`,
  `requireDocument` and `GraphQLSyntaxException`; error recovery at
  definitions and selections; diagnostics `GQL011`–`GQL012`.
- `Parser.parse` reads schema, type and directive definitions;
  diagnostic `GQL013`.
- `Parser.parse` reads schema and type extensions and, with
  `allowDirectiveExtensions`, the working draft's directive extensions,
  directives on directive definitions and the `DIRECTIVE_DEFINITION`
  location; diagnostic `GQL014`.
- `Printer`: canonical GraphQL text from any node, as graphql-js prints
  it.
- `Printer(isMinified: true)`: GraphQL text without insignificant
  characters, for the wire and persisted-query hashes; parse, print and
  parse again gives an equivalent tree in both forms.
- Parser recovery no longer mistakes a directive named like a keyword
  (`@query`) for the start of a definition.
- `NonNullType.withChildren` throws a `StateError` in release builds too.
- `AstVisitor`, `VisitAction` and `AstWalker`: a depth-first walk of any
  syntax tree with `enter` and `leave`, which can skip a subtree or stop.
- `ParallelVisitor`: several visitors in one walk, each called as if it
  walked alone.
- `AstTransformer`: rebuilds a syntax tree bottom-up; `rewrite` keeps,
  replaces or removes a node, and unchanged branches keep their instance.
  Removing the name of a `Field` with an alias or of a
  `DirectiveDefinition` is a `StateError`, not a silent rename.
- Schema coordinate nodes: the `SchemaCoordinate` family
  (`TypeCoordinate`, `MemberCoordinate`, `ArgumentCoordinate`,
  `DirectiveCoordinate`, `DirectiveArgumentCoordinate`).
- `SchemaCoordinateLexer` and `TokenKind.dot`: the tokens of a schema
  coordinate, with `GQL001` for any character a coordinate cannot hold;
  `Lexer` and `SchemaCoordinateLexer` implement `TokenSource`.
- `Parser.parseSchemaCoordinate`: a schema coordinate such as
  `Query.hero(episode:)` as a `ParseElementResult<SchemaCoordinate>`.
- `Printer` prints schema coordinates, the same in both forms.
- `SourceExcerpt` and `SourceSpan.excerpt`: a location shown in its lines
  with a caret, as graphql-js's `printLocation` prints it.
- Schema model elements: `SchemaField`, `InputValue`, `SchemaEnumValue`,
  `SchemaDirective` and `AppliedDirective`, with `deprecationReason` read
  from `@deprecated` and lookups of arguments by name.
- `SchemaType`, the sealed family of named types: `ScalarType`
  (`specifiedByUrl`), `ObjectType`, `InterfaceType`, `UnionType`,
  `EnumType` and `InputObjectType` (`isOneOf`), with lookups by name.
- `BuiltIns`: the built-in scalars (`String`, `Int`, `Float`, `Boolean`,
  `ID`), the five specified directives, `@defer` and `@stream`, and the
  introspection types of September2025.
- `Schema`: declared types and directives in declaration order, root
  operation type names, description and applied directives;
  `typeNamed` and `directiveNamed` also find the built-ins.
