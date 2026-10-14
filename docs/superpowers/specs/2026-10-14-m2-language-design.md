# M2 Language: stage design

Status: approved in conversation 2026-10-14; refines section 2 of
[the architecture](2026-10-13-typed-graphql-design.md) and never overrides it
silently. Deviations from it are listed in the last section. Requirements:
R0.1, R0.7, R1.1–R1.11, R10.3, R10.4 ([requirements](../../requirements.md)).

## 1. Scope and delivery

M2 builds the `language/` layer of `packages/typed_graphql` and starts
`packages/typed_graphql_conformance`. One spec, **two plans**, merged one
after the other:

| Plan | Content |
|---|---|
| **M2a** | M1 carry-overs (`Diagnostic` value equality; `strict-inference` and `strict-raw-types` enabled before any new code); AST nodes with `children`, `withChildren` and `isEquivalentTo`; lexer; block-string algorithm; parser (executable and type-system grammar, extensions, options, limits, recovery); `Printer`; parse → print → parse stability; conformance mapping table and the ported lexer, block-string, parser, schema-parser and printer suites |
| **M2b** | `AstVisitor`, `ParallelVisitor`, `AstTransformer`; schema coordinates (AST, parse, print); the remaining ports (visitor, coordinate lexer, `printLocation`); fuzzing; CHANGELOG, `CLAUDE.md` and docs |

Out of scope: a lossless CST (R1.13, LATER), fragment arguments
(R1.14, LATER), resolving a coordinate against a `Schema` (M3), benchmarks
(they wait for the executor), validation rules (M4).

## 2. Public API

Top-level functions are forbidden by the code rules, so the entry points are
methods of one class:

```dart
final class Parser {
  Parser({ParserOptions options = const ParserOptions()});

  ParseResult parse(Source source);                       // a Document
  ParseElementResult<Value> parseValue(Source source);
  ParseElementResult<TypeRef> parseTypeRef(Source source);
  ParseElementResult<SchemaCoordinate> parseSchemaCoordinate(Source source);
}
```

`ParseResult` is the sealed pair of the architecture spec (`ParseSuccess`
with `document`, `ParseFailure` with `partial`, both with `diagnostics`;
`requireDocument()` throws `GraphQLSyntaxException`). `ParseElementResult<T>`
is its sibling for the three single-element entry points:
`ParseElementSuccess<T>(value)` | `ParseElementFailure<T>`, both carrying
`diagnostics`; no partial result. `parseValue` and `parseTypeRef` exist for
code generation and for the ported suites; `parseSchemaCoordinate` uses the
separate coordinate grammar (section 7).

`ParserOptions`:

| Option | Default | Meaning |
|---|---|---|
| `maxTokens` | 15 000 | tokens in one document; `null` disables |
| `maxDepth` | 128 | nesting of selection sets, lists, objects and types; `null` disables |
| `allowDirectiveExtensions` | `false` | working draft: `extend directive @name ...` |
| `allowEmptySelectionSets` | `false` | working draft: `{ }` is a valid selection set |

The parser has one extension point for experimental productions: a document
level hook that the working-draft options use too, so a later RFC grammar is
added without touching the base productions. Fragment arguments are not
parsed: the corresponding graphql-js tests are mapped as `skipped`.

## 3. Source text and lexer

`Source`, `SourceLocation` and `SourceSpan` are M1 types in `diagnostics/`.

`Lexer(Source, DiagnosticSink)` is pull-based: `advance()` returns the next
significant token. It scans with `codeUnitAt` and an `int` cursor, and never
throws (R1.2).

- `Token`: `kind` (`TokenKind`: punctuators, `name`, `int`, `float`,
  `string`, `blockString`, `comment`, `error`, `eof`), `start`, `end`, and the
  decoded value for names, numbers (raw lexeme), strings and block strings.
- **Comments** are produced as `comment` tokens only when the lexer is created
  with `keepComments: true`; the parser does not, a future formatter or LSP
  does. Comments never reach the AST.
- **Unicode (R1.1).** The source is UTF-16; a surrogate pair is one scalar
  value, a lone surrogate is a diagnostic. `\uXXXX` (with a surrogate pair)
  and `\u{...}` escapes validate the scalar value.
- **Block strings** use the exact algorithm of the specification
  (`BlockStringValue`: common indentation, leading and trailing blank lines,
  `\"""`) in a `BlockString` class that the printer reuses.
- **Numbers.** `007`, `1.`, `.5`, `1e`, `0x1` and a name glued to a number
  (`1a`) are lexical errors; the lexeme is kept raw.
- **Limits.** `maxTokens` is counted by the lexer; when it is exceeded the
  lexer reports one diagnostic and returns `eof` from then on.
- Every error yields one `error` token covering the offending run and one
  diagnostic; scanning resumes after it.

## 4. Parser

Hand-written recursive descent, one method per production, each at most 40
lines. The parser is split into collaborators, one per file: a token cursor,
values and types, selections, executable definitions, type-system
definitions, extensions, and the recovery policy. `Parser` itself only wires
them and assembles results.

**Recovery (R1.5).** After a syntax error the parser records one diagnostic
and resynchronises:
- inside a definition it skips tokens to the next definition-start keyword
  (`query`, `mutation`, `subscription`, `fragment`, `schema`, `scalar`,
  `type`, `interface`, `union`, `enum`, `input`, `directive`, `extend`, a `{`
  or a string that starts a description) at brace depth 0, and drops the
  whole failed definition;
- inside a selection set it skips to a token that starts a selection or to
  the closing `}`, and drops the failed selection.

`ParseFailure.partial` therefore holds everything that parsed completely; the
AST has no error or missing nodes. A second diagnostic at an offset that
already has one is not reported, and the sink stops after `maxErrors` as in
M1.

**Depth (R1.6).** `maxDepth` is counted by the parser for selection sets,
lists, objects and types; exceeding it reports one diagnostic and ends the
current definition.

**Diagnostics.** New `GQL0xx` codes are added to `DiagnosticCode` in id order,
each with a doc comment, in the commit that first reports it. The families:
unexpected character, unterminated string and block string, invalid escape,
invalid scalar value, invalid number, expected token, unexpected token,
limit exceeded, working-draft feature disabled, empty selection set.

## 5. AST

Every node extends the abstract class `Node`: `start`, `end` (UTF-16 offsets,
R1.7), `children` (a read-only list in grammar order: never modify it), `withChildren(list)`
(a copy with replaced children, the same instance when nothing changed) and
`isEquivalentTo(other)`. Nodes are immutable `final` classes with primary
constructors and are `const` where possible; they do not override `==`.

`Node` and `Definition` are **not** sealed: the subclasses of a sealed class
must share a library, which cannot hold ~40 nodes under the 300-line limit.
The families below are sealed, one library each:

- `ExecutableDefinition`: `OperationDefinition`, `FragmentDefinition`;
- `TypeSystemDefinition`: schema, scalar, object, interface, union, enum,
  input object, directive definition;
- `TypeSystemExtension`: the schema and six type extensions, plus the
  directive extension behind the option;
- `Selection`: `Field`, `FragmentSpread`, `InlineFragment`;
- `Value`: `Variable`, `IntValue`, `FloatValue`, `StringValue`,
  `BooleanValue`, `NullValue`, `EnumValue`, `ListValue`, `ObjectValue`;
- `TypeRef`: `NamedType`, `ListType`, `NonNullType` (a wrapper).

Other nodes: `Document`, `Name`, `SelectionSet`, `Argument`, `ObjectField`,
`VariableDefinition`, `Directive`, `FieldDefinition`, `InputValueDefinition`,
`EnumValueDefinition`, `OperationTypeDefinition`. Names and descriptions
(`StringValue`) are child nodes, so a diagnostic can point at them exactly.
`IntValue` and `FloatValue` keep the raw lexeme.

`isEquivalentTo` compares the node kind, the node's own scalar fields (raw
lexemes, so `1.0` differs from `1`; the block-string flag; the operation
type) and the children pairwise. Positions are ignored.

## 6. Traversal, transformation, printing

**`AstVisitor`.** `VisitAction enter(Node node)` and `void leave(Node node)`,
both no-ops by default; `VisitAction` is `next`, `skip` (do not enter the
children) or `stop`. A visitor tells kinds apart with a `switch` over the
sealed families. A walker drives it with `children`.

**`ParallelVisitor`** fuses a list of visitors into one walk and keeps the
skip/stop state per visitor, exactly as in graphql-js.

**`AstTransformer`** rebuilds bottom-up. `Node? rewrite(Node node)` returns a
replacement, the same node to keep it, or `null` to remove it from its list
(removing a required child is a `StateError`). Unchanged branches keep their
instance, so identity tells whether anything changed. Code generation adds
`__typename` by rewriting a `SelectionSet`.

**`Printer`.** Canonical output as graphql-js prints it, including the
80-column wrapping of argument and variable lists, so the ported printer
suites hold; a minified mode for the wire and for APQ hashing (no
insignificant whitespace, idempotent under parse → print). The implementation
is split by responsibility: values, executable definitions, type-system
definitions, line wrapping. Printing a `StringValue` reuses `BlockString`.

## 7. Schema coordinates

`SchemaCoordinate` is a sealed family of nodes with its own tiny lexer and
grammar (Section 2 "Schema Coordinates" of September2025; the coordinate
text allows no ignored tokens):

| Node | Text |
|---|---|
| `TypeCoordinate` | `Name` |
| `MemberCoordinate` | `Name.Name` |
| `ArgumentCoordinate` | `Name.Name(Name:)` |
| `DirectiveCoordinate` | `@Name` |
| `DirectiveArgumentCoordinate` | `@Name(Name:)` |

`Parser.parseSchemaCoordinate` parses, `Printer` prints. Meta-fields and
introspection types are not schema elements and have no coordinate. Resolving
a coordinate against a `Schema` belongs to M3.

## 8. Conformance package

`packages/typed_graphql_conformance` depends on `typed_graphql` only and stays
`publish_to: none`.

- Ported graphql-js tests live under `test/language/`, one Dart test per
  graphql-js test, with the same name.
- `mapping/language.csv` lists every test of the graphql-js language
  `__tests__` we consider: graphql-js file, test name, status (`ported`,
  `adapted`, `skipped`), our test (file and name) and, for the last two, the
  reason. `adapted` is for a deliberate design difference (diagnostics instead
  of exceptions, no error node, no `Location` object); `skipped` is for
  behaviour we do not have (fragment arguments, experimental options).
- A test reads the CSV and fails when a `ported` or `adapted` row names a test
  that does not exist, or when a graphql-js file in the language directory has
  no rows.
- **Fuzzing (R10.4).** Two properties, each with a seeded generator and a
  fixed iteration count in CI (a larger count behind an environment
  variable): (1) a random valid AST printed, parsed and compared with
  `isEquivalentTo` is stable, in canonical and minified form; (2) arbitrary
  and mutated text never throws, always terminates, and produces at most
  `maxErrors + 1` diagnostics.

## 9. Testing and platforms

Tests come with the code, in the same commit. The language layer runs in the
VM, AOT (`--compiler exe`), dart2js and dart2wasm, like the rest of the core;
tests that need `dart:io` are `@TestOn('vm')`. The layer test keeps `language`
importing only `diagnostics`. The code-rule ratchet, format and analyze stay
clean after every task; no allowlist grows.

## 10. Deviations from the architecture spec

1. `Node` and `Definition` are not sealed (section 5); the lower families
   are. The architecture spec showed one `Definition` hierarchy.
2. The visitor has a generic `enter`/`leave` pair instead of dispatch through
   an exhaustive `switch` over every node kind (section 6).
3. Added: `ParseElementResult<T>` and the `parseValue`, `parseTypeRef`,
   `parseSchemaCoordinate` entry points (section 2).
4. Added: `Name` is a node, and `Node.children` / `withChildren` exist so the
   traversal tools do not repeat a switch over every kind.
5. Fragment arguments (R1.14) stay out; graphql-js's
   `experimentalFragmentArguments` tests are `skipped` in the mapping table.
6. `Node.children` is documented as read-only rather than wrapped in an
   unmodifiable list, to avoid an allocation per call.
