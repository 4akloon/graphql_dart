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
- `SchemaBuilder.fromSdl`: SDL to a `Schema` without validating, as the
  sealed `BuildResult` (`BuildSuccess`, `BuildFailure` with the partial
  schema); root types from the schema definition or the types named
  `Query`, `Mutation` and `Subscription`; `GQL100` for an operation or a
  fragment in the document; `includesDeferAndStream` opt-in.
- The builder keeps the first type or directive of each name: `GQL101`
  and `GQL102` for a repeat, `GQL103` for a redefined built-in scalar,
  introspection type or directive.
- The builder keeps the first member of each name: `GQL104` for a
  repeated field or input field, `GQL105` for a repeated argument,
  `GQL106` for a repeated enum value.
- The builder applies schema extensions; `GQL107` for a second schema
  definition, `GQL108` for a second root type of one operation.
- The builder applies type extensions of every kind; `GQL109` for an
  extension of a missing type, `GQL110` for one of another kind,
  `GQL103` for one of a built-in.
- `SchemaBuilder.extend`: applies a document's definitions and extensions
  to an existing `Schema` (graphql-js's `extendSchema`), giving the schema
  back when the document has none; directive extensions (working draft)
  are applied too.
- `SchemaPrinter`: a schema's types as SDL, laid out as graphql-js's
  `printSchema`, with every applied directive printed as written.
- `SchemaPrinter` prints the schema definition when it says more than the
  default root names, and the directive definitions; `includesBuiltIns`
  adds the built-in directives, scalars and introspection types.
- `ScalarCodec<T>` (`decode` to a `DecodeResult`, `encode` to a
  `JsonValue`) and the built-in codecs `IntCodec` (signed 32-bit),
  `FloatCodec` (finite), `StringCodec`, `BooleanCodec` and `IdCodec`.
- `ScalarCodecs`: an immutable registry of codecs by scalar name, with the
  built-in ones; `LiteralConverter`: a constant literal to the `JsonValue`
  a codec decodes.
- `BuiltIns.isBuiltInDirective`: whether a name is a built-in directive,
  `@defer` and `@stream` by a flag. Extending one type or directive many
  times builds in linear time.
- Documentation: six guides (getting started, language, diagnostics, wire
  protocol, schema, scalars and codecs), a runnable `example/example.dart`
  and `dart doc` categories for every exported type. The programs in the
  guides are run by the test suite.
- **Breaking:** `SchemaDirective.locations` is a `List<DirectiveLocation>`.
  `DirectiveLocation` names the nineteen September2025 locations and the
  working draft's `DIRECTIVE_DEFINITION` (`spelling`, `named`,
  `isExecutable`); the parser accepts exactly its spellings.
- **Breaking:** the interfaces of `ObjectType` and `InterfaceType` and the
  members of `UnionType` are `NamedTypeReference`s (a name and a span)
  instead of `NamedType` nodes, so a reference added by `extend` from
  another source points into that source. `Schema.rootTypeSpan` gives
  where a root type was named (`rootTypeSpans` in the constructor).
- `SchemaType.isInputType`, `isOutputType`, `isLeafType`,
  `isCompositeType` and `isAbstractType`; `Schema.namedTypeOf`,
  `isInputType`, `isOutputType` (for a `TypeRef`), `implementations`,
  `possibleTypes`, `isSubType`, `isTypeSubTypeOf` and `typesOverlap`, as
  graphql-js names them, for validation and execution.
- `SchemaValidator` and the sealed `SchemaValidationResult`: `ValidSchema`
  (made only by the validator or `ValidSchema.assumeValid`) or
  `InvalidSchema(schema, diagnostics)`. The root-type rules: `GQL111` for
  a missing query root, `GQL112` for a root that is not an object type,
  `GQL113` for one type used as two roots.
- Schema validation checks names: `GQL114` for a name that begins with
  `__`, `GQL115` for a name of invalid syntax and `GQL013` for an enum
  value named `true`, `false` or `null`; and, in a schema built in code,
  repeated types, directives, fields, arguments and enum values
  (`GQL101`–`GQL106`, the builder's messages) and redefined built-ins
  (`GQL103`).
- Schema validation reports unknown types (`GQL116`, at the type name; a
  root that names no type included) and checks applied directives: unknown
  (`GQL117`), misplaced (`GQL118`), repeated when not repeatable
  (`GQL119`), with a repeated (`GQL120`), unknown (`GQL121`) or missing
  required (`GQL122`) argument, with graphql-js's SDL-rule messages.
  `TypeComparator.namedType` gives the named type node inside wrappers.
- Schema validation checks constant values against their input types,
  with graphql-js's `validateInputLiteral` messages and paths: default
  values of arguments and input fields (`GQL123`) and the arguments of
  applied directives (`GQL124`), `@oneOf` input objects included.
- Schema validation checks fields and directive definitions: an object or
  interface type without fields (`GQL125`), a field of an input type
  (`GQL126`), an argument or input field of an output type (`GQL127`), a
  deprecated required argument or input field (`GQL128`), a directive
  without locations (`GQL129`) and a directive that references itself,
  directly or through types and directives (`GQL130`).
- Schema validation checks implemented interfaces, with graphql-js's
  messages: a non-interface (`GQL131`), a circular implementation
  (`GQL132`), a repeat (`GQL133`), a missing inherited interface
  (`GQL134`), and, for each interface field, a missing field (`GQL135`),
  a field type that is not a subtype (`GQL136`), a missing argument
  (`GQL137`), an argument of another type (`GQL138`), an added required
  argument (`GQL139`) and a deprecated implementation of a live field
  (`GQL140`).
- Schema validation checks unions, enums and input objects, with
  graphql-js's messages: a union without members (`GQL141`), with a
  repeated member (`GQL142`) or a member that is not an object type
  (`GQL143`); an enum without values (`GQL144`); an input object without
  fields (`GQL145`); a `@oneOf` field that is non-null (`GQL146`) or has a
  default (`GQL147`); an input object that cannot be given a finite value
  (`GQL148`) and a default value that contains itself (`GQL149`).
- `IntrospectionQuery`: graphql-js's `getIntrospectionQuery` as a const
  value with `includes*` flags and `typeDepth` (0 to 100, else a
  `RangeError`); `text` is the query. `IntrospectionQuery.full` reads
  every field September2025 introspection has.
- `Schema.toIntrospection([query])` writes the schema as the `data` of its
  answer to an `IntrospectionQuery` (graphql-js's
  `introspectionFromSchema`), `IntrospectionQuery.full` by default: the
  declared types, the built-in scalars they use, then the introspection
  types; the declared directives, then the built-in ones. A reference to
  a type the schema lacks is an `ArgumentError`.
- `SchemaBuilder.fromIntrospection(result)` builds a schema from the `data`
  of an introspection result (graphql-js's `buildClientSchema`) and returns
  the sealed `BuildResult`: structural problems are `GQL150` to `GQL155`
  diagnostics whose message starts with the JSON path. Built-in types and
  directives in the result stay undeclared; listing `@defer` or `@stream`
  turns on `includesDeferAndStream`.
- `Schema.toIntrospection` lists every member of a union, also one that is
  not an object, so the validator sees it after a round trip.
- `Schema.resolve(SchemaCoordinate)` finds the element a schema coordinate
  names as a sealed `CoordinateTarget` (`TypeTarget`, `FieldTarget`,
  `ArgumentTarget`, `InputFieldTarget`, `EnumValueTarget`,
  `DirectiveTarget`, `DirectiveArgumentTarget`), or null: also when a
  containing element is missing or of the wrong kind, and for meta-fields
  and introspection types, which are not schema elements.
- The Schema guide covers validating a schema and resolving a schema
  coordinate, and the new Introspection guide covers the introspection query
  and results; the new types carry their dartdoc category.
- Hardening of schema validation against hostile input: constant-time
  sub type and overlap queries, linear-time union, implementation and
  directive-reference rules, rules that stop at the error limit, and
  `Int` literals checked before they are parsed. A value in a validation
  message prints in full only when small (a deviation from graphql-js);
  an introspection result with more than 100 `ofType` wrappers is `GQL155`.
- `IntrospectionQuery.checkTypeDepth()` is the range check of `typeDepth`;
  `Schema.toIntrospection` calls it, so a depth outside 0 to 100 is a
  `RangeError` there too. The introspection reader ignores directive
  deprecation and drops a result's redefinition of a built-in directive; the
  Introspection guide and the M3 spec list these and the other differences
  from graphql-js.
- pub.dev metadata and README: a description and an opening sentence that say
  what the package does today, a "Should I use this?" section after Install,
  the topics `graphql`, `parser`, `ast`, `sdl` and `schema`, and a
  `repository` URL that points at the package folder; pub.dev is expected to
  rewrite relative README links from it (to confirm at M16).
