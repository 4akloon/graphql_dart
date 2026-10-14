# M2a Language Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the core's `language/` layer up to printing, and start measuring conformance. The layer has:
- the syntax tree, with `children`, `withChildren` and `isEquivalentTo`;
- the lexer and the block-string algorithms;
- an error-resilient parser of the whole September2025 grammar, with limits and the working-draft options;
- a printer with canonical and minified output that is stable under parse → print → parse.

The conformance package gets its mapping table and the ported graphql-js lexer, block-string, parser, schema-parser and printer suites. Every graphql-js test of those seven files gets a row.

**Architecture:** `packages/typed_graphql/lib/src/language/` gets four folders. `language` imports only `diagnostics`, which `layers_test.dart` already enforces.
- `ast/`: an abstract `Node` and the sealed families `Value`, `TypeRef`, `Selection`, `ExecutableDefinition`, `TypeSystemDefinition` (with the sealed `TypeDefinition`) and `TypeSystemExtension` (with the sealed `TypeExtension`), one library each. `ChildReader` (internal) rebuilds a node from new children.
- `lexer/`: `Token`, `TokenKind`, `BlockString`, and the pull-based `Lexer`. The lexer delegates to scanners over a shared `SourceReader`.
- `parser/`: a `const` `Parser` that, per call, builds a `TokenCursor` and grammar collaborators, one per file. A syntax error throws the internal `SyntaxAbort`, which never leaves `Parser`. `Recovery` resynchronises, and `DefinitionGrammar` is the extension point for draft grammar.
- `printer/`: `Printer` and its collaborators over `PrintLayout`; `Minifier` strips the canonical text.

`packages/typed_graphql_conformance` gets `mapping/language.csv` and a test that checks it. Its port helpers live in `test/support/`, and the ported suites in `test/language/`.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, patterns, sealed classes), `package:test`, `package:meta`. graphql-js 17.0.2 (commit `ee5ce41`, fetched into `reference/` by `tool/fetch_reference.sh`) is the reference. Chrome runs dart2js and dart2wasm.

**Spec:** `docs/superpowers/specs/2026-10-14-m2-language-design.md` (the M2a row of its section 1), section 2 of `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`, and `docs/requirements.md` (R0.1–R0.7, R1.1–R1.8, R1.10, R1.12, R10.2, R10.3).

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, not even a private one; a helper in a test is a local closure inside `main` or a method of a class.
- The core stays pure Dart: no new dependency, and no `dart:io` in `lib/`. The language tests run on the VM, as exe, with dart2js and with dart2wasm (R0.6). A test that needs `dart:io` starts with `@TestOn('vm')` and then `library;`. A test that runs on the web has no integer literal above 2^53.
- No new package dependency in this stage. The conformance package depends on `typed_graphql` only (spec §8); Task 15 removes its other workspace dependencies.
- Bad input never throws (R0.3). A lexer or parser problem is a `Diagnostic` with a code from `DiagnosticCode`. Only programmer errors throw, as `ArgumentError`, `RangeError` or `StateError`. A new code goes into the catalog, in id order and with its doc comment, in the task that first reports it.
- Public API goes through the barrel `lib/typed_graphql.dart`. A collaborator that is not API (`TokenCursor`, the `*_parser.dart` and `*_printer.dart` collaborators, the scanners, `ChildReader`, the rebuilders) stays out of it.
- Messages are graphql-js's text without the `Syntax Error: ` prefix, so the ported suites compare them unchanged.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- `CLAUDE.md` and the package `CHANGELOG.md` change in the task that changes what they describe; the steps give those changes.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message given in the task. Executors append the trailers their session instructs.
- Run every command from the repository root unless a step says otherwise. Use `(cd packages/<name> && …)` so the shell stays at the root.

## Review Focus

These are the five failure modes most likely to hurt a user who parses untrusted documents. Each one has tests that pin it, in the task named.

1. **Hostile nesting and size (R1.6).** Take 100 000 nested selection sets, a document of 20 000 tokens, or 300 broken definitions. Each must end with one limit diagnostic, or with the sink's `GQL000`, and never with a stack overflow, on the VM or on the web. Pinned in:
   - Task 7: `replaces the token after the limit by one error and the end`;
   - Task 8: `accepts nesting up to maxDepth`, `reports one error at the level past maxDepth`;
   - Task 9: `a document past maxDepth loses only the deep definition`, `a full sink stops the parse`;
   - Task 14: `a selection set 100 000 levels deep gives one depth error`, `the token limit stops a long document with one error`, `the sink stops after maxErrors errors with GQL000`. Task 19 runs them with dart2js and dart2wasm.
2. **Lone surrogates and Unicode escapes (R1.1).** A lone surrogate in a name position, a comment, a string or a block string must give one `GQL002` with graphql-js's `U+D800` text. An escape must be validated as a Unicode scalar value. Pinned in:
   - Task 6: `reports a lone surrogate as an invalid character`, `a comment ends before a lone surrogate`;
   - Task 7: `reject a lone surrogate`, `quote the text graphql-js quotes for bad Unicode escapes`, `reject a lone surrogate and skip to the closing quotes`;
   - Task 14: `a lone surrogate in a selection is one error`.
3. **Numbers keep their lexeme (R1.8).** An integer past 64 bits must not be rounded or rejected. `1.0` must stay distinct from `1.00`. `1a`, `1.`, `.5`, `00` and `0x1` must each be one error. Pinned in:
   - Task 6: `keeps the lexeme of integers and floats`, `rejects a leading zero`, `rejects a name or a dot glued to a number`, `rejects a number without its integer part`;
   - Task 2: `compares raw lexemes, so 1.0 differs from 1.00`;
   - Task 14: `an integer past 64 bits keeps its raw lexeme`.
4. **Block-string edge cases.** The following must round-trip through lexer and printer exactly as graphql-js does: `\r\n` and `\r` inside a block string, escaped triple quotes, a trailing backslash, a first line with indentation, and blank edge lines. Pinned in:
   - Task 5: `treats CR LF and CR as line terminators`, `escapes triple quotes and puts them on their own lines`, `a trailing backslash forces a trailing line break`, `a value with internal indentation starts on a new line`;
   - Task 7: `unescape triple quotes only`;
   - Task 13: `prints block strings in their shortest form`;
   - Task 16: all 25 tests of `blockString-test.ts`.
5. **Unterminated and broken input (R1.5).** Input that stops in a string, a block string, a selection set or an argument list must give exactly one error and end. Broken definitions must not hide the good ones. Pinned in:
   - Task 9: `reports every broken definition and keeps the others`, `an unterminated definition gives one error`, `an unclosed selection set fails the definition once`, `drops a failed selection and keeps the rest`;
   - Task 14: the group `unterminated input gives one error and ends` (four tests).

## M2a design decisions

These were made while writing this plan; the spec leaves them open.

1. **`Parser` is `const` and stateless.** Each call builds a `Lexer`, a `TokenCursor` and the grammar collaborators. The entry points are `parse(Source)`, `parseValue(Source, {isConst})` and `parseTypeRef(Source)`; `parseSchemaCoordinate` arrives in M2b. `isConst` is graphql-js's `parseConstValue`: the ported suite and code generation both need constant values.
2. **Syntax errors unwind with an internal exception.** `TokenCursor.fail` reports the diagnostic and throws `SyntaxAbort`, which `Parser` and `Recovery` catch. It never leaves `Parser`, so the public rule "bad input never throws" holds. A recursive descent without it would have to check a result after every production.
3. **Recovery (R1.5):**
   - `Parser.parse` drops a failed definition and skips to the next definition keyword, `{` or description. `SelectionParser` drops a failed selection and skips to a name, `...` or `}`. Both only resynchronise at the bracket balance where the failed part started, and they always consume a token.
   - A selection set that loses every selection fails too.
   - The cursor stays silent at an `error` token, because the lexer already reported it, and at an offset that already has a diagnostic.
4. **Depth (R1.6)** counts selection sets, lists, objects and list types. Passing `maxDepth` reports `GQL010` once and ends the definition (`SyntaxAbort(endsDefinition: true)`). `maxTokens` is counted by the lexer, which reports `GQL006` once and then returns `eof`; comments and `eof` are not counted.
5. **The lexer** turns bad text into one `error` token over the run and one diagnostic, then resumes (R1.2). Comments become `comment` tokens only with `keepComments: true`.
6. **Diagnostic codes `GQL001`–`GQL014`:**

   | Code | Name | Task |
   |---|---|---|
   | GQL001 | `unexpectedCharacter` | 6 |
   | GQL002 | `invalidCharacter` | 6 |
   | GQL003 | `invalidNumber` | 6 |
   | GQL004 | `unterminatedString` | 7 |
   | GQL005 | `invalidEscapeSequence` | 7 |
   | GQL006 | `tokenLimitExceeded` | 7 |
   | GQL007 | `expectedToken` | 8 |
   | GQL008 | `unexpectedToken` | 8 |
   | GQL009 | `variableInConstant` | 8 |
   | GQL010 | `depthLimitExceeded` | 8 |
   | GQL011 | `misplacedDescription` | 9 |
   | GQL012 | `emptySelectionSet` | 9 |
   | GQL013 | `reservedEnumValueName` | 10 |
   | GQL014 | `workingDraftFeatureDisabled` | 11 |

7. **The syntax tree:**
   - Every node has `children` in graphql-js key order and `scalars`, its own compared fields. `isEquivalentTo` compares the node kind, `scalars` and the children, and ignores positions.
   - `withChildren(list)` returns `Node` and keeps the instance when nothing changed. A node implements it through `rebuildFrom(ChildReader)`; the two type-system families delegate that to a `*_rebuilder.dart`, to stay under the size limit.
   - `TypeDefinition` and `TypeExtension` are sealed sub-families inside the type-system libraries, so a `switch` can cover the six type kinds.
   - `Name` is a node and descriptions are `StringValue` nodes, so a diagnostic can point at them.
8. **`allowDirectiveExtensions` gates three productions** of the working draft:
   - `extend directive @name @directives`;
   - directives on a directive definition;
   - the `DIRECTIVE_DEFINITION` location.

   With the option off, each one reports `GQL014` with a message that names the option. `DirectiveExtensionGrammar`, the first user of the `DefinitionGrammar` extension point (R1.4), is always registered so that it can give that message.
9. **The printer** is a port of graphql-js's `print`, through collaborators:
   - `ValuePrinter`, `ExecutablePrinter`, `TypeMemberPrinter`, `TypeSystemPrinter` and `ExtensionPrinter`;
   - the `PrintLayout` combinators;
   - `QuotedString`, a port of `printString`.

   `Printer(isMinified: true)` passes the canonical text through `Minifier`, which follows graphql-js's `stripIgnoredCharacters`. A node class the library does not define is an `ArgumentError`, a programmer error.
10. **An empty selection set prints as `{}`.** graphql-js prints nothing for it, which would drop the field's selection set on a round trip under `allowEmptySelectionSets`.
11. **Conformance helpers are test code.** `LexerPort`, `ParserPort`, `AstJson`, `ErrorJson`, `Contain`, `Dedent`, `KitchenSink` and `SchemaNodes` live in `test/support/`, one class per file. `CsvTable` and `GraphqlJsSuite` read the table and the graphql-js sources. `AstJson` writes every field that graphql-js sets, with `null` for `undefined`; `ListValue.values`, `ObjectValue.fields`, `SelectionSet.selections`, `Document.definitions`, `DirectiveDefinition.locations` and `SchemaDefinition.operationTypes` are always lists, and other lists are `null` when empty.
12. **Repository files.**
    - The ported tests derive from MIT code, so `LICENSE-graphql-js` (graphql-js's license) sits next to the conformance package's own `LICENSE`.
    - `.gitattributes` pins `eol=lf`, because test sources hold multi-line literals whose line ends are data.
    - `blockString-fuzz.ts` moves to M2b with the fuzzing.

## Spec deviations and findings

Bring these to the user with the plan.

1. **The mapping check covers the ported files only.** Spec §8 says the check fails when a graphql-js file in the language directory has no rows. M2a ports seven of its 15 files. The other eight get their rows in M2b: `visitor-test.ts`, `schemaCoordinateLexer-test.ts`, `printLocation-test.ts`, `blockString-fuzz.ts`, `source-test.ts`, `predicates-test.ts`, `kind-test.ts` and `diagnostics-test.ts`. The spec's M2b row names only the first three, so the M2b plan must also cover the other five. So `mapping_test.dart` checks the files named in `portedFiles`, and M2b turns it into a check of the whole directory. The coverage check needs `reference/`, so CI, which does not fetch it, skips that check. Run it locally.
2. **`allowDirectiveExtensions` covers more than spec §2 says** (decision 8). The working draft that adds `extend directive` also adds directives on directive definitions and the `DIRECTIVE_DEFINITION` location, and graphql-js 17 parses all three. The option keeps the September2025 baseline (R0.1) by default.
3. **`parseValue` has `isConst`** (decision 1). Spec §2 shows `parseValue(Source)` only.
4. **`Parser` has a `const` constructor** with a final `options` field; spec §2 shows a plain constructor.
5. **An empty selection set prints as `{}`** (decision 10); graphql-js prints nothing.
6. **`Node` is extensible outside the library, but `rebuildFrom` takes the internal `ChildReader`.** An outside subclass can override it with a wider parameter type (`Object? read`), which the printer suite's foreign node does. Exporting `ChildReader`, or a sealed root, is a question for M2b's `AstTransformer`.
7. **Recovery cannot resynchronise inside unbalanced brackets.** If a `(` or `[` is never closed, recovery finds no definition boundary again. The rest of the document is lost from the partial tree, and later errors may go unreported. For example, `query { a(x: [1 }` followed by two more definitions gives one diagnostic and an empty partial document. This is safe, since there is always at least one error and the parse ends. graphql-js stops at the first error anyway.
8. **What the ported suites change.** Each such row is `adapted` or `skipped`, with its reason, and needs nothing from the library:
   - graphql-js's `printLocation` excerpt arrives in M2b;
   - `Source` has no `locationOffset`;
   - tokens are not linked;
   - nodes carry offsets and no `Location` object;
   - fragment arguments are R1.14, LATER;
   - schema coordinates arrive in M2b.

   A full port of all seven files was made against this plan's library while verifying it: 182 rows, 152 Dart tests. Every ported expectation passed unchanged. The library had no mismatch with graphql-js.
9. **What could not be verified locally:** the CI matrix on exactly 3.13.0, macOS and Windows. Everything else in the green check and in Task 19 ran on Linux with Dart 3.13.1 and Chrome.

## File map

| Path | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/language/ast/child_reader.dart` | Reads the list given to [Node.withChildren] back into a node's fields, in grammar order, for [Node.rebuildFrom] | 2 |
| `packages/typed_graphql/lib/src/language/ast/definition.dart` | A top-level definition of a [Document] | 2 |
| `packages/typed_graphql/lib/src/language/ast/document.dart` | A GraphQL document | 2 |
| `packages/typed_graphql/lib/src/language/ast/name.dart` | A name, such as a field, type or argument name (spec §2.1.9) | 2 |
| `packages/typed_graphql/lib/src/language/ast/node.dart` | A node of the syntax tree of a GraphQL document | 2 |
| `packages/typed_graphql/lib/src/language/ast/object_field.dart` | One field of an [ObjectValue], `name: value` (spec §2.9.8) | 2 |
| `packages/typed_graphql/lib/src/language/ast/type_ref.dart` | A reference to a type | 2 |
| `packages/typed_graphql/lib/src/language/ast/value.dart` | An input value as written in a document (spec §2.9) | 2 |
| `packages/typed_graphql/test/language/ast/node_test.dart` | Tests | 2 |
| `packages/typed_graphql/test/language/ast/rebuild_check.dart` | Checks [Node.withChildren] on one node and everything under it | 2 |
| `packages/typed_graphql/test/language/ast/value_test.dart` | Tests | 2 |
| `packages/typed_graphql/lib/src/language/ast/argument.dart` | An argument of a field or directive, `name: value` (spec §2.6) | 3 |
| `packages/typed_graphql/lib/src/language/ast/directive.dart` | A directive applied to a node, `@name(arguments)` (spec §2.12) | 3 |
| `packages/typed_graphql/lib/src/language/ast/executable_definition.dart` | A definition a server executes | 3 |
| `packages/typed_graphql/lib/src/language/ast/operation_type.dart` | The type of an operation (spec §2.3) | 3 |
| `packages/typed_graphql/lib/src/language/ast/selection.dart` | One selection of a [SelectionSet] (spec §2.4) | 3 |
| `packages/typed_graphql/lib/src/language/ast/selection_set.dart` | A selection set, `{ selections }` (spec §2.4) | 3 |
| `packages/typed_graphql/lib/src/language/ast/variable_definition.dart` | A variable definition of an operation, `$name: Type = default @directives` (spec §2.10) | 3 |
| `packages/typed_graphql/test/language/ast/executable_test.dart` | Tests | 3 |
| `packages/typed_graphql/lib/src/language/ast/enum_value_definition.dart` | A value of an enum type, `"desc" NAME @d` (spec §3.9) | 4 |
| `packages/typed_graphql/lib/src/language/ast/field_definition.dart` | A field of an object or interface type, `"desc" name(args): Type @d` (spec §3.6) | 4 |
| `packages/typed_graphql/lib/src/language/ast/input_value_definition.dart` | An argument or input field definition, `"desc" name: Type = default @d` (spec §3.6.1, §3.10) | 4 |
| `packages/typed_graphql/lib/src/language/ast/operation_type_definition.dart` | A root operation type of a schema, `query: Query` (spec §3.3.1) | 4 |
| `packages/typed_graphql/lib/src/language/ast/type_system_definition.dart` | A definition of a schema, a type or a directive (spec §3) | 4 |
| `packages/typed_graphql/lib/src/language/ast/type_system_definition_rebuilder.dart` | Rebuilds a [TypeSystemDefinition] for [Node.withChildren] | 4 |
| `packages/typed_graphql/lib/src/language/ast/type_system_extension.dart` | An extension of a schema, a type or a directive (spec §3) | 4 |
| `packages/typed_graphql/lib/src/language/ast/type_system_extension_rebuilder.dart` | Rebuilds a [TypeSystemExtension] for [Node.withChildren] | 4 |
| `packages/typed_graphql/test/language/ast/type_system_test.dart` | Tests | 4 |
| `packages/typed_graphql/lib/src/language/lexer/block_string.dart` | The block string algorithms | 5 |
| `packages/typed_graphql/lib/src/language/lexer/token.dart` | One lexical token: its kind, its offsets and its value | 5 |
| `packages/typed_graphql/lib/src/language/lexer/token_kind.dart` | The kinds of lexical tokens (spec §2.1.6), plus [comment], [error] and [eof] | 5 |
| `packages/typed_graphql/test/language/lexer/block_string_test.dart` | Tests | 5 |
| `packages/typed_graphql/test/language/lexer/token_test.dart` | Tests | 5 |
| `packages/typed_graphql/lib/src/language/lexer/character_class.dart` | The character classes of the lexical grammar (spec §2.1), over UTF-16 code units | 6 |
| `packages/typed_graphql/lib/src/language/lexer/lexer.dart` | Turns a [Source] into tokens, one per [advance] (spec §2.1) | 6 |
| `packages/typed_graphql/lib/src/language/lexer/number_scanner.dart` | Scans an `IntValue` or a `FloatValue` (spec §2.9.1, §2.9.2), keeping the lexeme as written | 6 |
| `packages/typed_graphql/lib/src/language/lexer/source_reader.dart` | What the scanners of one lexer share | 6 |
| `packages/typed_graphql/test/language/lexer/lexed.dart` | The tokens and diagnostics of lexing one text, for tests | 6 |
| `packages/typed_graphql/test/language/lexer/lexer_test.dart` | Tests | 6 |
| `packages/typed_graphql/lib/src/language/lexer/block_string_scanner.dart` | Scans a block string, `"""..."""` (spec §2.9.4), and computes its value with [BlockString] | 7 |
| `packages/typed_graphql/lib/src/language/lexer/escape_reader.dart` | Reads one escape sequence of a quoted string (spec §2.9.4, `EscapedCharacter` and `EscapedUnicode`) | 7 |
| `packages/typed_graphql/lib/src/language/lexer/string_scanner.dart` | Scans a quoted `StringValue` (spec §2.9.4) and decodes its escapes | 7 |
| `packages/typed_graphql/test/language/lexer/string_test.dart` | Tests | 7 |
| `packages/typed_graphql/lib/src/language/parser/parse_element_result.dart` | The result of parsing one value or type reference | 8 |
| `packages/typed_graphql/lib/src/language/parser/parser.dart` | Parses GraphQL documents and single elements | 8 |
| `packages/typed_graphql/lib/src/language/parser/parser_options.dart` | What a `Parser` accepts: the limits and the working-draft grammar | 8 |
| `packages/typed_graphql/lib/src/language/parser/syntax_abort.dart` | Unwinds the parser from a syntax error, already reported, to the nearest recovery point | 8 |
| `packages/typed_graphql/lib/src/language/parser/token_cursor.dart` | The parser's view of the token stream | 8 |
| `packages/typed_graphql/lib/src/language/parser/value_parser.dart` | Parses values, variables, type references, descriptions and operation types | 8 |
| `packages/typed_graphql/test/language/parser/parse_value_test.dart` | Tests | 8 |
| `packages/typed_graphql/lib/src/language/parser/definition_parser.dart` | Parses one definition of a document | 9 |
| `packages/typed_graphql/lib/src/language/parser/directive_parser.dart` | Parses directives and arguments (spec §2.6, §2.12) | 9 |
| `packages/typed_graphql/lib/src/language/parser/executable_parser.dart` | Parses operations and fragment definitions (spec §2.3, §2.8), with the descriptions September2025 allows on them | 9 |
| `packages/typed_graphql/lib/src/language/parser/graphql_syntax_exception.dart` | Thrown by `requireDocument` when a document has syntax errors | 9 |
| `packages/typed_graphql/lib/src/language/parser/parse_result.dart` | The result of parsing a document | 9 |
| `packages/typed_graphql/lib/src/language/parser/recovery.dart` | Where the parser resumes after a syntax error (R1.5) | 9 |
| `packages/typed_graphql/lib/src/language/parser/selection_parser.dart` | Parses selection sets, fields and fragment spreads (spec §2.4–§2.8) | 9 |
| `packages/typed_graphql/test/language/parser/parse_executable_test.dart` | Tests | 9 |
| `packages/typed_graphql/test/language/parser/parsed.dart` | The result of parsing one text, for tests | 9 |
| `packages/typed_graphql/test/language/parser/recovery_test.dart` | Tests | 9 |
| `packages/typed_graphql/test/language/parser/token_cursor_test.dart` | Tests | 9 |
| `packages/typed_graphql/lib/src/language/parser/type_member_parser.dart` | Parses what type-system definitions and extensions share | 10 |
| `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart` | Parses schema, type and directive definitions (spec §3) | 10 |
| `packages/typed_graphql/test/language/parser/parse_type_system_test.dart` | Tests | 10 |
| `packages/typed_graphql/lib/src/language/parser/definition_grammar.dart` | A definition production outside the September2025 grammar | 11 |
| `packages/typed_graphql/lib/src/language/parser/directive_extension_grammar.dart` | The working draft's `extend directive @name Directives[Const]` | 11 |
| `packages/typed_graphql/lib/src/language/parser/extension_parser.dart` | Parses `extend` definitions of the schema and of types (spec §3.3.2, §3.4.3) | 11 |
| `packages/typed_graphql/test/language/parser/parse_extension_test.dart` | Tests | 11 |
| `packages/typed_graphql/lib/src/language/printer/executable_printer.dart` | Prints operations, fragments and selections as graphql-js does | 12 |
| `packages/typed_graphql/lib/src/language/printer/extension_printer.dart` | Prints schema, type and directive extensions as graphql-js does | 12 |
| `packages/typed_graphql/lib/src/language/printer/print_layout.dart` | graphql-js's printer combinators, so printed text matches it to the character | 12 |
| `packages/typed_graphql/lib/src/language/printer/printer.dart` | Prints a syntax tree as GraphQL text (R1.10), character for character as graphql-js's `print` | 12 |
| `packages/typed_graphql/lib/src/language/printer/quoted_string.dart` | A string value as a quoted GraphQL string, escaped as graphql-js's `printString` does | 12 |
| `packages/typed_graphql/lib/src/language/printer/type_member_printer.dart` | Prints the members that type definitions and extensions share | 12 |
| `packages/typed_graphql/lib/src/language/printer/type_system_printer.dart` | Prints schema, type and directive definitions as graphql-js does | 12 |
| `packages/typed_graphql/lib/src/language/printer/value_printer.dart` | Prints values, type references, arguments and directives | 12 |
| `packages/typed_graphql/test/language/printer/print_executable_test.dart` | Tests | 12 |
| `packages/typed_graphql/test/language/printer/print_type_system_test.dart` | Tests | 12 |
| `packages/typed_graphql/lib/src/language/printer/minifier.dart` | Removes insignificant characters from GraphQL text as graphql-js's `stripIgnoredCharacters` does | 13 |
| `packages/typed_graphql/test/language/printer/print_minified_test.dart` | Tests | 13 |
| `packages/typed_graphql/test/language/parser/hostile_input_test.dart` | Tests | 14 |
| `.gitattributes` | LF line ends for every text file | 15 |
| `packages/typed_graphql_conformance/LICENSE-graphql-js` | graphql-js's MIT license, for the ported tests | 15 |
| `packages/typed_graphql_conformance/mapping/language.csv` | The mapping table (R0.7, R10.3) | 15 |
| `packages/typed_graphql_conformance/test/mapping_test.dart` | Tests | 15 |
| `packages/typed_graphql_conformance/test/support/csv_table.dart` | A CSV text with a header row, read as RFC 4180 | 15 |
| `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart` | The tests of one graphql-js test file in `reference/` (fetched by `tool/fetch_reference.sh`, absent in CI) | 15 |
| `packages/typed_graphql_conformance/test/support_test.dart` | Tests | 15 |
| `packages/typed_graphql_conformance/test/language/block_string_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/language/lexer_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/support/contain.dart` | chai's `.to.contain({...})` on an object | 16 |
| `packages/typed_graphql_conformance/test/support/error_json.dart` | A diagnostic as graphql-js's `GraphQLError` JSON for a syntax error, so a ported `expectSyntaxError(...)` expectation is copied unchanged | 16 |
| `packages/typed_graphql_conformance/test/support/lexer_port.dart` | graphql-js's lexer test helpers over [Lexer] | 16 |
| `packages/typed_graphql_conformance/test/language/parser/parser_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/language/parser/parser_values_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/language/parser/schema_parser_definitions_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/language/parser/schema_parser_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/support/ast_json.dart` | A node as graphql-js's `toJSONDeep` shows it, so a ported AST expectation is copied unchanged | 17 |
| `packages/typed_graphql_conformance/test/support/dedent.dart` | graphql-js's `dedent` test tag | 17 |
| `packages/typed_graphql_conformance/test/support/kitchen_sink.dart` | graphql-js's kitchen-sink documents (`src/__testUtils__/`), which use every part of the grammar | 17 |
| `packages/typed_graphql_conformance/test/support/parser_port.dart` | graphql-js's parser test helpers over [Parser] | 17 |
| `packages/typed_graphql_conformance/test/support/schema_nodes.dart` | graphql-js's node builders of `schema-parser-test.ts` (`nameNode`, `typeNode`, `fieldNode`, `fieldNodeWithArgs`, `enumValueNode`, `inputValueNode`) as `AstJson` maps, shared by the files the suite is split into | 17 |
| `packages/typed_graphql_conformance/test/language/printer/print_string_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/language/printer/printer_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/language/printer/schema_printer_test.dart` | Tests | 18 |
| `CLAUDE.md` | Repository guide: the language layer, the M2a lessons, the status | 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 19 |
| `analysis_options.yaml` | `strict-inference`, `strict-raw-types` | 1 |
| `packages/typed_graphql/CHANGELOG.md` | Core changelog | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic.dart` | `Diagnostic` value equality | 1 |
| `packages/typed_graphql/lib/typed_graphql.dart` | The barrel: the public language API | 2, 3, 4, 5, 6, 8, 9, 12, 19 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Codes `GQL001`–`GQL014` | 6, 7, 8, 9, 10, 11 |
| `packages/typed_graphql_conformance/CHANGELOG.md` | Conformance changelog | 15, 16, 17, 18 |
| `packages/typed_graphql_conformance/README.md` | "Ported suites" and the attribution | 15 |
| `packages/typed_graphql_conformance/pubspec.yaml` | Depends on `typed_graphql` only | 15 |
| `README.md` | Repository README: status and the package table | 19 |
| `docs/superpowers/HANDOFF.md` | Where the work stands | 19 |
| `packages/typed_graphql/README.md` | Core README: "Parsing and printing" | 19 |
| `packages/typed_graphql_conformance/test/language/lexer_strings_test.dart` | Tests, written while porting | 16 |
| `packages/typed_graphql_conformance/test/language/parser/parser_ast_test.dart` | Tests, written while porting | 17 |
| `packages/typed_graphql_conformance/test/language/parser/parser_descriptions_test.dart` | Tests, written while porting | 17 |
| `packages/typed_graphql_conformance/test/language/parser/schema_parser_types_test.dart` | Tests, written while porting | 17 |
| `packages/typed_graphql_conformance/test/language/parser/schema_parser_extensions_test.dart` | Tests, written while porting | 17 |

## The green check

Every task ends with this check. "Green" means each command exits 0.

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages test
dart analyze --fatal-infos
dart test
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
```

---

### Task 1: Diagnostic equality and the strict analyzer modes

The M1 carry-overs come first (spec §1): every later test compares lists of diagnostics, and every later file is written under `strict-inference` and `strict-raw-types`.

**Files:**
- Modify: `CLAUDE.md`, `analysis_options.yaml`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic.dart`
- Test: `packages/typed_graphql/test/diagnostics/diagnostic_test.dart`, `packages/typed_graphql/test/protocol/json_reader_test.dart`

**Interfaces:**
- Consumes: M1's `Diagnostic`, `SourceSpan` (equal for the same `Source` object and offsets) and `analysis_options.yaml`.
- Produces:
  - `Diagnostic` `==` and `hashCode` over `code`, `severity`, `message`, `span` and `related`, compared in order;
  - `analyzer: language: strict-inference: true, strict-raw-types: true` for the whole workspace.

- [ ] **Step 1: Write the failing test**

Replace `packages/typed_graphql/test/diagnostics/diagnostic_test.dart` whole with:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('DiagnosticCode', () {
    test('every id is GQL and three digits', () {
      for (final code in DiagnosticCode.values) {
        expect(code.id, matches(RegExp(r'^GQL[0-5]\d\d$')), reason: code.name);
      }
    });

    test('ids are unique and sorted', () {
      final ids = [for (final code in DiagnosticCode.values) code.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, [...ids]..sort());
    });

    test('keeps the ids already published', () {
      expect(DiagnosticCode.diagnosticLimitReached.id, 'GQL000');
    });
  });

  group('Diagnostic', () {
    final source = Source('{\n  a\n  b\n}', name: 'q.graphql');

    test('prints the place, the severity, the id and the message', () {
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'Too many errors.',
        span: SourceSpan(source, 4, 5),
      );
      expect(
        diagnostic.toString(),
        'q.graphql:2:3: error GQL000: Too many errors.',
      );
    });

    test('prints without a place when it has no span', () {
      final diagnostic = Diagnostic(.diagnosticLimitReached, .warning, 'Hm.');
      expect(diagnostic.toString(), 'warning GQL000: Hm.');
    });

    test('isError follows the severity', () {
      expect(Diagnostic(.diagnosticLimitReached, .error, 'x').isError, isTrue);
      expect(
        Diagnostic(.diagnosticLimitReached, .warning, 'x').isError,
        isFalse,
      );
    });

    test('lists the location of the span, then of the related spans', () {
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'Fields conflict.',
        span: SourceSpan(source, 4, 5),
        related: [SourceSpan(source, 8, 9)],
      );
      expect(diagnostic.locations, const [
        SourceLocation(2, 3),
        SourceLocation(3, 3),
      ]);
    });

    test('has no locations without spans', () {
      expect(
        Diagnostic(.diagnosticLimitReached, .error, 'x').locations,
        isEmpty,
      );
    });

    test('copies the related spans', () {
      final related = [SourceSpan(source, 8, 9)];
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'x',
        related: related,
      );
      related.clear();
      expect(diagnostic.related, hasLength(1));
      expect(
        () => diagnostic.related.add(SourceSpan(source, 0, 1)),
        throwsUnsupportedError,
      );
    });

    group('equality', () {
      Diagnostic make({
        String message = 'x',
        int end = 5,
        List<SourceSpan> related = const [],
      }) => Diagnostic(
        .diagnosticLimitReached,
        .error,
        message,
        span: SourceSpan(source, 4, end),
        related: related,
      );

      test('equal fields make equal diagnostics with equal hash codes', () {
        final related = [SourceSpan(source, 8, 9)];
        expect(make(related: related), make(related: [...related]));
        expect(
          make(related: related).hashCode,
          make(related: [...related]).hashCode,
        );
      });

      test('a different message, span or related list differs', () {
        expect(make(message: 'y'), isNot(make()));
        expect(make(end: 6), isNot(make()));
        expect(make(related: [SourceSpan(source, 8, 9)]), isNot(make()));
      });

      test('a different severity differs', () {
        expect(
          Diagnostic(.diagnosticLimitReached, .warning, 'x'),
          isNot(Diagnostic(.diagnosticLimitReached, .error, 'x')),
        );
      });
    });
  });
}
```

- [ ] **Step 2: Run the test and see it fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/diagnostics/diagnostic_test.dart)
```

Expected: FAIL. `compares by value, spans included` reports `Expected: Diagnostic:<q.graphql:2:3: error GQL000: x>`, because two equal diagnostics are not `==` yet.

- [ ] **Step 3: Write the implementation**

Replace `packages/typed_graphql/lib/src/diagnostics/diagnostic.dart` whole with:

```dart
import 'diagnostic_code.dart';
import 'diagnostic_severity.dart';
import 'source_location.dart';
import 'source_span.dart';

/// One problem found in a document, a schema or a payload; immutable.
///
/// Two diagnostics are equal when their code, severity, message, span and
/// related spans are, so tests compare lists of them directly.
final class Diagnostic(
  /// The stable code; its [DiagnosticCode.id] appears in messages.
  final DiagnosticCode code,

  /// Whether this is an error or a warning.
  final DiagnosticSeverity severity,

  /// A sentence for people: what is wrong, in the terms of the input.
  final String message, {

  /// Where the problem is; null when it has no place in a source, such as
  /// a problem of a schema built in code.
  final SourceSpan? span,
  List<SourceSpan> related = const [],
}) {
  /// Creates a diagnostic.
  this;

  /// Other places that explain the problem, such as the first definition
  /// of a duplicated name, in the order the GraphQL error's `locations`
  /// list them after [span].
  final List<SourceSpan> related = List.unmodifiable(related);

  /// Whether [severity] is [DiagnosticSeverity.error].
  bool get isError => severity == .error;

  /// The line and column of [span] and then of each [related] span: the
  /// `locations` of the GraphQL error this diagnostic becomes.
  List<SourceLocation> get locations => [
    ?span?.location,
    for (final place in related) place.location,
  ];

  @override
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.code == code &&
      other.severity == severity &&
      other.message == message &&
      other.span == span &&
      _sameSpans(other.related, related);

  @override
  int get hashCode =>
      Object.hash(code, severity, message, span, Object.hashAll(related));

  /// `name:line:column: severity GQLnnn: message`, without the place when
  /// there is no [span]: the form a terminal links to the source.
  @override
  String toString() {
    final place = span == null ? '' : '$span: ';
    return '$place${severity.name} ${code.id}: $message';
  }

  static bool _sameSpans(List<SourceSpan> left, List<SourceSpan> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}
```

- [ ] **Step 4: Run the test and see it pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/diagnostics/diagnostic_test.dart)
```

Expected: `+12: All tests passed!`

- [ ] **Step 5: Turn on the strict analyzer modes**

In `analysis_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,6 +7,12 @@
 # must print "No issues found!".
 include: package:lints/recommended.yaml
 
+analyzer:
+  language:
+    # Inference never falls back to dynamic silently (M2a).
+    strict-inference: true
+    strict-raw-types: true
+
 linter:
   rules:
     # Types and signatures (Effective Dart: Design, Usage)
@@ -112,7 +118,7 @@ linter:
     - sort_pub_dependencies
 
     # Staged, not enabled yet: enable one at a time and fix its findings.
-    #   strict-casts, strict-inference, strict-raw-types (analyzer: language:)
+    #   strict-casts (analyzer: language:)
     #   avoid_positional_boolean_parameters, avoid_redundant_argument_values,
     #   avoid_equals_and_hash_code_on_mutable_classes (add @immutable),
     #   cast_nullable_to_non_nullable, comment_references, discarded_futures,
```

Run: `dart analyze --fatal-infos`

Expected: one issue, `packages/typed_graphql/test/protocol/json_reader_test.dart:101:27 - The type argument(s) of 'List' can't be inferred. … - inference_failure_on_collection_literal`.

In `packages/typed_graphql/test/protocol/json_reader_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -98,7 +98,7 @@ void main() {
 
     test('read rejects nesting past maxDepth too', () {
       const reader = JsonReader(maxDepth: 2);
-      expect(reader.read([[]]), isA<DecodeSuccess<JsonValue>>());
+      expect(reader.read([<Object?>[]]), isA<DecodeSuccess<JsonValue>>());
       expect(
         reader.read([
           [<Object?>[]],
```

Run: `dart analyze --fatal-infos`

Expected: `No issues found!`

- [ ] **Step 6: Update the documents**

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -76,7 +76,8 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   renumber, reuse or remove one. Ranges: `GQL0xx` syntax, `GQL1xx` type
   system, `GQL2xx` operation validation, `GQL3xx` coercion and execution,
   `GQL4xx` transports, `GQL5xx` code generation; `GQL000` is the sink limit.
-- `Diagnostic(code, severity, message, span:, related:)`.
+- `Diagnostic(code, severity, message, span:, related:)`; equal when all
+  five are, so tests compare lists of diagnostics.
 - `DiagnosticSink` collects diagnostics in report order and stops after
   `maxErrors` errors (default 100) with one `GQL000`. Lexer, parser and rules
   take a sink through their constructor; the public API turns it into a
@@ -105,7 +106,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 
 The rules follow typed_openapi's (R10.1). `analysis_options.yaml` is adapted
 from typed_openapi's: its comments are this repo's own, and it additionally
-enables `simple_directive_paths`, `no_dynamic_casts` and `no_raw_types`.
+enables `simple_directive_paths`, `no_dynamic_casts` and `no_raw_types`, and
+the analyzer's `strict-inference` and `strict-raw-types` (write `<Object?>[]`
+where a literal has no context type).
 The workspace suite in `test/quality/` (run `dart test` at the root) enforces
 what a lint cannot (R10.2).
 
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md analysis_options.yaml packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic.dart packages/typed_graphql/test/diagnostics/diagnostic_test.dart packages/typed_graphql/test/protocol/json_reader_test.dart
git commit -q -m "feat(typed_graphql): compare diagnostics by value and enable strict inference"
```

### Task 2: Syntax tree core, values and type references

The base of every node, the values and the type references (R1.7, R1.8). `RebuildCheck` is a test helper that later tasks reuse for every node kind.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/ast/child_reader.dart`, `packages/typed_graphql/lib/src/language/ast/definition.dart`, `packages/typed_graphql/lib/src/language/ast/document.dart`, `packages/typed_graphql/lib/src/language/ast/name.dart`, `packages/typed_graphql/lib/src/language/ast/node.dart`, `packages/typed_graphql/lib/src/language/ast/object_field.dart`, `packages/typed_graphql/lib/src/language/ast/type_ref.dart`, `packages/typed_graphql/lib/src/language/ast/value.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/ast/node_test.dart`, `packages/typed_graphql/test/language/ast/rebuild_check.dart`, `packages/typed_graphql/test/language/ast/value_test.dart`

**Interfaces:**
- Consumes: `Source` offsets from M1 (nodes carry plain `int` offsets).
- Produces:
  - `abstract class const Node({final int start = 0, final int end = 0})`:
    - `List<Node> get children`, in graphql-js key order;
    - `List<Object?> get scalars` (default `const []`);
    - `Node withChildren(List<Node> children)`, which keeps the instance when nothing changed;
    - `Node rebuildFrom(ChildReader read)`, abstract;
    - `bool isEquivalentTo(Node other)`.
  - Internal `final class ChildReader(final List<Node> children)`:
    - `T rebuild<T extends Node>(T node, T Function(ChildReader read) build)`;
    - `T one<T extends Node>()`, `T? optional<T extends Node>()`, `List<T> all<T extends Node>()`;
    - each throws `StateError` on a missing, wrong or left-over child.
  - `abstract class const Definition({super.start, super.end}) extends Node`.
  - `final class Document(List<Definition> definitions, {start, end})` and `final class const Name(final String value, {start, end})`.
  - `sealed class Value`:
    - `Variable(Name name)`;
    - `IntValue(String value)` and `FloatValue(String value)`, which keep the raw lexeme;
    - `StringValue(String value, {bool isBlock = false})`;
    - `BooleanValue(bool value)`, `NullValue()`, `EnumValue(String value)`;
    - `ListValue(List<Value> values)`, `ObjectValue(List<ObjectField> fields)`.
  - `final class const ObjectField(Name name, Value value)`.
  - `sealed class TypeRef`: `NamedType(Name name)`, `ListType(TypeRef type)`, `NonNullType(TypeRef type)`.
  - Every constructor also takes `{start, end}`. List fields are copied with `List.unmodifiable`.
  - Test helper `RebuildCheck().expectRebuilds(Node)`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/ast/node_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/language/ast/child_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const a = Name('a');
  const b = Name('b');
  const one = IntValue('1');

  group('ChildReader', () {
    test('rebuild keeps the node when every child is identical', () {
      const field = ObjectField(a, one);
      final rebuilt = ChildReader(const [a, one]).rebuild(
        field,
        (read) => fail('nothing changed, so nothing is built'),
      );
      expect(identical(rebuilt, field), isTrue);
    });

    test('one throws a StateError when the child is missing', () {
      expect(() => ChildReader(const []).one<Name>(), throwsStateError);
    });

    test('one throws a StateError for a child of another kind', () {
      expect(() => ChildReader(const [one]).one<Name>(), throwsStateError);
    });

    test('optional consumes nothing when the next child is another kind', () {
      final read = ChildReader(const [one]);
      expect(read.optional<Name>(), isNull);
      expect(read.one<IntValue>(), same(one));
    });

    test('all reads the run of one kind and stops at another', () {
      final read = ChildReader(const [a, b, one]);
      expect(read.all<Name>(), [same(a), same(b)]);
      expect(read.all<Name>(), isEmpty);
      expect(read.one<Value>(), same(one));
    });

    test('rebuild throws a StateError for a child left over', () {
      expect(
        () => const ObjectField(a, one).withChildren(const [b, one, one]),
        throwsStateError,
      );
    });
  });

  group('isEquivalentTo', () {
    test('ignores positions', () {
      expect(
        const ObjectField(a, one).isEquivalentTo(
          const ObjectField(
            Name('a', start: 4, end: 5),
            IntValue('1', start: 7, end: 8),
            start: 4,
            end: 8,
          ),
        ),
        isTrue,
      );
    });

    test('compares raw lexemes, so 1.0 differs from 1.00', () {
      expect(
        const FloatValue('1.0').isEquivalentTo(const FloatValue('1.00')),
        isFalse,
      );
    });

    test('compares the kind of the node', () {
      expect(const IntValue('1').isEquivalentTo(const EnumValue('1')), isFalse);
    });

    test('compares the block-string flag', () {
      expect(
        const StringValue('s').isEquivalentTo(
          const StringValue('s', isBlock: true),
        ),
        isFalse,
      );
    });

    test('compares children in order and by count', () {
      final ab = ListValue(const [EnumValue('A'), EnumValue('B')]);
      expect(
        ab.isEquivalentTo(ListValue(const [EnumValue('A'), EnumValue('B')])),
        isTrue,
      );
      expect(
        ab.isEquivalentTo(ListValue(const [EnumValue('B'), EnumValue('A')])),
        isFalse,
      );
      expect(ab.isEquivalentTo(ListValue(const [EnumValue('A')])), isFalse);
    });
  });

  group('lists', () {
    test('a node copies its list into an unmodifiable one', () {
      final values = <Value>[one];
      final list = ListValue(values);
      values.clear();
      expect(list.values, [same(one)]);
      expect(() => list.values.add(one), throwsUnsupportedError);
    });

    test('a node built in code is at offset 0', () {
      expect((a.start, a.end), (0, 0));
    });
  });
}
```

Create `packages/typed_graphql/test/language/ast/rebuild_check.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Checks [Node.withChildren] on one node and everything under it.
final class RebuildCheck {
  /// Creates the check.
  const RebuildCheck();

  /// Expects that [node] keeps itself for its own children, and that fresh
  /// names under it rebuild every node above them into an equivalent node
  /// of the same kind at the same place.
  void expectRebuilds(Node node) {
    expect(identical(node.withChildren(node.children), node), isTrue);
    final copy = _copy(node);
    expect(copy.runtimeType, node.runtimeType);
    expect(copy.isEquivalentTo(node), isTrue);
    expect((copy.start, copy.end), (node.start, node.end));
    for (final child in node.children) {
      expectRebuilds(child);
    }
  }

  /// [node] with a new instance of every [Name] under it.
  Node _copy(Node node) => switch (node) {
    Name(:final value, :final start, :final end) => Name(
      value,
      start: start,
      end: end,
    ),
    _ => node.withChildren([for (final child in node.children) _copy(child)]),
  };
}
```

Create `packages/typed_graphql/test/language/ast/value_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const name = Name('v', start: 1, end: 2);

  group('Value', () {
    test('a variable has its name as its only child', () {
      expect(const Variable(name).children, [same(name)]);
    });

    test('scalar values have no children', () {
      const leaves = <Value>[
        IntValue('1'),
        FloatValue('1.5'),
        StringValue('s'),
        BooleanValue(true),
        NullValue(),
        EnumValue('RED'),
      ];
      for (final leaf in leaves) {
        expect(leaf.children, isEmpty, reason: '$leaf');
      }
    });

    test('a list has its items and an object its fields as children', () {
      const field = ObjectField(Name('a'), IntValue('1'));
      expect(ListValue(const [NullValue()]).children, [isA<NullValue>()]);
      expect(ObjectValue(const [field]).children, [same(field)]);
    });

    test('withChildren rebuilds every kind of value', () {
      final values = <Value>[
        const Variable(name, start: 0, end: 2),
        const IntValue('-12', start: 3, end: 6),
        const FloatValue('1.5e3'),
        const StringValue('s', isBlock: true),
        const BooleanValue(false),
        const NullValue(),
        const EnumValue('RED'),
        ListValue(const [Variable(name), IntValue('1')], start: 4, end: 9),
        ObjectValue([
          const ObjectField(Name('a'), Variable(name), start: 1, end: 5),
        ]),
      ];
      values.forEach(check.expectRebuilds);
    });

    test('a scalar value rejects children', () {
      expect(
        () => const IntValue('1').withChildren(const [name]),
        throwsStateError,
      );
    });
  });

  group('TypeRef', () {
    const named = NamedType(Name('Int'), start: 1, end: 4);

    test('wrappers have the wrapped type as their only child', () {
      expect(const ListType(named).children, [same(named)]);
      expect(const NonNullType(named).children, [same(named)]);
    });

    test('withChildren rebuilds every kind of type', () {
      const types = <TypeRef>[
        named,
        ListType(named, start: 0, end: 5),
        NonNullType(ListType(NonNullType(named)), start: 0, end: 7),
      ];
      types.forEach(check.expectRebuilds);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/node_test.dart test/language/ast/value_test.dart)
```

Expected: FAIL. The tests do not compile: `Error when reading 'lib/src/language/ast/child_reader.dart': No such file or directory`, and `Type 'Node' not found`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/language/ast/child_reader.dart`:

```dart
import 'node.dart';

/// Reads the list given to [Node.withChildren] back into a node's fields,
/// in grammar order, for [Node.rebuildFrom].
///
/// Each read consumes children from the front: [one] a required child,
/// [optional] a child that may be absent, [all] the run of children of one
/// kind. A child that does not fit is a [StateError]: [Node.withChildren]
/// is called by code, never with user input.
final class ChildReader(final List<Node> children) {
  /// Creates a reader positioned before the first of [children].
  this;

  int _next = 0;

  /// [node] when [children] are identical to its own; otherwise the node
  /// [build] makes from this reader, which must consume every child.
  T rebuild<T extends Node>(T node, T Function(ChildReader read) build) {
    if (_isUnchanged(node.children)) {
      return node;
    }
    final rebuilt = build(this);
    if (_next != children.length) {
      throw StateError(
        'Too many children for ${node.runtimeType}: '
        '${children.length - _next} left over.',
      );
    }
    return rebuilt;
  }

  /// The next child, which must be a [T].
  T one<T extends Node>() =>
      optional<T>() ??
      (throw StateError('Expected a $T child at position $_next.'));

  /// The next child when it is a [T]; null, consuming nothing, otherwise.
  T? optional<T extends Node>() {
    if (_next == children.length) {
      return null;
    }
    if (children[_next] case final T child) {
      _next++;
      return child;
    }
    return null;
  }

  /// The children from here on that are a [T], up to the first that is
  /// not; empty when the next child is not a [T].
  List<T> all<T extends Node>() => [
    for (var child = optional<T>(); child != null; child = optional<T>()) child,
  ];

  bool _isUnchanged(List<Node> original) {
    if (original.length != children.length) {
      return false;
    }
    for (var i = 0; i < original.length; i++) {
      if (!identical(original[i], children[i])) {
        return false;
      }
    }
    return true;
  }
}
```

Create `packages/typed_graphql/lib/src/language/ast/definition.dart`:

```dart
import 'node.dart';

/// A top-level definition of a [Document]: executable, type system or type
/// system extension (spec §2.2).
///
/// Not sealed: its families are, so a `switch` covers
/// `ExecutableDefinition`, `TypeSystemDefinition` and
/// `TypeSystemExtension`.
abstract class const Definition({super.start, super.end}) extends Node {
  /// Creates a definition spanning `start` to `end`.
  this;
}
```

Create `packages/typed_graphql/lib/src/language/ast/document.dart`:

```dart
import 'child_reader.dart';
import 'definition.dart';
import 'node.dart';

/// A GraphQL document: a list of definitions (spec §2.2).
final class Document(
  List<Definition> definitions, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a document.
  this;

  /// The definitions, in source order.
  final List<Definition> definitions = List.unmodifiable(definitions);

  @override
  List<Node> get children => definitions;

  @override
  Document rebuildFrom(ChildReader read) =>
      Document(read.all(), start: start, end: end);
}
```

Create `packages/typed_graphql/lib/src/language/ast/name.dart`:

```dart
import 'child_reader.dart';
import 'node.dart';

/// A name, such as a field, type or argument name (spec §2.1.9).
final class const Name(
  /// The name as written: `[_A-Za-z][_0-9A-Za-z]*`.
  final String value, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a name.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  Name rebuildFrom(ChildReader read) => this;
}
```

Create `packages/typed_graphql/lib/src/language/ast/node.dart`:

```dart
import 'package:meta/meta.dart';

import 'child_reader.dart';

/// A node of the syntax tree of a GraphQL document; immutable.
///
/// [start] and [end] are UTF-16 offsets into the source the node was parsed
/// from (R1.7); a node built in code has 0 for both. Nodes do not override
/// `==`: [isEquivalentTo] compares structure and ignores positions.
abstract class const Node({
  /// The offset of the first code unit of the node.
  final int start = 0,

  /// The offset after the last code unit of the node.
  final int end = 0,
}) {
  /// Creates a node spanning [start] to [end].
  this;

  /// The child nodes in grammar order, the order of graphql-js's
  /// `QueryDocumentKeys`; an absent optional child is left out. The list
  /// cannot be modified.
  List<Node> get children;

  /// The scalar fields [isEquivalentTo] compares, such as a name's value or
  /// an operation's type; empty for a node that has none.
  @protected
  List<Object?> get scalars => const [];

  /// A copy of this node with [children] in place of [Node.children], in
  /// the same order and shape, keeping [start] and [end]; this node itself
  /// when every child is identical.
  ///
  /// Throws a [StateError] when [children] does not fit the node: a missing
  /// required child, a child of the wrong kind or one too many.
  Node withChildren(List<Node> children) =>
      ChildReader(children).rebuild(this, rebuildFrom);

  /// A node of this kind with this node's scalar fields and positions and
  /// the children [read] returns, in the order of [children]; a leaf
  /// returns itself. Only [withChildren] calls it.
  @protected
  Node rebuildFrom(ChildReader read);

  /// Whether [other] has the same kind, the same scalar fields and
  /// equivalent children, in order; positions are ignored.
  bool isEquivalentTo(Node other) {
    if (other.runtimeType != runtimeType ||
        !_sameScalars(scalars, other.scalars)) {
      return false;
    }
    final mine = children;
    final theirs = other.children;
    if (mine.length != theirs.length) {
      return false;
    }
    for (var i = 0; i < mine.length; i++) {
      if (!mine[i].isEquivalentTo(theirs[i])) {
        return false;
      }
    }
    return true;
  }

  static bool _sameScalars(List<Object?> left, List<Object?> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}
```

Create `packages/typed_graphql/lib/src/language/ast/object_field.dart`:

```dart
import 'child_reader.dart';
import 'name.dart';
import 'node.dart';
import 'value.dart';

/// One field of an [ObjectValue], `name: value` (spec §2.9.8).
final class const ObjectField(
  /// The field name.
  final Name name,

  /// The field value.
  final Value value, {
  super.start,
  super.end,
}) extends Node {
  /// Creates an object field.
  this;

  @override
  List<Node> get children => [name, value];

  @override
  ObjectField rebuildFrom(ChildReader read) =>
      ObjectField(read.one(), read.one(), start: start, end: end);
}
```

Create `packages/typed_graphql/lib/src/language/ast/type_ref.dart`:

```dart
import 'child_reader.dart';
import 'name.dart';
import 'node.dart';

/// A reference to a type: named, list or non-null (spec §2.11).
sealed class const TypeRef({super.start, super.end}) extends Node {
  /// Creates a type reference spanning `start` to `end`.
  this;
}

/// A type by its name, `Name`.
final class const NamedType(
  /// The type's name.
  final Name name, {
  super.start,
  super.end,
}) extends TypeRef {
  /// Creates a named type.
  this;

  @override
  List<Node> get children => [name];

  @override
  NamedType rebuildFrom(ChildReader read) =>
      NamedType(read.one(), start: start, end: end);
}

/// A list type, `[Type]`.
final class const ListType(
  /// The type of the items.
  final TypeRef type, {
  super.start,
  super.end,
}) extends TypeRef {
  /// Creates a list type.
  this;

  @override
  List<Node> get children => [type];

  @override
  ListType rebuildFrom(ChildReader read) =>
      ListType(read.one(), start: start, end: end);
}

/// A non-null type, `Type!`; it wraps a named or list type, never another
/// non-null type.
final class const NonNullType(
  /// The wrapped type.
  final TypeRef type, {
  super.start,
  super.end,
}) extends TypeRef {
  /// Creates a non-null type; [type] must not be a [NonNullType].
  this : assert(type is! NonNullType, 'a non-null type is not wrapped twice');

  @override
  List<Node> get children => [type];

  @override
  NonNullType rebuildFrom(ChildReader read) =>
      NonNullType(read.one(), start: start, end: end);
}
```

Create `packages/typed_graphql/lib/src/language/ast/value.dart`:

```dart
import 'child_reader.dart';
import 'name.dart';
import 'node.dart';
import 'object_field.dart';

/// An input value as written in a document (spec §2.9).
sealed class const Value({super.start, super.end}) extends Node {
  /// Creates a value spanning `start` to `end`.
  this;
}

/// A variable, `$name` (spec §2.10).
final class const Variable(
  /// The name without the `$`.
  final Name name, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a variable.
  this;

  @override
  List<Node> get children => [name];

  @override
  Variable rebuildFrom(ChildReader read) =>
      Variable(read.one(), start: start, end: end);
}

/// An integer, kept as written so no precision is lost (spec §2.9.1).
final class const IntValue(
  /// The lexeme, such as `-12`.
  final String value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates an integer value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  IntValue rebuildFrom(ChildReader read) => this;
}

/// A float, kept as written so no precision is lost (spec §2.9.2).
final class const FloatValue(
  /// The lexeme, such as `1.5e-3`.
  final String value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a float value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  FloatValue rebuildFrom(ChildReader read) => this;
}

/// A string or block string; also a description (spec §2.9.4).
final class const StringValue(
  /// The decoded value: escapes resolved, block indentation removed.
  final String value, {

  /// Whether it was written as a block string, `"""..."""`.
  final bool isBlock = false,
  super.start,
  super.end,
}) extends Value {
  /// Creates a string value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value, isBlock];

  @override
  StringValue rebuildFrom(ChildReader read) => this;
}

/// `true` or `false` (spec §2.9.3).
final class const BooleanValue(
  /// The value.
  final bool value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a boolean value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  BooleanValue rebuildFrom(ChildReader read) => this;
}

/// `null` (spec §2.9.5).
final class const NullValue({super.start, super.end}) extends Value {
  /// Creates a null value.
  this;

  @override
  List<Node> get children => const [];

  @override
  NullValue rebuildFrom(ChildReader read) => this;
}

/// An enum value: a name other than `true`, `false` and `null` (spec
/// §2.9.6).
final class const EnumValue(
  /// The name as written.
  final String value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates an enum value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  EnumValue rebuildFrom(ChildReader read) => this;
}

/// A list, `[a, b]` (spec §2.9.7).
final class ListValue(
  List<Value> values, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a list value.
  this;

  /// The items, in order.
  final List<Value> values = List.unmodifiable(values);

  @override
  List<Node> get children => values;

  @override
  ListValue rebuildFrom(ChildReader read) =>
      ListValue(read.all(), start: start, end: end);
}

/// An input object, `{a: 1}` (spec §2.9.8).
final class ObjectValue(
  List<ObjectField> fields, {
  super.start,
  super.end,
}) extends Value {
  /// Creates an object value.
  this;

  /// The fields, in source order; a name may repeat (validation reports
  /// it).
  final List<ObjectField> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => fields;

  @override
  ObjectValue rebuildFrom(ChildReader read) =>
      ObjectValue(read.all(), start: start, end: end);
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/node_test.dart test/language/ast/value_test.dart)
```

Expected: `node_test.dart` `+13`, `value_test.dart` `+7`, each `All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -83,6 +83,13 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   take a sink through their constructor; the public API turns it into a
   sealed result.
 
+**Language** (`language/`; M2).
+- `ast/`: every node extends `Node` (`start`, `end`, `children` in
+  graphql-js key order, `withChildren`, `isEquivalentTo`). Leaves are
+  `const`; a node with a list copies it with `List.unmodifiable`. A node
+  overrides `rebuildFrom(ChildReader)` for `withChildren`. `scalars` lists
+  what `isEquivalentTo` compares besides children.
+
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
   `JsonString`, `JsonArray`, `JsonObject`): the type of arbitrary JSON in
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/value.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/ast/child_reader.dart packages/typed_graphql/lib/src/language/ast/definition.dart packages/typed_graphql/lib/src/language/ast/document.dart packages/typed_graphql/lib/src/language/ast/name.dart packages/typed_graphql/lib/src/language/ast/node.dart packages/typed_graphql/lib/src/language/ast/object_field.dart packages/typed_graphql/lib/src/language/ast/type_ref.dart packages/typed_graphql/lib/src/language/ast/value.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/ast/node_test.dart packages/typed_graphql/test/language/ast/rebuild_check.dart packages/typed_graphql/test/language/ast/value_test.dart
git commit -q -m "feat(typed_graphql): add the syntax tree core, values and type references"
```

### Task 3: Executable syntax nodes

**Files:**
- Create: `packages/typed_graphql/lib/src/language/ast/argument.dart`, `packages/typed_graphql/lib/src/language/ast/directive.dart`, `packages/typed_graphql/lib/src/language/ast/executable_definition.dart`, `packages/typed_graphql/lib/src/language/ast/operation_type.dart`, `packages/typed_graphql/lib/src/language/ast/selection.dart`, `packages/typed_graphql/lib/src/language/ast/selection_set.dart`, `packages/typed_graphql/lib/src/language/ast/variable_definition.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/ast/executable_test.dart`

**Interfaces:**
- Consumes: Task 2: `Node`, `Definition`, `Name`, `Value`, `TypeRef`, `ChildReader`, `RebuildCheck`.
- Produces:
  - `final class const Argument(Name name, Value value)` and `final class Directive(Name name, {List<Argument> arguments})`;
  - `enum OperationType { query, mutation, subscription }`;
  - `sealed class ExecutableDefinition extends Definition`:
    - `OperationDefinition(OperationType operation, SelectionSet selectionSet, {StringValue? description, Name? name, List<VariableDefinition> variableDefinitions, List<Directive> directives})`;
    - `FragmentDefinition(Name name, NamedType typeCondition, SelectionSet selectionSet, {StringValue? description, List<Directive> directives})`.
  - `sealed class Selection`:
    - `Field(Name? alias, Name name, {List<Argument> arguments, List<Directive> directives, SelectionSet? selectionSet})`;
    - `FragmentSpread(Name name, {List<Directive> directives})`;
    - `InlineFragment(NamedType? typeCondition, SelectionSet selectionSet, {List<Directive> directives})`.
  - `final class SelectionSet(List<Selection> selections)`.
  - `final class VariableDefinition(Variable variable, TypeRef type, {StringValue? description, Value? defaultValue, List<Directive> directives})`.
  - Every constructor also takes `{start, end}`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/ast/executable_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const id = Name('id');
  const alias = Name('key');
  final skip = Directive(
    const Name('skip'),
    arguments: const [Argument(Name('if'), Variable(Name('no')))],
  );

  OperationDefinition operation({OperationType type = .query}) =>
      OperationDefinition(
        type,
        SelectionSet([Field(null, id)]),
        description: const StringValue('Reads.'),
        name: const Name('Q'),
        variableDefinitions: [
          VariableDefinition(
            const Variable(Name('no')),
            const NonNullType(NamedType(Name('Boolean'))),
            description: const StringValue('Skip?'),
            defaultValue: const BooleanValue(false),
            directives: [skip],
          ),
        ],
        directives: [skip],
        start: 2,
        end: 40,
      );

  group('Field', () {
    test('lists alias, name, arguments, directives, selections', () {
      final selections = SelectionSet([Field(null, id)]);
      final field = Field(
        alias,
        const Name('node'),
        arguments: const [Argument(Name('id'), IntValue('4'))],
        directives: [skip],
        selectionSet: selections,
      );
      expect(field.children, [
        same(alias),
        isA<Name>(),
        isA<Argument>(),
        same(skip),
        same(selections),
      ]);
    });

    test('withChildren reads one leading name as the name alone', () {
      final field = Field(alias, id).withChildren(const [Name('other')]);
      expect(field, isA<Field>().having((f) => f.alias, 'alias', isNull));
    });

    test('withChildren reads two leading names as alias and name', () {
      final field = Field(null, id).withChildren(const [alias, id]);
      expect(field, isA<Field>().having((f) => f.alias, 'alias', same(alias)));
    });

    test('withChildren rejects a field without a name', () {
      expect(() => Field(null, id).withChildren(const []), throwsStateError);
    });

    test('withChildren rejects three leading names', () {
      expect(
        () => Field(null, id).withChildren(const [alias, id, id]),
        throwsStateError,
      );
    });
  });

  group('executable nodes', () {
    test('withChildren rebuilds every kind of executable node', () {
      final selections = SelectionSet([
        Field(alias, id, directives: [skip], start: 1, end: 9),
        FragmentSpread(const Name('F'), directives: [skip]),
        InlineFragment(
          const NamedType(Name('User')),
          SelectionSet([Field(null, id)]),
          directives: [skip],
        ),
        InlineFragment(null, SelectionSet([Field(null, id)])),
      ]);
      final nodes = <Node>[
        selections,
        operation(),
        OperationDefinition(.mutation, selections),
        FragmentDefinition(
          const Name('F'),
          const NamedType(Name('User')),
          selections,
          description: const StringValue('Fields.'),
          directives: [skip],
        ),
        Document([operation()], start: 0, end: 41),
      ];
      nodes.forEach(check.expectRebuilds);
    });

    test('an operation lists description, name, variables, directives', () {
      final children = operation().children;
      expect(children, [
        isA<StringValue>(),
        isA<Name>(),
        isA<VariableDefinition>(),
        isA<Directive>(),
        isA<SelectionSet>(),
      ]);
    });

    test('a variable definition lists description first', () {
      final variable = operation().variableDefinitions.single;
      expect(variable.children, [
        isA<StringValue>(),
        isA<Variable>(),
        isA<NonNullType>(),
        isA<BooleanValue>(),
        isA<Directive>(),
      ]);
    });

    test('isEquivalentTo compares the operation type', () {
      expect(operation().isEquivalentTo(operation()), isTrue);
      expect(
        operation().isEquivalentTo(operation(type: .subscription)),
        isFalse,
      );
    });

    test('a document copies its definitions into an unmodifiable list', () {
      final definitions = <Definition>[operation()];
      final document = Document(definitions);
      definitions.clear();
      expect(document.definitions, hasLength(1));
      expect(document.definitions.clear, throwsUnsupportedError);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/executable_test.dart)
```

Expected: FAIL to compile: `Method not found: 'Argument'`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/language/ast/argument.dart`:

```dart
import 'child_reader.dart';
import 'name.dart';
import 'node.dart';
import 'value.dart';

/// An argument of a field or directive, `name: value` (spec §2.6).
final class const Argument(
  /// The argument name.
  final Name name,

  /// The argument value.
  final Value value, {
  super.start,
  super.end,
}) extends Node {
  /// Creates an argument.
  this;

  @override
  List<Node> get children => [name, value];

  @override
  Argument rebuildFrom(ChildReader read) =>
      Argument(read.one(), read.one(), start: start, end: end);
}
```

Create `packages/typed_graphql/lib/src/language/ast/directive.dart`:

```dart
import 'argument.dart';
import 'child_reader.dart';
import 'name.dart';
import 'node.dart';

/// A directive applied to a node, `@name(arguments)` (spec §2.12).
final class Directive(
  /// The directive name, without the `@`.
  final Name name, {
  List<Argument> arguments = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates a directive.
  this;

  /// The arguments, in source order.
  final List<Argument> arguments = List.unmodifiable(arguments);

  @override
  List<Node> get children => [name, ...arguments];

  @override
  Directive rebuildFrom(ChildReader read) =>
      Directive(read.one(), arguments: read.all(), start: start, end: end);
}
```

Create `packages/typed_graphql/lib/src/language/ast/executable_definition.dart`:

```dart
import 'child_reader.dart';
import 'definition.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'operation_type.dart';
import 'selection_set.dart';
import 'type_ref.dart';
import 'value.dart';
import 'variable_definition.dart';

/// A definition a server executes: an operation or a fragment (spec §2.2).
sealed class const ExecutableDefinition({super.start, super.end})
    extends Definition {
  /// Creates an executable definition spanning `start` to `end`.
  this;
}

/// An operation, `query Name($v: T) @d { ... }`, or the shorthand
/// `{ ... }` (spec §2.3).
final class OperationDefinition(
  /// Whether it is a query, a mutation or a subscription.
  final OperationType operation,

  /// The selections.
  final SelectionSet selectionSet, {

  /// The description, if any (September2025).
  final StringValue? description,

  /// The name; null for an anonymous operation.
  final Name? name,
  List<VariableDefinition> variableDefinitions = const [],
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends ExecutableDefinition {
  /// Creates an operation.
  this;

  /// The variable definitions, in source order.
  final List<VariableDefinition> variableDefinitions = List.unmodifiable(
    variableDefinitions,
  );

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    ?name,
    ...variableDefinitions,
    ...directives,
    selectionSet,
  ];

  @override
  List<Object?> get scalars => [operation];

  @override
  OperationDefinition rebuildFrom(ChildReader read) => OperationDefinition(
    operation,
    description: read.optional(),
    name: read.optional(),
    variableDefinitions: read.all(),
    directives: read.all(),
    read.one(),
    start: start,
    end: end,
  );
}

/// A fragment, `fragment Name on Type @d { ... }` (spec §2.8).
final class FragmentDefinition(
  /// The fragment name; never `on`.
  final Name name,

  /// The type the fragment applies to.
  final NamedType typeCondition,

  /// The selections.
  final SelectionSet selectionSet, {

  /// The description, if any (September2025).
  final StringValue? description,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends ExecutableDefinition {
  /// Creates a fragment.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    name,
    typeCondition,
    ...directives,
    selectionSet,
  ];

  @override
  FragmentDefinition rebuildFrom(ChildReader read) => FragmentDefinition(
    description: read.optional(),
    read.one(),
    read.one(),
    directives: read.all(),
    read.one(),
    start: start,
    end: end,
  );
}
```

Create `packages/typed_graphql/lib/src/language/ast/operation_type.dart`:

```dart
/// The type of an operation (spec §2.3): its keyword is its [name].
enum OperationType {
  /// `query`: a read-only fetch.
  query,

  /// `mutation`: a write followed by a fetch.
  mutation,

  /// `subscription`: a long-lived request that fetches on events.
  subscription,
}
```

Create `packages/typed_graphql/lib/src/language/ast/selection.dart`:

```dart
import 'argument.dart';
import 'child_reader.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'selection_set.dart';
import 'type_ref.dart';

/// One selection of a [SelectionSet] (spec §2.4).
sealed class const Selection({super.start, super.end}) extends Node {
  /// Creates a selection spanning `start` to `end`.
  this;
}

/// A field, `alias: name(arguments) @directives { selections }` (spec
/// §2.5).
final class Field(
  /// The alias, if any.
  final Name? alias,

  /// The field name.
  final Name name, {
  List<Argument> arguments = const [],
  List<Directive> directives = const [],

  /// The sub-selections; null for a leaf field.
  final SelectionSet? selectionSet,
  super.start,
  super.end,
}) extends Selection {
  /// Creates a field.
  this;

  /// The arguments, in source order.
  final List<Argument> arguments = List.unmodifiable(arguments);

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?alias,
    name,
    ...arguments,
    ...directives,
    ?selectionSet,
  ];

  /// The alias and the name are both [Name]s: two leading names are both,
  /// one is the name alone.
  @override
  Field rebuildFrom(ChildReader read) {
    final names = read.all<Name>();
    if (names.isEmpty || names.length > 2) {
      throw StateError('A field has one or two names, not ${names.length}.');
    }
    return Field(
      names.length == 2 ? names.first : null,
      names.last,
      arguments: read.all(),
      directives: read.all(),
      selectionSet: read.optional(),
      start: start,
      end: end,
    );
  }
}

/// A fragment spread, `...Name @directives` (spec §2.8).
final class FragmentSpread(
  /// The fragment name.
  final Name name, {
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Selection {
  /// Creates a fragment spread.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [name, ...directives];

  @override
  FragmentSpread rebuildFrom(ChildReader read) => FragmentSpread(
    read.one(),
    directives: read.all(),
    start: start,
    end: end,
  );
}

/// An inline fragment, `... on Type @directives { selections }` (spec
/// §2.8.2).
final class InlineFragment(
  /// The type condition, if any.
  final NamedType? typeCondition,

  /// The selections.
  final SelectionSet selectionSet, {
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Selection {
  /// Creates an inline fragment.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [?typeCondition, ...directives, selectionSet];

  @override
  InlineFragment rebuildFrom(ChildReader read) => InlineFragment(
    read.optional(),
    directives: read.all(),
    read.one(),
    start: start,
    end: end,
  );
}
```

Create `packages/typed_graphql/lib/src/language/ast/selection_set.dart`:

```dart
import 'child_reader.dart';
import 'node.dart';
import 'selection.dart';

/// A selection set, `{ selections }` (spec §2.4).
///
/// It is empty only when the parser allows empty selection sets (a
/// working-draft option).
final class SelectionSet(
  List<Selection> selections, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a selection set.
  this;

  /// The selections, in source order.
  final List<Selection> selections = List.unmodifiable(selections);

  @override
  List<Node> get children => selections;

  @override
  SelectionSet rebuildFrom(ChildReader read) =>
      SelectionSet(read.all(), start: start, end: end);
}
```

Create `packages/typed_graphql/lib/src/language/ast/variable_definition.dart`:

```dart
import 'child_reader.dart';
import 'directive.dart';
import 'node.dart';
import 'type_ref.dart';
import 'value.dart';

/// A variable definition of an operation, `$name: Type = default
/// @directives` (spec §2.10).
final class VariableDefinition(
  /// The variable.
  final Variable variable,

  /// The variable's type.
  final TypeRef type, {

  /// The description, if any (September2025).
  final StringValue? description,

  /// The default value, if any; a constant.
  final Value? defaultValue,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates a variable definition.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    variable,
    type,
    ?defaultValue,
    ...directives,
  ];

  @override
  VariableDefinition rebuildFrom(ChildReader read) => VariableDefinition(
    description: read.optional(),
    read.one(),
    read.one(),
    defaultValue: read.optional(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/executable_test.dart)
```

Expected: `+10: All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/ast/argument.dart packages/typed_graphql/lib/src/language/ast/directive.dart packages/typed_graphql/lib/src/language/ast/executable_definition.dart packages/typed_graphql/lib/src/language/ast/operation_type.dart packages/typed_graphql/lib/src/language/ast/selection.dart packages/typed_graphql/lib/src/language/ast/selection_set.dart packages/typed_graphql/lib/src/language/ast/variable_definition.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/ast/executable_test.dart
git commit -q -m "feat(typed_graphql): add the executable syntax nodes"
```

### Task 4: Type-system syntax nodes

The type-system families are too large for one 300-line file each with their `rebuildFrom` bodies, so each delegates to a rebuilder in its own file.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/ast/enum_value_definition.dart`, `packages/typed_graphql/lib/src/language/ast/field_definition.dart`, `packages/typed_graphql/lib/src/language/ast/input_value_definition.dart`, `packages/typed_graphql/lib/src/language/ast/operation_type_definition.dart`, `packages/typed_graphql/lib/src/language/ast/type_system_definition.dart`, `packages/typed_graphql/lib/src/language/ast/type_system_definition_rebuilder.dart`, `packages/typed_graphql/lib/src/language/ast/type_system_extension.dart`, `packages/typed_graphql/lib/src/language/ast/type_system_extension_rebuilder.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/ast/type_system_test.dart`

**Interfaces:**
- Consumes: Tasks 2–3: `Node`, `Definition`, `Name`, `Value`, `TypeRef`, `Directive`, `OperationType`, `ChildReader`.
- Produces:
  - `final class FieldDefinition(Name name, TypeRef type, {StringValue? description, List<InputValueDefinition> arguments, List<Directive> directives})`;
  - `final class InputValueDefinition(Name name, TypeRef type, {StringValue? description, Value? defaultValue, List<Directive> directives})`;
  - `final class EnumValueDefinition(Name name, {StringValue? description, List<Directive> directives})`;
  - `final class const OperationTypeDefinition(OperationType operation, NamedType type)`;
  - `sealed class TypeSystemDefinition({StringValue? description, List<Directive> directives}) extends Definition`:
    - `SchemaDefinition({List<OperationTypeDefinition> operationTypes})`;
    - `DirectiveDefinition(Name name, {List<InputValueDefinition> arguments, bool isRepeatable = false, List<Name> locations})`;
    - the sealed `TypeDefinition(Name name)`: `ScalarTypeDefinition`, `ObjectTypeDefinition` and `InterfaceTypeDefinition` (`interfaces`, `fields`), `UnionTypeDefinition` (`types`), `EnumTypeDefinition` (`values`), `InputObjectTypeDefinition` (`fields`).
  - `sealed class TypeSystemExtension({List<Directive> directives}) extends Definition`:
    - `SchemaExtension({List<OperationTypeDefinition> operationTypes})`;
    - `DirectiveExtension(Name name)`;
    - the sealed `TypeExtension(Name name)`, with the six `*TypeExtension` classes and the same lists as their definitions.
  - Internal `TypeSystemDefinitionRebuilder` and `TypeSystemExtensionRebuilder`.
  - Every constructor also takes `{start, end}`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/ast/type_system_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const description = StringValue('Docs.', isBlock: true);
  const node = NamedType(Name('Node'));
  final key = Directive(const Name('key'));
  final field = FieldDefinition(
    const Name('id'),
    const NonNullType(NamedType(Name('ID'))),
    description: description,
    arguments: [
      InputValueDefinition(
        const Name('first'),
        const NamedType(Name('Int')),
        defaultValue: const IntValue('10'),
        directives: [key],
      ),
    ],
    directives: [key],
  );
  final input = InputValueDefinition(
    const Name('limit'),
    const NamedType(Name('Int')),
    description: description,
  );
  final value = EnumValueDefinition(
    const Name('RED'),
    description: description,
    directives: [key],
  );
  const root = OperationTypeDefinition(.query, NamedType(Name('Query')));

  DirectiveDefinition directive({bool isRepeatable = false}) =>
      DirectiveDefinition(
        const Name('key'),
        description: description,
        arguments: [input],
        directives: [key],
        isRepeatable: isRepeatable,
        locations: const [Name('FIELD'), Name('OBJECT')],
        start: 3,
        end: 50,
      );

  final definitions = <TypeSystemDefinition>[
    SchemaDefinition(
      description: description,
      directives: [key],
      operationTypes: const [root],
    ),
    directive(),
    ScalarTypeDefinition(const Name('Date'), description: description),
    ObjectTypeDefinition(
      const Name('User'),
      description: description,
      interfaces: const [node],
      directives: [key],
      fields: [field],
    ),
    InterfaceTypeDefinition(
      const Name('Node'),
      interfaces: const [node],
      fields: [field],
    ),
    UnionTypeDefinition(const Name('U'), types: const [node, node]),
    EnumTypeDefinition(const Name('Color'), values: [value]),
    InputObjectTypeDefinition(const Name('Page'), fields: [input]),
  ];

  final extensions = <TypeSystemExtension>[
    SchemaExtension(directives: [key], operationTypes: const [root]),
    DirectiveExtension(const Name('key'), directives: [key]),
    ScalarTypeExtension(const Name('Date'), directives: [key]),
    ObjectTypeExtension(
      const Name('User'),
      interfaces: const [node],
      directives: [key],
      fields: [field],
    ),
    InterfaceTypeExtension(const Name('Node'), fields: [field]),
    UnionTypeExtension(const Name('U'), types: const [node]),
    EnumTypeExtension(const Name('Color'), values: [value]),
    InputObjectTypeExtension(const Name('Page'), fields: [input]),
  ];

  test('withChildren rebuilds every type system definition', () {
    definitions.forEach(check.expectRebuilds);
  });

  test('withChildren rebuilds every type system extension', () {
    extensions.forEach(check.expectRebuilds);
  });

  test('withChildren rebuilds field, argument and enum value definitions', () {
    <Node>[field, input, value, root].forEach(check.expectRebuilds);
  });

  test('an object type lists interfaces before directives and fields', () {
    expect(definitions[3].children, [
      same(description),
      isA<Name>(),
      same(node),
      same(key),
      same(field),
    ]);
  });

  test('a directive definition lists its locations last', () {
    expect(directive().children, [
      same(description),
      isA<Name>(),
      same(input),
      same(key),
      isA<Name>().having((name) => name.value, 'value', 'FIELD'),
      isA<Name>().having((name) => name.value, 'value', 'OBJECT'),
    ]);
  });

  test('isEquivalentTo compares whether a directive is repeatable', () {
    expect(directive().isEquivalentTo(directive()), isTrue);
    expect(directive().isEquivalentTo(directive(isRepeatable: true)), isFalse);
  });

  test('isEquivalentTo compares the operation of a root type', () {
    expect(
      root.isEquivalentTo(
        const OperationTypeDefinition(.mutation, NamedType(Name('Query'))),
      ),
      isFalse,
    );
  });

  test('a switch over a type definition needs no wildcard', () {
    String keyword(TypeDefinition type) => switch (type) {
      ScalarTypeDefinition() => 'scalar',
      ObjectTypeDefinition() => 'type',
      InterfaceTypeDefinition() => 'interface',
      UnionTypeDefinition() => 'union',
      EnumTypeDefinition() => 'enum',
      InputObjectTypeDefinition() => 'input',
    };
    expect(
      [
        for (final type in definitions.whereType<TypeDefinition>())
          keyword(type),
      ],
      ['scalar', 'type', 'interface', 'union', 'enum', 'input'],
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/type_system_test.dart)
```

Expected: FAIL to compile: `Method not found: 'InputValueDefinition'`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/language/ast/enum_value_definition.dart`:

```dart
import 'child_reader.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'value.dart';

/// A value of an enum type, `"desc" NAME @d` (spec §3.9).
final class EnumValueDefinition(
  /// The value's name; never `true`, `false` or `null`.
  final Name name, {

  /// The description, if any.
  final StringValue? description,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates an enum value definition.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [?description, name, ...directives];

  @override
  EnumValueDefinition rebuildFrom(ChildReader read) => EnumValueDefinition(
    description: read.optional(),
    read.one(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
```

Create `packages/typed_graphql/lib/src/language/ast/field_definition.dart`:

```dart
import 'child_reader.dart';
import 'directive.dart';
import 'input_value_definition.dart';
import 'name.dart';
import 'node.dart';
import 'type_ref.dart';
import 'value.dart';

/// A field of an object or interface type, `"desc" name(args): Type @d`
/// (spec §3.6).
final class FieldDefinition(
  /// The field name.
  final Name name,

  /// The output type.
  final TypeRef type, {

  /// The description, if any.
  final StringValue? description,
  List<InputValueDefinition> arguments = const [],
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates a field definition.
  this;

  /// The argument definitions, in source order.
  final List<InputValueDefinition> arguments = List.unmodifiable(arguments);

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...arguments,
    type,
    ...directives,
  ];

  @override
  FieldDefinition rebuildFrom(ChildReader read) => FieldDefinition(
    description: read.optional(),
    read.one(),
    arguments: read.all(),
    read.one(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
```

Create `packages/typed_graphql/lib/src/language/ast/input_value_definition.dart`:

```dart
import 'child_reader.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'type_ref.dart';
import 'value.dart';

/// An argument or input field definition, `"desc" name: Type = default
/// @d` (spec §3.6.1, §3.10).
final class InputValueDefinition(
  /// The name.
  final Name name,

  /// The input type.
  final TypeRef type, {

  /// The description, if any.
  final StringValue? description,

  /// The default value, if any; a constant.
  final Value? defaultValue,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates an input value definition.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?description,
    name,
    type,
    ?defaultValue,
    ...directives,
  ];

  @override
  InputValueDefinition rebuildFrom(ChildReader read) => InputValueDefinition(
    description: read.optional(),
    read.one(),
    read.one(),
    defaultValue: read.optional(),
    directives: read.all(),
    start: start,
    end: end,
  );
}
```

Create `packages/typed_graphql/lib/src/language/ast/operation_type_definition.dart`:

```dart
import 'child_reader.dart';
import 'node.dart';
import 'operation_type.dart';
import 'type_ref.dart';

/// A root operation type of a schema, `query: Query` (spec §3.3.1).
final class const OperationTypeDefinition(
  /// The operation the type serves.
  final OperationType operation,

  /// The root type.
  final NamedType type, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a root operation type definition.
  this;

  @override
  List<Node> get children => [type];

  @override
  List<Object?> get scalars => [operation];

  @override
  OperationTypeDefinition rebuildFrom(ChildReader read) =>
      OperationTypeDefinition(
        operation,
        read.one(),
        start: start,
        end: end,
      );
}
```

Create `packages/typed_graphql/lib/src/language/ast/type_system_definition.dart`:

```dart
import 'child_reader.dart';
import 'definition.dart';
import 'directive.dart';
import 'enum_value_definition.dart';
import 'field_definition.dart';
import 'input_value_definition.dart';
import 'name.dart';
import 'node.dart';
import 'operation_type_definition.dart';
import 'type_ref.dart';
import 'type_system_definition_rebuilder.dart';
import 'value.dart';

/// A definition of a schema, a type or a directive (spec §3).
sealed class TypeSystemDefinition({
  /// The description, if any.
  final StringValue? description,
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Definition {
  /// Creates a type system definition.
  this;

  /// The directives, in source order (working draft on a directive).
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  TypeSystemDefinition rebuildFrom(ChildReader read) =>
      const TypeSystemDefinitionRebuilder().rebuild(this, read);
}

/// `"desc" schema @d { query: Query }` (spec §3.3).
final class SchemaDefinition({
  super.description,
  super.directives,
  List<OperationTypeDefinition> operationTypes = const [],
  super.start,
  super.end,
}) extends TypeSystemDefinition {
  /// Creates a schema definition.
  this;

  /// The root operation types, in source order.
  final List<OperationTypeDefinition> operationTypes = List.unmodifiable(
    operationTypes,
  );

  @override
  List<Node> get children => [?description, ...directives, ...operationTypes];
}

/// `"desc" directive @name(args) @d repeatable on LOCATIONS` (spec §3.13).
final class DirectiveDefinition(
  /// The directive name, without the `@`.
  final Name name, {
  super.description,
  List<InputValueDefinition> arguments = const [],
  super.directives,

  /// Whether the directive may be applied more than once to one place.
  final bool isRepeatable = false,
  List<Name> locations = const [],
  super.start,
  super.end,
}) extends TypeSystemDefinition {
  /// Creates a directive definition.
  this;

  /// The argument definitions, in source order.
  final List<InputValueDefinition> arguments = List.unmodifiable(arguments);

  /// The locations, such as `FIELD`, in source order.
  final List<Name> locations = List.unmodifiable(locations);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...arguments,
    ...directives,
    ...locations,
  ];

  @override
  List<Object?> get scalars => [isRepeatable];
}

/// A named type definition (spec §3.4).
sealed class TypeDefinition(
  /// The type name.
  final Name name, {
  super.description,
  super.directives,
  super.start,
  super.end,
}) extends TypeSystemDefinition {
  /// Creates a type definition.
  this;
}

/// `"desc" scalar Name @d` (spec §3.5).
final class ScalarTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates a scalar type definition.
  this;

  @override
  List<Node> get children => [?description, name, ...directives];
}

/// `"desc" type Name implements I @d { fields }` (spec §3.6).
final class ObjectTypeDefinition(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an object type definition.
  this;

  /// The interfaces it implements, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...interfaces,
    ...directives,
    ...fields,
  ];
}

/// `"desc" interface Name implements I @d { fields }` (spec §3.7).
final class InterfaceTypeDefinition(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an interface type definition.
  this;

  /// The interfaces it implements, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [
    ?description,
    name,
    ...interfaces,
    ...directives,
    ...fields,
  ];
}

/// `"desc" union Name @d = A | B` (spec §3.8).
final class UnionTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  List<NamedType> types = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates a union type definition.
  this;

  /// The member types, in source order.
  final List<NamedType> types = List.unmodifiable(types);

  @override
  List<Node> get children => [?description, name, ...directives, ...types];
}

/// `"desc" enum Name @d { VALUES }` (spec §3.9).
final class EnumTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  List<EnumValueDefinition> values = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an enum type definition.
  this;

  /// The values, in source order.
  final List<EnumValueDefinition> values = List.unmodifiable(values);

  @override
  List<Node> get children => [?description, name, ...directives, ...values];
}

/// `"desc" input Name @d { fields }` (spec §3.10).
final class InputObjectTypeDefinition(
  super.name, {
  super.description,
  super.directives,
  List<InputValueDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeDefinition {
  /// Creates an input object type definition.
  this;

  /// The input fields, in source order.
  final List<InputValueDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [?description, name, ...directives, ...fields];
}
```

Create `packages/typed_graphql/lib/src/language/ast/type_system_definition_rebuilder.dart`:

```dart
import 'child_reader.dart';
import 'node.dart';
import 'type_system_definition.dart';

/// Rebuilds a [TypeSystemDefinition] for [Node.withChildren]; apart from
/// the node classes so their library stays within the size limit.
final class const TypeSystemDefinitionRebuilder() {
  /// Creates the rebuilder.
  this;

  /// A definition of [node]'s kind, with its scalar fields and positions
  /// and the children [read] returns.
  TypeSystemDefinition rebuild(TypeSystemDefinition node, ChildReader read) =>
      switch (node) {
        SchemaDefinition() => SchemaDefinition(
          description: read.optional(),
          directives: read.all(),
          operationTypes: read.all(),
          start: node.start,
          end: node.end,
        ),
        DirectiveDefinition() => DirectiveDefinition(
          description: read.optional(),
          read.one(),
          arguments: read.all(),
          directives: read.all(),
          isRepeatable: node.isRepeatable,
          locations: read.all(),
          start: node.start,
          end: node.end,
        ),
        ScalarTypeDefinition() => ScalarTypeDefinition(
          description: read.optional(),
          read.one(),
          directives: read.all(),
          start: node.start,
          end: node.end,
        ),
        ObjectTypeDefinition() => _object(node, read),
        InterfaceTypeDefinition() => _interface(node, read),
        UnionTypeDefinition() => _union(node, read),
        EnumTypeDefinition() => _enum(node, read),
        InputObjectTypeDefinition() => _inputObject(node, read),
      };

  ObjectTypeDefinition _object(ObjectTypeDefinition node, ChildReader read) =>
      ObjectTypeDefinition(
        description: read.optional(),
        read.one(),
        interfaces: read.all(),
        directives: read.all(),
        fields: read.all(),
        start: node.start,
        end: node.end,
      );

  InterfaceTypeDefinition _interface(
    InterfaceTypeDefinition node,
    ChildReader read,
  ) => InterfaceTypeDefinition(
    description: read.optional(),
    read.one(),
    interfaces: read.all(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );

  UnionTypeDefinition _union(UnionTypeDefinition node, ChildReader read) =>
      UnionTypeDefinition(
        description: read.optional(),
        read.one(),
        directives: read.all(),
        types: read.all(),
        start: node.start,
        end: node.end,
      );

  EnumTypeDefinition _enum(EnumTypeDefinition node, ChildReader read) =>
      EnumTypeDefinition(
        description: read.optional(),
        read.one(),
        directives: read.all(),
        values: read.all(),
        start: node.start,
        end: node.end,
      );

  InputObjectTypeDefinition _inputObject(
    InputObjectTypeDefinition node,
    ChildReader read,
  ) => InputObjectTypeDefinition(
    description: read.optional(),
    read.one(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );
}
```

Create `packages/typed_graphql/lib/src/language/ast/type_system_extension.dart`:

```dart
import 'child_reader.dart';
import 'definition.dart';
import 'directive.dart';
import 'enum_value_definition.dart';
import 'field_definition.dart';
import 'input_value_definition.dart';
import 'name.dart';
import 'node.dart';
import 'operation_type_definition.dart';
import 'type_ref.dart';
import 'type_system_extension_rebuilder.dart';

/// An extension of a schema, a type or a directive (spec §3.3.2, §3.4.3;
/// the directive extension is a working-draft option).
sealed class TypeSystemExtension({
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Definition {
  /// Creates a type system extension.
  this;

  /// The directives the extension adds, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  TypeSystemExtension rebuildFrom(ChildReader read) =>
      const TypeSystemExtensionRebuilder().rebuild(this, read);
}

/// `extend schema @d { query: Query }` (spec §3.3.2).
final class SchemaExtension({
  super.directives,
  List<OperationTypeDefinition> operationTypes = const [],
  super.start,
  super.end,
}) extends TypeSystemExtension {
  /// Creates a schema extension.
  this;

  /// The root operation types it adds, in source order.
  final List<OperationTypeDefinition> operationTypes = List.unmodifiable(
    operationTypes,
  );

  @override
  List<Node> get children => [...directives, ...operationTypes];
}

/// `extend directive @name @d` (working draft, behind
/// `ParserOptions.allowDirectiveExtensions`).
final class DirectiveExtension(
  /// The directive name, without the `@`.
  final Name name, {
  super.directives,
  super.start,
  super.end,
}) extends TypeSystemExtension {
  /// Creates a directive extension.
  this;

  @override
  List<Node> get children => [name, ...directives];
}

/// An extension of a named type (spec §3.4.3).
sealed class TypeExtension(
  /// The name of the type it extends.
  final Name name, {
  super.directives,
  super.start,
  super.end,
}) extends TypeSystemExtension {
  /// Creates a type extension.
  this;
}

/// `extend scalar Name @d` (spec §3.5.1).
final class ScalarTypeExtension(
  super.name, {
  super.directives,
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates a scalar type extension.
  this;

  @override
  List<Node> get children => [name, ...directives];
}

/// `extend type Name implements I @d { fields }` (spec §3.6.3).
final class ObjectTypeExtension(
  super.name, {
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an object type extension.
  this;

  /// The interfaces it adds, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields it adds, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [name, ...interfaces, ...directives, ...fields];
}

/// `extend interface Name implements I @d { fields }` (spec §3.7.1).
final class InterfaceTypeExtension(
  super.name, {
  List<NamedType> interfaces = const [],
  super.directives,
  List<FieldDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an interface type extension.
  this;

  /// The interfaces it adds, in source order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields it adds, in source order.
  final List<FieldDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [name, ...interfaces, ...directives, ...fields];
}

/// `extend union Name @d = A | B` (spec §3.8.1).
final class UnionTypeExtension(
  super.name, {
  super.directives,
  List<NamedType> types = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates a union type extension.
  this;

  /// The member types it adds, in source order.
  final List<NamedType> types = List.unmodifiable(types);

  @override
  List<Node> get children => [name, ...directives, ...types];
}

/// `extend enum Name @d { VALUES }` (spec §3.9.1).
final class EnumTypeExtension(
  super.name, {
  super.directives,
  List<EnumValueDefinition> values = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an enum type extension.
  this;

  /// The values it adds, in source order.
  final List<EnumValueDefinition> values = List.unmodifiable(values);

  @override
  List<Node> get children => [name, ...directives, ...values];
}

/// `extend input Name @d { fields }` (spec §3.10.1).
final class InputObjectTypeExtension(
  super.name, {
  super.directives,
  List<InputValueDefinition> fields = const [],
  super.start,
  super.end,
}) extends TypeExtension {
  /// Creates an input object type extension.
  this;

  /// The input fields it adds, in source order.
  final List<InputValueDefinition> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => [name, ...directives, ...fields];
}
```

Create `packages/typed_graphql/lib/src/language/ast/type_system_extension_rebuilder.dart`:

```dart
import 'child_reader.dart';
import 'node.dart';
import 'type_system_extension.dart';

/// Rebuilds a [TypeSystemExtension] for [Node.withChildren]; apart from
/// the node classes so their library stays within the size limit.
final class const TypeSystemExtensionRebuilder() {
  /// Creates the rebuilder.
  this;

  /// An extension of [node]'s kind, with its positions and the children
  /// [read] returns.
  TypeSystemExtension rebuild(TypeSystemExtension node, ChildReader read) =>
      switch (node) {
        SchemaExtension() => SchemaExtension(
          directives: read.all(),
          operationTypes: read.all(),
          start: node.start,
          end: node.end,
        ),
        DirectiveExtension() => DirectiveExtension(
          read.one(),
          directives: read.all(),
          start: node.start,
          end: node.end,
        ),
        ScalarTypeExtension() => ScalarTypeExtension(
          read.one(),
          directives: read.all(),
          start: node.start,
          end: node.end,
        ),
        ObjectTypeExtension() => _object(node, read),
        InterfaceTypeExtension() => _interface(node, read),
        UnionTypeExtension() => _union(node, read),
        EnumTypeExtension() => _enum(node, read),
        InputObjectTypeExtension() => _inputObject(node, read),
      };

  ObjectTypeExtension _object(ObjectTypeExtension node, ChildReader read) =>
      ObjectTypeExtension(
        read.one(),
        interfaces: read.all(),
        directives: read.all(),
        fields: read.all(),
        start: node.start,
        end: node.end,
      );

  InterfaceTypeExtension _interface(
    InterfaceTypeExtension node,
    ChildReader read,
  ) => InterfaceTypeExtension(
    read.one(),
    interfaces: read.all(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );

  UnionTypeExtension _union(UnionTypeExtension node, ChildReader read) =>
      UnionTypeExtension(
        read.one(),
        directives: read.all(),
        types: read.all(),
        start: node.start,
        end: node.end,
      );

  EnumTypeExtension _enum(EnumTypeExtension node, ChildReader read) =>
      EnumTypeExtension(
        read.one(),
        directives: read.all(),
        values: read.all(),
        start: node.start,
        end: node.end,
      );

  InputObjectTypeExtension _inputObject(
    InputObjectTypeExtension node,
    ChildReader read,
  ) => InputObjectTypeExtension(
    read.one(),
    directives: read.all(),
    fields: read.all(),
    start: node.start,
    end: node.end,
  );
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/type_system_test.dart)
```

Expected: `+8: All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -87,8 +87,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 - `ast/`: every node extends `Node` (`start`, `end`, `children` in
   graphql-js key order, `withChildren`, `isEquivalentTo`). Leaves are
   `const`; a node with a list copies it with `List.unmodifiable`. A node
-  overrides `rebuildFrom(ChildReader)` for `withChildren`. `scalars` lists
-  what `isEquivalentTo` compares besides children.
+  overrides `rebuildFrom(ChildReader)` for `withChildren`; the two
+  type-system families delegate it to a `*_rebuilder.dart` (size limit).
+  `scalars` lists what `isEquivalentTo` compares besides children.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/enum_value_definition.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/field_definition.dart';
export 'src/language/ast/input_value_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/operation_type_definition.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/type_system_definition.dart';
export 'src/language/ast/type_system_extension.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/ast/enum_value_definition.dart packages/typed_graphql/lib/src/language/ast/field_definition.dart packages/typed_graphql/lib/src/language/ast/input_value_definition.dart packages/typed_graphql/lib/src/language/ast/operation_type_definition.dart packages/typed_graphql/lib/src/language/ast/type_system_definition.dart packages/typed_graphql/lib/src/language/ast/type_system_definition_rebuilder.dart packages/typed_graphql/lib/src/language/ast/type_system_extension.dart packages/typed_graphql/lib/src/language/ast/type_system_extension_rebuilder.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/ast/type_system_test.dart
git commit -q -m "feat(typed_graphql): add the type system syntax nodes"
```

### Task 5: Tokens and the block-string algorithms

`BlockString` holds the specification's `BlockStringValue` and graphql-js's `printBlockString`. The lexer and the printer share it (spec §3).

**Files:**
- Create: `packages/typed_graphql/lib/src/language/lexer/block_string.dart`, `packages/typed_graphql/lib/src/language/lexer/token.dart`, `packages/typed_graphql/lib/src/language/lexer/token_kind.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/lexer/block_string_test.dart`, `packages/typed_graphql/test/language/lexer/token_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `enum TokenKind(final String description)`:
    - the fourteen punctuators from `bang` (`"!"`) to `braceRight` (`"}"`), then `name`, `int`, `float`, `string`, `blockString`, `comment`, `error`, `eof` (`<EOF>`);
    - `bool get isPunctuator`.
  - `final class const Token(TokenKind kind, int start, int end, {String? value})`, with `String get description` (graphql-js's `getTokenDesc`) and `toString()`.
  - `final class BlockString` (`const BlockString()`):
    - `String valueOf(String raw)`;
    - `List<String> dedentLines(List<String> lines)`;
    - `bool isPrintable(String value)`;
    - `String print(String value, {bool isMinified = false})`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/lexer/block_string_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const blockString = BlockString();

  group('valueOf', () {
    test('removes the common indentation and blank edge lines', () {
      const raw =
          '\n    Hello,\n      World!\n\n    Yours,\n      GraphQL.\n  ';
      expect(
        blockString.valueOf(raw),
        'Hello,\n  World!\n\nYours,\n  GraphQL.',
      );
    });

    test('treats CR LF and CR as line terminators', () {
      expect(blockString.valueOf('\r\n  a\r  b\r\n'), 'a\nb');
    });
  });

  group('dedentLines', () {
    test('keeps the indentation of the first line', () {
      expect(blockString.dedentLines([' a', '  b']), [' a', 'b']);
    });

    test('ignores blank lines when it measures the indentation', () {
      expect(blockString.dedentLines(['a', ' ', '  b']), ['a', '', 'b']);
    });

    test('an empty string has no lines', () {
      expect(blockString.dedentLines(['']), isEmpty);
    });
  });

  group('isPrintable', () {
    test('accepts plain text and the empty string', () {
      expect(blockString.isPrintable(''), isTrue);
      expect(blockString.isPrintable(' a'), isTrue);
    });

    test('rejects control characters and carriage returns', () {
      expect(blockString.isPrintable('a\x00b'), isFalse);
      expect(blockString.isPrintable('a\rb'), isFalse);
    });

    test('rejects leading or trailing empty lines and common indent', () {
      expect(blockString.isPrintable('\na'), isFalse);
      expect(blockString.isPrintable('a\n'), isFalse);
      expect(blockString.isPrintable('\t"\n \n\t"'), isFalse);
    });
  });

  group('print', () {
    test('prints a short value on one line', () {
      expect(blockString.print('one liner'), '"""one liner"""');
    });

    test('escapes triple quotes and puts them on their own lines', () {
      expect(blockString.print('a """'), '"""\na \\"""\n"""');
      expect(blockString.print('a """', isMinified: true), r'"""a \""""""');
    });

    test('a trailing backslash forces a trailing line break', () {
      expect(
        blockString.print(r'backslash \', isMinified: true),
        '"""backslash \\\n"""',
      );
    });

    test('a value with internal indentation starts on a new line', () {
      expect(
        blockString.print('no indent\n with indent', isMinified: true),
        '"""\nno indent\n with indent"""',
      );
    });
  });
}
```

Create `packages/typed_graphql/test/language/lexer/token_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('TokenKind', () {
    test('punctuators are the fourteen kinds from "!" to "}"', () {
      final punctuators = [
        for (final kind in TokenKind.values)
          if (kind.isPunctuator) kind.description,
      ];
      expect(punctuators, [
        '"!"',
        r'"$"',
        '"&"',
        '"("',
        '")"',
        '"..."',
        '":"',
        '"="',
        '"@"',
        '"["',
        '"]"',
        '"{"',
        '"|"',
        '"}"',
      ]);
    });

    test('the end of the document is described as <EOF>', () {
      expect(TokenKind.eof.description, '<EOF>');
      expect(TokenKind.eof.isPunctuator, isFalse);
    });
  });

  group('Token', () {
    test('a token with a value is described with the value in quotes', () {
      const token = Token(TokenKind.name, 0, 2, value: 'id');
      expect(token.description, 'Name "id"');
    });

    test('a punctuator is described by its kind alone', () {
      expect(const Token(TokenKind.braceLeft, 0, 1).description, '"{"');
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/block_string_test.dart test/language/lexer/token_test.dart)
```

Expected: FAIL to compile: `Method not found: 'BlockString'` and `Undefined name 'TokenKind'`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/language/lexer/block_string.dart`:

```dart
import 'dart:math';

/// The block string algorithms: the value of a block string
/// (`BlockStringValue`, spec §2.9.4) and how a printer writes one, ported
/// from graphql-js's `blockString.ts` so printed output matches.
final class BlockString {
  /// Creates the algorithms; they keep no state.
  const BlockString();

  static final RegExp _lineTerminator = RegExp('\r\n|[\n\r]');

  /// The value of a block string whose raw text, between the quotes and
  /// with `\"""` already unescaped, is [raw].
  String valueOf(String raw) =>
      dedentLines(raw.split(_lineTerminator)).join('\n');

  /// [lines] without the common indentation of all lines but the first
  /// and without leading and trailing blank lines.
  List<String> dedentLines(List<String> lines) {
    int? commonIndent;
    int? firstNonEmpty;
    var lastNonEmpty = -1;
    for (var i = 0; i < lines.length; i++) {
      final indent = _leadingWhiteSpace(lines[i]);
      if (indent == lines[i].length) {
        continue;
      }
      firstNonEmpty ??= i;
      lastNonEmpty = i;
      if (i != 0 && (commonIndent == null || indent < commonIndent)) {
        commonIndent = indent;
      }
    }
    final indent = commonIndent ?? 0;
    return [
      for (var i = firstNonEmpty ?? 0; i <= lastNonEmpty; i++)
        _withoutIndent(lines[i], i == 0 ? 0 : indent),
    ];
  }

  /// Whether [value] prints as a block string with the same value: no
  /// control characters, no `\r`, no leading or trailing empty line and
  /// no indentation common to every line.
  bool isPrintable(String value) {
    if (value.isEmpty) {
      return true;
    }
    final scan = _PrintableScan();
    for (final unit in value.codeUnits) {
      if (!scan.accept(unit)) {
        return false;
      }
    }
    return !scan.isEmptyLine &&
        !(scan.hasCommonIndent && scan.seenNonEmptyLine);
  }

  /// [value] as block string source, `"""` included: on separate lines
  /// unless [isMinified] or it reads better on one line.
  String print(String value, {bool isMinified = false}) {
    final escaped = value.replaceAll('"""', r'\"""');
    final lines = escaped.split(_lineTerminator);
    final isSingleLine = lines.length == 1;
    final forceLeadingNewLine =
        lines.length > 1 &&
        lines
            .skip(1)
            .every((line) => line.isEmpty || _isWhiteSpace(line.codeUnitAt(0)));
    final hasTrailingTripleQuotes = escaped.endsWith(r'\"""');
    final forceTrailingNewLine =
        (value.endsWith('"') && !hasTrailingTripleQuotes) ||
        value.endsWith(r'\');
    final printAsMultipleLines =
        !isMinified &&
        (!isSingleLine ||
            value.length > 70 ||
            forceTrailingNewLine ||
            forceLeadingNewLine ||
            hasTrailingTripleQuotes);
    final skipLeadingNewLine =
        isSingleLine && value.isNotEmpty && _isWhiteSpace(value.codeUnitAt(0));
    final leading =
        (printAsMultipleLines && !skipLeadingNewLine) || forceLeadingNewLine;
    final trailing = printAsMultipleLines || forceTrailingNewLine;
    return '"""${leading ? '\n' : ''}$escaped${trailing ? '\n' : ''}"""';
  }

  static String _withoutIndent(String line, int indent) =>
      line.substring(min(indent, line.length));

  static int _leadingWhiteSpace(String line) {
    var i = 0;
    while (i < line.length && _isWhiteSpace(line.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  static bool _isWhiteSpace(int unit) => unit == 0x09 || unit == 0x20;
}

/// The state of [BlockString.isPrintable] as it reads a value.
final class _PrintableScan {
  bool isEmptyLine = true;
  bool hasIndent = false;
  bool hasCommonIndent = true;
  bool seenNonEmptyLine = false;

  /// Reads one code unit; false when the value cannot be a block string.
  bool accept(int unit) {
    switch (unit) {
      case 0x0d || <= 0x08 || 0x0b || 0x0c || 0x0e || 0x0f:
        return false;
      case 0x0a:
        if (isEmptyLine && !seenNonEmptyLine) {
          return false;
        }
        seenNonEmptyLine = true;
        isEmptyLine = true;
        hasIndent = false;
      case 0x09 || 0x20:
        hasIndent = hasIndent || isEmptyLine;
      default:
        hasCommonIndent = hasCommonIndent && hasIndent;
        isEmptyLine = false;
    }
    return true;
  }
}
```

Create `packages/typed_graphql/lib/src/language/lexer/token.dart`:

```dart
import 'package:meta/meta.dart';

import 'token_kind.dart';

/// One lexical token: its [kind], its offsets and, for names, numbers and
/// strings, its [value].
@immutable
final class const Token(
  /// The kind of token.
  final TokenKind kind,

  /// The offset of the first code unit, in UTF-16 code units.
  final int start,

  /// The offset after the last code unit.
  final int end, {

  /// The name, the raw number lexeme, the decoded string or the comment
  /// text without `#`; null for punctuators, errors and the end.
  final String? value,
}) {
  /// Creates a token.
  this;

  /// How a message names this token: its kind, then its value in quotes,
  /// such as `Name "id"` (graphql-js's `getTokenDesc`).
  String get description =>
      value == null ? kind.description : '${kind.description} "$value"';

  @override
  String toString() => '$description@$start:$end';
}
```

Create `packages/typed_graphql/lib/src/language/lexer/token_kind.dart`:

```dart
/// The kinds of lexical tokens (spec §2.1.6), plus [comment], [error] and
/// [eof].
enum TokenKind(
  /// How a message names the kind, as graphql-js does: a punctuator in
  /// quotes, such as `"{"`, other kinds by name, such as `Name`.
  final String description,
) {
  /// `!`.
  bang('"!"'),

  /// `$`.
  dollar(r'"$"'),

  /// `&`.
  ampersand('"&"'),

  /// `(`.
  parenLeft('"("'),

  /// `)`.
  parenRight('")"'),

  /// `...`.
  spread('"..."'),

  /// `:`.
  colon('":"'),

  /// `=`.
  equals('"="'),

  /// `@`.
  at('"@"'),

  /// `[`.
  bracketLeft('"["'),

  /// `]`.
  bracketRight('"]"'),

  /// `{`.
  braceLeft('"{"'),

  /// `|`.
  pipe('"|"'),

  /// `}`.
  braceRight('"}"'),

  /// A name or a keyword.
  name('Name'),

  /// An integer literal.
  int('Int'),

  /// A float literal.
  float('Float'),

  /// A quoted string.
  string('String'),

  /// A block string, `"""..."""`.
  blockString('BlockString'),

  /// A comment, produced only when the lexer keeps comments.
  comment('Comment'),

  /// Text that is not a token; the lexer reported a diagnostic for it.
  error('Error'),

  /// The end of the document.
  eof('<EOF>');

  /// Whether this kind is a punctuator, such as `{` or `...`.
  bool get isPunctuator => index <= braceRight.index;
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/block_string_test.dart test/language/lexer/token_test.dart)
```

Expected: `block_string_test.dart` `+12`, `token_test.dart` `+4`, each `All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -90,6 +90,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   overrides `rebuildFrom(ChildReader)` for `withChildren`; the two
   type-system families delegate it to a `*_rebuilder.dart` (size limit).
   `scalars` lists what `isEquivalentTo` compares besides children.
+- `lexer/`: `Token` (`kind`, `start`, `end`, `value`) and `TokenKind`, whose
+  `description` is how messages name it. `BlockString` holds the spec's
+  `BlockStringValue` and graphql-js's printing rules; lexer and printer share
+  it.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/enum_value_definition.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/field_definition.dart';
export 'src/language/ast/input_value_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/operation_type_definition.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/type_system_definition.dart';
export 'src/language/ast/type_system_extension.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/language/lexer/block_string.dart';
export 'src/language/lexer/token.dart';
export 'src/language/lexer/token_kind.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/lexer/block_string.dart packages/typed_graphql/lib/src/language/lexer/token.dart packages/typed_graphql/lib/src/language/lexer/token_kind.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/lexer/block_string_test.dart packages/typed_graphql/test/language/lexer/token_test.dart
git commit -q -m "feat(typed_graphql): add tokens and the block string algorithms"
```

### Task 6: Lexer: names, numbers, punctuators and comments

**Files:**
- Create: `packages/typed_graphql/lib/src/language/lexer/character_class.dart`, `packages/typed_graphql/lib/src/language/lexer/lexer.dart`, `packages/typed_graphql/lib/src/language/lexer/number_scanner.dart`, `packages/typed_graphql/lib/src/language/lexer/source_reader.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/lexer/lexed.dart`, `packages/typed_graphql/test/language/lexer/lexer_test.dart`

**Interfaces:**
- Consumes: Task 5: `Token`, `TokenKind`; M1: `Source`, `DiagnosticSink`, `DiagnosticCode`.
- Produces:
  - `final class Lexer(Source source, DiagnosticSink sink, {bool keepComments = false})`:
    - `Token advance()` never throws, and returns `eof` again after the end;
    - `Source get source`.
  - Internal `SourceReader`: `unitAt`, `slice`, `characterWidthAt`, `describe` (graphql-js's `printCodePointAt`), `report`.
  - Internal `CharacterClass` (character tests) and `NumberScanner`.
  - New codes: `GQL001 unexpectedCharacter`, `GQL002 invalidCharacter`, `GQL003 invalidNumber`.
  - Test helper `Lexed(text, {keepComments})`, with `tokens`, `diagnostics`, `described` and `errors` (`'line:column GQLnnn message'`).

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/lexer/lexed.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The tokens and diagnostics of lexing one text, for tests.
final class Lexed {
  /// Lexes [text] to the end.
  factory Lexed(String text, {bool keepComments = false}) {
    final sink = DiagnosticSink();
    final lexer = Lexer(Source(text), sink, keepComments: keepComments);
    final tokens = <Token>[];
    for (var token = lexer.advance(); token.kind != .eof;) {
      tokens.add(token);
      token = lexer.advance();
    }
    return Lexed._(tokens, sink.diagnostics);
  }

  Lexed._(this.tokens, this.diagnostics);

  /// The tokens before the end.
  final List<Token> tokens;

  /// What the lexer reported.
  final List<Diagnostic> diagnostics;

  /// Each token as `kind start:end value`.
  List<String> get described => [
    for (final token in tokens)
      '${token.kind.name} ${token.start}:${token.end}'
          '${token.value == null ? '' : ' ${token.value}'}',
  ];

  /// Each diagnostic as `line:column id message`.
  List<String> get errors => [
    for (final diagnostic in diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];
}
```

Create `packages/typed_graphql/test/language/lexer/lexer_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'lexed.dart';

void main() {
  group('ignored tokens', () {
    test('skips the BOM, white space, commas and line terminators', () {
      expect(Lexed('﻿ ,\t\r\n\rfoo,').described, ['name 7:10 foo']);
    });

    test('drops comments unless asked to keep them', () {
      expect(Lexed('# hi\nfoo').described, ['name 5:8 foo']);
      expect(Lexed('# hi\r\nfoo', keepComments: true).described, [
        'comment 0:4  hi',
        'name 6:9 foo',
      ]);
    });

    test('an empty document is only the end', () {
      expect(Lexed('').tokens, isEmpty);
      expect(Lexed(' \n ').diagnostics, isEmpty);
    });
  });

  group('punctuators and names', () {
    test('lexes every punctuator', () {
      final kinds = [
        for (final token in Lexed(r'! $ & ( ) ... : = @ [ ] { | }').tokens)
          token.kind,
      ];
      expect(kinds, [
        for (final kind in TokenKind.values)
          if (kind.isPunctuator) kind,
      ]);
    });

    test('lexes names with digits and underscores', () {
      expect(Lexed('_a1 B_2').described, ['name 0:3 _a1', 'name 4:7 B_2']);
    });
  });

  group('numbers', () {
    test('keeps the lexeme of integers and floats', () {
      expect(Lexed('4 -0 9007199254740993 1.5e-3 0.0 2E+5').described, [
        'int 0:1 4',
        'int 2:4 -0',
        'int 5:21 9007199254740993',
        'float 22:28 1.5e-3',
        'float 29:32 0.0',
        'float 33:37 2E+5',
      ]);
    });

    test('rejects a leading zero', () {
      final lexed = Lexed('007');
      expect(lexed.errors, [
        '1:2 GQL003 Invalid number, unexpected digit after 0: "0".',
      ]);
      expect(lexed.described, ['error 0:3']);
    });

    test('rejects missing digits after "-", "." and the exponent', () {
      expect(Lexed('-').errors, [
        '1:2 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
      expect(Lexed('1.').errors, [
        '1:3 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
      expect(Lexed('1.0e').errors, [
        '1:5 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
    });

    test('rejects a name or a dot glued to a number', () {
      final lexed = Lexed('1a 1.2.3 x');
      expect(lexed.errors, [
        '1:2 GQL003 Invalid number, expected digit but got: "a".',
        '1:7 GQL003 Invalid number, expected digit but got: ".".',
      ]);
      expect(lexed.described, ['error 0:2', 'error 3:8', 'name 9:10 x']);
    });

    test('rejects a number without its integer part', () {
      expect(Lexed('.123').errors, [
        '1:1 GQL003 Invalid number, expected digit before ".", '
            'did you mean "0.123"?',
      ]);
    });

    test('reports a dash in a name as a malformed number', () {
      expect(Lexed('a-b').errors, [
        '1:3 GQL003 Invalid number, expected digit but got: "b".',
      ]);
    });
  });

  group('unexpected characters', () {
    test('reports one error per character and resumes after it', () {
      final lexed = Lexed('a ~ b');
      expect(lexed.errors, ['1:3 GQL001 Unexpected character: "~".']);
      expect(lexed.described, ['name 0:1 a', 'error 2:3', 'name 4:5 b']);
    });

    test('suggests a spread for two dots and a double quote for one', () {
      expect(Lexed('..').errors, [
        '1:1 GQL001 Unexpected "..", did you mean "..."?',
      ]);
      expect(Lexed("'a'").errors.first, contains('did you mean to use a'));
    });

    test('names a control character and a supplementary character', () {
      expect(Lexed('\u0007').errors, [
        '1:1 GQL001 Unexpected character: U+0007.',
      ]);
      expect(Lexed('\u{1F600}').errors, [
        '1:1 GQL001 Unexpected character: U+1F600.',
      ]);
    });

    test('reports a lone surrogate as an invalid character', () {
      expect(Lexed('\uDEAD').errors, [
        '1:1 GQL002 Invalid character: U+DEAD.',
      ]);
    });

    test('a comment ends before a lone surrogate', () {
      final lexed = Lexed('# a\uD800', keepComments: true);
      expect(lexed.described, ['comment 0:3  a', 'error 3:4']);
    });
  });

  test('the end is returned again after the end', () {
    final lexer = Lexer(Source('a'), DiagnosticSink());
    lexer.advance();
    expect(lexer.advance().kind, TokenKind.eof);
    expect(lexer.advance().kind, TokenKind.eof);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/lexer_test.dart)
```

Expected: FAIL to compile: `Method not found: 'Lexer'`.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -24,5 +24,17 @@ enum DiagnosticCode(
   /// `GQL000`: a sink kept as many errors as its limit allows and dropped
   /// the rest. It is reported once, at the place of the first dropped
   /// error; the run behind the sink should stop.
-  diagnosticLimitReached('GQL000');
+  diagnosticLimitReached('GQL000'),
+
+  /// `GQL001`: a character that starts no token, such as `~`, a single
+  /// quote or `..`.
+  unexpectedCharacter('GQL001'),
+
+  /// `GQL002`: a code unit that is not part of a Unicode scalar value: a
+  /// surrogate without its pair, in or outside a string (spec §2.1.1).
+  invalidCharacter('GQL002'),
+
+  /// `GQL003`: a malformed number, such as `007`, `1.`, `.5`, `1e` or a
+  /// name glued to a number (`1a`).
+  invalidNumber('GQL003');
 }
```

Create `packages/typed_graphql/lib/src/language/lexer/character_class.dart`:

```dart
/// The character classes of the lexical grammar (spec §2.1), over UTF-16
/// code units; -1 stands for the end of the document and is in no class.
final class CharacterClass {
  /// Creates the classes; they keep no state.
  const CharacterClass();

  /// Whether [unit] is `0`–`9`.
  bool isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// Whether [unit] is a letter `A`–`Z` or `a`–`z`.
  bool isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);

  /// Whether [unit] may start a name: a letter or `_`.
  bool isNameStart(int unit) => isLetter(unit) || unit == 0x5f;

  /// Whether [unit] may continue a name: a letter, a digit or `_`.
  bool isNameContinue(int unit) => isNameStart(unit) || isDigit(unit);

  /// Whether [point] is a Unicode scalar value: a code point that is not
  /// a surrogate.
  bool isScalarValue(int point) =>
      (point >= 0 && point <= 0xd7ff) || (point >= 0xe000 && point <= 0x10ffff);

  /// Whether [unit] is the first half of a surrogate pair.
  bool isLeadingSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

  /// Whether [unit] is the second half of a surrogate pair.
  bool isTrailingSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

  /// The value of the hexadecimal digit [unit], or -1 when it is none.
  int hexValue(int unit) => switch (unit) {
    >= 0x30 && <= 0x39 => unit - 0x30,
    >= 0x41 && <= 0x46 => unit - 0x37,
    >= 0x61 && <= 0x66 => unit - 0x57,
    _ => -1,
  };
}
```

Create `packages/typed_graphql/lib/src/language/lexer/lexer.dart`:

```dart
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import 'character_class.dart';
import 'number_scanner.dart';
import 'source_reader.dart';
import 'token.dart';
import 'token_kind.dart';

/// Turns a [Source] into tokens, one per [advance] (spec §2.1).
///
/// The lexer never throws (R1.2): text that is no token becomes one
/// [TokenKind.error] token over the offending run and one diagnostic in
/// the sink, and scanning resumes after it. Ignored tokens are skipped;
/// comments are returned only when [keepComments] is set.
final class Lexer {
  /// Creates a lexer of [source] that reports into [sink].
  Lexer(Source source, DiagnosticSink sink, {bool keepComments = false})
    : this._(SourceReader(source, sink), keepComments: keepComments);

  Lexer._(SourceReader reader, {required this.keepComments})
    : _reader = reader,
      _numbers = NumberScanner(reader);

  /// Whether [advance] returns [TokenKind.comment] tokens.
  final bool keepComments;

  final SourceReader _reader;
  final NumberScanner _numbers;
  int _position = 0;

  static const CharacterClass _classes = CharacterClass();

  static const Map<int, TokenKind> _punctuators = {
    0x21: .bang,
    0x24: .dollar,
    0x26: .ampersand,
    0x28: .parenLeft,
    0x29: .parenRight,
    0x3a: .colon,
    0x3d: .equals,
    0x40: .at,
    0x5b: .bracketLeft,
    0x5d: .bracketRight,
    0x7b: .braceLeft,
    0x7c: .pipe,
    0x7d: .braceRight,
  };

  /// The next token; [TokenKind.eof] at the end, and again on every later
  /// call.
  Token advance() {
    var token = _scanFrom(_position);
    while (token.kind == .comment && !keepComments) {
      token = _scanFrom(token.end);
    }
    return token;
  }

  Token _scanFrom(int offset) {
    final token = _scan(_skipIgnored(offset));
    _position = token.end;
    return token;
  }

  /// The offset of the first character from [offset] on that is not
  /// white space, a line terminator, a comma or a byte order mark.
  int _skipIgnored(int offset) {
    var position = offset;
    while (_isIgnored(_reader.unitAt(position))) {
      position++;
    }
    return position;
  }

  static bool _isIgnored(int unit) => switch (unit) {
    0xfeff || 0x09 || 0x20 || 0x2c || 0x0a || 0x0d => true,
    _ => false,
  };

  Token _scan(int at) {
    final unit = _reader.unitAt(at);
    if (_punctuators[unit] case final kind?) {
      return Token(kind, at, at + 1);
    }
    return switch (unit) {
      -1 => Token(.eof, at, at),
      0x23 => _comment(at),
      0x2e => _dot(at),
      _ when _classes.isDigit(unit) || unit == 0x2d => _numbers.scan(at),
      _ when _classes.isNameStart(unit) => _name(at),
      _ => _unexpected(at),
    };
  }

  Token _name(int start) {
    var end = start + 1;
    while (_classes.isNameContinue(_reader.unitAt(end))) {
      end++;
    }
    return Token(.name, start, end, value: _reader.slice(start, end));
  }

  /// A comment runs to a line terminator or to a character that is not
  /// a source character, which the next token reports.
  Token _comment(int start) {
    var end = start + 1;
    while (_reader.unitAt(end) != 0x0a && _reader.unitAt(end) != 0x0d) {
      final width = _reader.characterWidthAt(end);
      if (width == 0) {
        break;
      }
      end += width;
    }
    return Token(.comment, start, end, value: _reader.slice(start + 1, end));
  }

  Token _dot(int at) {
    if (_reader.unitAt(at + 1) != 0x2e) {
      return _classes.isDigit(_reader.unitAt(at + 1))
          ? _leadingDot(at)
          : _unexpected(at);
    }
    if (_reader.unitAt(at + 2) == 0x2e) {
      return Token(.spread, at, at + 3);
    }
    const message = 'Unexpected "..", did you mean "..."?';
    _reader.report(.unexpectedCharacter, message, at, at + 2);
    return Token(.error, at, at + 2);
  }

  /// `.5`: a number without its integer part.
  Token _leadingDot(int at) {
    var end = at + 1;
    while (_classes.isDigit(_reader.unitAt(end))) {
      end++;
    }
    final digits = _reader.slice(at + 1, end);
    _reader.report(
      .invalidNumber,
      'Invalid number, expected digit before ".", did you mean "0.$digits"?',
      at,
      end,
    );
    return Token(.error, at, end);
  }

  Token _unexpected(int at) {
    final width = _reader.characterWidthAt(at);
    final character = _reader.describe(at);
    final end = at + (width == 0 ? 1 : width);
    if (_reader.unitAt(at) == 0x27) {
      const message =
          'Unexpected single quote character (\'), did you mean to use a '
          'double quote (")?';
      _reader.report(.unexpectedCharacter, message, at, end);
    } else if (width == 0) {
      final message = 'Invalid character: $character.';
      _reader.report(.invalidCharacter, message, at, end);
    } else {
      final message = 'Unexpected character: $character.';
      _reader.report(.unexpectedCharacter, message, at, end);
    }
    return Token(.error, at, end);
  }
}
```

Create `packages/typed_graphql/lib/src/language/lexer/number_scanner.dart`:

```dart
import 'character_class.dart';
import 'source_reader.dart';
import 'token.dart';
import 'token_kind.dart';

/// Scans an `IntValue` or a `FloatValue` (spec §2.9.1, §2.9.2), keeping
/// the lexeme as written.
final class NumberScanner {
  /// Creates a scanner of the text of [reader].
  NumberScanner(this.reader);

  /// The text and the sink.
  final SourceReader reader;

  static const CharacterClass _classes = CharacterClass();
  static const int _minus = 0x2d;
  static const int _plus = 0x2b;
  static const int _dot = 0x2e;
  static const int _zero = 0x30;

  /// The number that starts at [start] with a digit or `-`, or an error
  /// token over the malformed run after one diagnostic.
  Token scan(int start) {
    final position = reader.unitAt(start) == _minus ? start + 1 : start;
    if (reader.unitAt(position) == _zero) {
      if (_classes.isDigit(reader.unitAt(position + 1))) {
        final digit = reader.describe(position + 1);
        return _fail(start, position + 1, 'unexpected digit after 0: $digit');
      }
      return _afterInteger(start, position + 1);
    }
    return switch (_digitsFrom(position)) {
      final end? => _afterInteger(start, end),
      null => _expectedDigit(start, position),
    };
  }

  /// The rest of the number from [start] after its integer part, which
  /// ends at [position]: an optional fraction and exponent.
  Token _afterInteger(int start, int position) {
    var end = position;
    if (reader.unitAt(end) == _dot) {
      final fractionEnd = _digitsFrom(end + 1);
      if (fractionEnd == null) {
        return _expectedDigit(start, end + 1);
      }
      end = fractionEnd;
    }
    if (reader.unitAt(end) case 0x45 || 0x65) {
      final sign = reader.unitAt(end + 1);
      final digits = end + (sign == _plus || sign == _minus ? 2 : 1);
      final exponentEnd = _digitsFrom(digits);
      if (exponentEnd == null) {
        return _expectedDigit(start, digits);
      }
      end = exponentEnd;
    }
    final next = reader.unitAt(end);
    if (next == _dot || _classes.isNameStart(next)) {
      return _expectedDigit(start, end);
    }
    final kind = end == position ? TokenKind.int : TokenKind.float;
    return Token(kind, start, end, value: reader.slice(start, end));
  }

  /// The offset after the digits that start at [position], or null when
  /// there is no digit there.
  int? _digitsFrom(int position) {
    if (!_classes.isDigit(reader.unitAt(position))) {
      return null;
    }
    var end = position + 1;
    while (_classes.isDigit(reader.unitAt(end))) {
      end++;
    }
    return end;
  }

  Token _expectedDigit(int start, int at) =>
      _fail(start, at, 'expected digit but got: ${reader.describe(at)}');

  /// Reports `Invalid number, [problem].` at [at] and returns an error
  /// token from [start] over the rest of the malformed run.
  Token _fail(int start, int at, String problem) {
    reader.report(
      .invalidNumber,
      'Invalid number, $problem.',
      at,
      at + reader.characterWidthAt(at),
    );
    var end = at;
    while (_classes.isNameContinue(reader.unitAt(end)) ||
        reader.unitAt(end) == _dot) {
      end++;
    }
    return Token(.error, start, end);
  }
}
```

Create `packages/typed_graphql/lib/src/language/lexer/source_reader.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../../diagnostics/source_span.dart';
import 'character_class.dart';

/// What the scanners of one lexer share: the text, its characters and the
/// sink errors go to.
final class SourceReader {
  /// Creates a reader of [source] that reports into [sink].
  SourceReader(this.source, this.sink);

  /// The document being read.
  final Source source;

  /// Where errors are reported.
  final DiagnosticSink sink;

  static const CharacterClass _classes = CharacterClass();

  /// The number of code units in the document.
  int get length => source.body.length;

  /// The code unit at [offset], or -1 at and past the end.
  int unitAt(int offset) =>
      offset < source.body.length ? source.body.codeUnitAt(offset) : -1;

  /// The text from [start] to [end], cut at the end of the document.
  String slice(int start, int end) =>
      source.body.substring(start, end < length ? end : length);

  /// The code units of the source character at [offset]: 1, 2 for a
  /// surrogate pair, or 0 when it is a lone surrogate or the end.
  int characterWidthAt(int offset) {
    final unit = unitAt(offset);
    if (_classes.isScalarValue(unit)) {
      return 1;
    }
    final isPair =
        _classes.isLeadingSurrogate(unit) &&
        _classes.isTrailingSurrogate(unitAt(offset + 1));
    return isPair ? 2 : 0;
  }

  /// The character at [offset] as messages show it, as graphql-js's
  /// `printCodePointAt` does: `"a"`, `'"'`, `U+0007`, `U+1F600` or
  /// `<EOF>`.
  String describe(int offset) {
    final unit = unitAt(offset);
    if (unit < 0) {
      return '<EOF>';
    }
    if (unit >= 0x20 && unit <= 0x7e) {
      final character = String.fromCharCode(unit);
      return character == '"' ? "'\"'" : '"$character"';
    }
    final point = characterWidthAt(offset) == 2
        ? 0x10000 + ((unit - 0xd800) << 10) + (unitAt(offset + 1) - 0xdc00)
        : unit;
    return 'U+${point.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  /// Reports an error with [code] and [message] over [start] to [end].
  void report(DiagnosticCode code, String message, int start, int end) {
    final span = SourceSpan(source, start, end < length ? end : length);
    sink.report(Diagnostic(code, .error, message, span: span));
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/lexer_test.dart)
```

Expected: `+17: All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -93,7 +93,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 - `lexer/`: `Token` (`kind`, `start`, `end`, `value`) and `TokenKind`, whose
   `description` is how messages name it. `BlockString` holds the spec's
   `BlockStringValue` and graphql-js's printing rules; lexer and printer share
-  it.
+  it. `Lexer(source, sink).advance()` never throws: bad text becomes one
+  `error` token over the run and one diagnostic, with graphql-js's message
+  minus "Syntax Error: ". Scanners (`*_scanner.dart`) share a
+  `SourceReader` (text, `describe`, `report`); `CharacterClass` holds the
+  character tests.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
- `Lexer`: names, numbers (raw lexemes), punctuators and comments, with
  diagnostics `GQL001`–`GQL003` instead of exceptions.
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/enum_value_definition.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/field_definition.dart';
export 'src/language/ast/input_value_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/operation_type_definition.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/type_system_definition.dart';
export 'src/language/ast/type_system_extension.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/language/lexer/block_string.dart';
export 'src/language/lexer/lexer.dart';
export 'src/language/lexer/token.dart';
export 'src/language/lexer/token_kind.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/language/lexer/character_class.dart packages/typed_graphql/lib/src/language/lexer/lexer.dart packages/typed_graphql/lib/src/language/lexer/number_scanner.dart packages/typed_graphql/lib/src/language/lexer/source_reader.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/lexer/lexed.dart packages/typed_graphql/test/language/lexer/lexer_test.dart
git commit -q -m "feat(typed_graphql): lex names, numbers, punctuators and comments"
```

### Task 7: Lexer: strings, block strings and the token limit

**Files:**
- Create: `packages/typed_graphql/lib/src/language/lexer/block_string_scanner.dart`, `packages/typed_graphql/lib/src/language/lexer/escape_reader.dart`, `packages/typed_graphql/lib/src/language/lexer/string_scanner.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/language/lexer/lexer.dart`
- Test: `packages/typed_graphql/test/language/lexer/lexer_test.dart`, `packages/typed_graphql/test/language/lexer/string_test.dart`

**Interfaces:**
- Consumes: Task 6: `Lexer`, `SourceReader`, `CharacterClass`; Task 5: `BlockString.valueOf`.
- Produces:
  - `Lexer(..., {bool keepComments = false, int? maxTokens})`, with `int get tokenCount` and `bool get isLimitReached`. Past the limit, the lexer reports `GQL006` once, then returns `eof`; comments and `eof` are not counted;
  - internal `StringScanner`, `EscapeReader` (`\uXXXX` with surrogate pairs and `\u{...}`, validated as scalar values) and `BlockStringScanner`;
  - new codes: `GQL004 unterminatedString`, `GQL005 invalidEscapeSequence`, `GQL006 tokenLimitExceeded`.

- [ ] **Step 1: Write the failing tests**

Replace `packages/typed_graphql/test/language/lexer/lexer_test.dart` whole with:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'lexed.dart';

void main() {
  group('ignored tokens', () {
    test('skips the BOM, white space, commas and line terminators', () {
      expect(Lexed('﻿ ,\t\r\n\rfoo,').described, ['name 7:10 foo']);
    });

    test('drops comments unless asked to keep them', () {
      expect(Lexed('# hi\nfoo').described, ['name 5:8 foo']);
      expect(Lexed('# hi\r\nfoo', keepComments: true).described, [
        'comment 0:4  hi',
        'name 6:9 foo',
      ]);
    });

    test('an empty document is only the end', () {
      expect(Lexed('').tokens, isEmpty);
      expect(Lexed(' \n ').diagnostics, isEmpty);
    });
  });

  group('punctuators and names', () {
    test('lexes every punctuator', () {
      final kinds = [
        for (final token in Lexed(r'! $ & ( ) ... : = @ [ ] { | }').tokens)
          token.kind,
      ];
      expect(kinds, [
        for (final kind in TokenKind.values)
          if (kind.isPunctuator) kind,
      ]);
    });

    test('lexes names with digits and underscores', () {
      expect(Lexed('_a1 B_2').described, ['name 0:3 _a1', 'name 4:7 B_2']);
    });
  });

  group('numbers', () {
    test('keeps the lexeme of integers and floats', () {
      expect(Lexed('4 -0 9007199254740993 1.5e-3 0.0 2E+5').described, [
        'int 0:1 4',
        'int 2:4 -0',
        'int 5:21 9007199254740993',
        'float 22:28 1.5e-3',
        'float 29:32 0.0',
        'float 33:37 2E+5',
      ]);
    });

    test('rejects a leading zero', () {
      final lexed = Lexed('007');
      expect(lexed.errors, [
        '1:2 GQL003 Invalid number, unexpected digit after 0: "0".',
      ]);
      expect(lexed.described, ['error 0:3']);
    });

    test('rejects missing digits after "-", "." and the exponent', () {
      expect(Lexed('-').errors, [
        '1:2 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
      expect(Lexed('1.').errors, [
        '1:3 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
      expect(Lexed('1.0e').errors, [
        '1:5 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
    });

    test('rejects a name or a dot glued to a number', () {
      final lexed = Lexed('1a 1.2.3 x');
      expect(lexed.errors, [
        '1:2 GQL003 Invalid number, expected digit but got: "a".',
        '1:7 GQL003 Invalid number, expected digit but got: ".".',
      ]);
      expect(lexed.described, ['error 0:2', 'error 3:8', 'name 9:10 x']);
    });

    test('rejects a number without its integer part', () {
      expect(Lexed('.123').errors, [
        '1:1 GQL003 Invalid number, expected digit before ".", '
            'did you mean "0.123"?',
      ]);
    });

    test('reports a dash in a name as a malformed number', () {
      expect(Lexed('a-b').errors, [
        '1:3 GQL003 Invalid number, expected digit but got: "b".',
      ]);
    });
  });

  group('unexpected characters', () {
    test('reports one error per character and resumes after it', () {
      final lexed = Lexed('a ~ b');
      expect(lexed.errors, ['1:3 GQL001 Unexpected character: "~".']);
      expect(lexed.described, ['name 0:1 a', 'error 2:3', 'name 4:5 b']);
    });

    test('suggests a spread for two dots and a double quote for one', () {
      expect(Lexed('..').errors, [
        '1:1 GQL001 Unexpected "..", did you mean "..."?',
      ]);
      expect(Lexed("'a'").errors.first, contains('did you mean to use a'));
    });

    test('names a control character and a supplementary character', () {
      expect(Lexed('\u0007').errors, [
        '1:1 GQL001 Unexpected character: U+0007.',
      ]);
      expect(Lexed('\u{1F600}').errors, [
        '1:1 GQL001 Unexpected character: U+1F600.',
      ]);
    });

    test('reports a lone surrogate as an invalid character', () {
      expect(Lexed('\uDEAD').errors, [
        '1:1 GQL002 Invalid character: U+DEAD.',
      ]);
    });

    test('a comment ends before a lone surrogate', () {
      final lexed = Lexed('# a\uD800', keepComments: true);
      expect(lexed.described, ['comment 0:3  a', 'error 3:4']);
    });
  });

  test('the end is returned again after the end', () {
    final lexer = Lexer(Source('a'), DiagnosticSink());
    lexer.advance();
    expect(lexer.advance().kind, TokenKind.eof);
    expect(lexer.advance().kind, TokenKind.eof);
  });

  group('maxTokens', () {
    test('replaces the token after the limit by one error and the end', () {
      final sink = DiagnosticSink();
      final lexer = Lexer(Source('{ a b }'), sink, maxTokens: 3);
      final kinds = [for (var i = 0; i < 5; i++) lexer.advance().kind];
      expect(kinds, [
        TokenKind.braceLeft,
        TokenKind.name,
        TokenKind.name,
        TokenKind.eof,
        TokenKind.eof,
      ]);
      expect(lexer.isLimitReached, isTrue);
      expect(
        sink.diagnostics.single.message,
        'Document contains more than 3 tokens. Parsing aborted.',
      );
      expect(sink.diagnostics.single.span?.start, 6);
    });

    test('counts neither comments nor the end', () {
      final lexer = Lexer(
        Source('a # c\n'),
        DiagnosticSink(),
        keepComments: true,
        maxTokens: 1,
      );
      while (lexer.advance().kind != TokenKind.eof) {}
      expect(lexer.tokenCount, 1);
      expect(lexer.isLimitReached, isFalse);
    });
  });
}
```

Create `packages/typed_graphql/test/language/lexer/string_test.dart`:

```dart
import 'package:test/test.dart';

import 'lexed.dart';

void main() {
  group('strings', () {
    test('decode simple and Unicode escapes', () {
      expect(
        Lexed(r'"a\"\\\/\b\f\n\r\t"').tokens.single.value,
        'a"\\/\b\f\n\r\t',
      );
      expect(
        Lexed(r'"A\u{1F600}😀"').tokens.single.value,
        'A\u{1F600}\u{1F600}',
      );
    });

    test('keep a supplementary character as it is', () {
      expect(Lexed('"\u{1F600}"').tokens.single.value, '\u{1F600}');
    });

    test('end at a line break with one error', () {
      final lexed = Lexed('"multi\nline');
      expect(lexed.errors, ['1:7 GQL004 Unterminated string.']);
      expect(lexed.described, ['error 0:6', 'name 7:11 line']);
    });

    test('report an unterminated string at the end', () {
      expect(Lexed('"no end quote').errors, [
        '1:14 GQL004 Unterminated string.',
      ]);
    });

    test('report the first bad escape and skip to the closing quote', () {
      final lexed = Lexed(r'"bad \z and \x" b');
      expect(lexed.errors, [
        r'1:6 GQL005 Invalid character escape sequence: "\z".',
      ]);
      expect(lexed.described, ['error 0:15', 'name 16:17 b']);
    });

    test('quote the text graphql-js quotes for bad Unicode escapes', () {
      final cases = {
        r'"bad \u1 esc"': r'"\u1 es"',
        r'"bad \u{FFFF"': r'"\u{FFFF""',
        r'"x \u{110000} esc"': r'"\u{110000}"',
        r'"x \u{12345678} esc"': r'"\u{12345678}"',
        r'"x \u{000000000} esc"': r'"\u{000000000"',
        r'"x \uD800\uD800 esc"': r'"\uD800"',
        r'"x \u{D83D}\u{DE00}"': r'"\u{D83D}"',
      };
      for (final MapEntry(key: text, value: quoted) in cases.entries) {
        expect(
          Lexed(text).diagnostics.single.message,
          'Invalid Unicode escape sequence: $quoted.',
          reason: text,
        );
      }
    });

    test('reject a lone surrogate', () {
      final lexed = Lexed('"bad \uDEAD"');
      expect(lexed.errors, [
        '1:6 GQL002 Invalid character within String: U+DEAD.',
      ]);
      expect(lexed.described, ['error 0:7']);
    });
  });

  group('block strings', () {
    test('compute the block string value', () {
      final token = Lexed('"""\n  a\n    b\n"""').tokens.single;
      expect(token.value, 'a\n  b');
      expect(token.end, 17);
    });

    test('unescape triple quotes only', () {
      expect(Lexed(r'"""a \""" \n b"""').tokens.single.value, r'a """ \n b');
    });

    test('report an unterminated block string at the end', () {
      expect(Lexed('"""').errors, ['1:4 GQL004 Unterminated string.']);
      expect(Lexed('""""').errors, ['1:5 GQL004 Unterminated string.']);
    });

    test('reject a lone surrogate and skip to the closing quotes', () {
      final lexed = Lexed('"""a\uD800b""" c');
      expect(lexed.errors, [
        '1:5 GQL002 Invalid character within String: U+D800.',
      ]);
      expect(lexed.described, ['error 0:9', 'name 10:11 c']);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/lexer_test.dart test/language/lexer/string_test.dart)
```

Expected: FAIL. `lexer_test.dart` does not compile (`No named parameter with the name 'maxTokens'`), and `string_test.dart` fails with `Expected: ['1:7 GQL004 Unterminated string.']`.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -36,5 +36,17 @@ enum DiagnosticCode(
 
   /// `GQL003`: a malformed number, such as `007`, `1.`, `.5`, `1e` or a
   /// name glued to a number (`1a`).
-  invalidNumber('GQL003');
+  invalidNumber('GQL003'),
+
+  /// `GQL004`: a string or block string without its closing quotes; a
+  /// quoted string also ends at a line break.
+  unterminatedString('GQL004'),
+
+  /// `GQL005`: an escape sequence that is not `\"`, `\\`, `\/`, `\b`,
+  /// `\f`, `\n`, `\r`, `\t` or a Unicode escape of a scalar value.
+  invalidEscapeSequence('GQL005'),
+
+  /// `GQL006`: a document with more tokens than the limit; the rest is not
+  /// read.
+  tokenLimitExceeded('GQL006');
 }
```

Create `packages/typed_graphql/lib/src/language/lexer/block_string_scanner.dart`:

```dart
import 'block_string.dart';
import 'source_reader.dart';
import 'token.dart';

/// Scans a block string, `"""..."""` (spec §2.9.4), and computes its
/// value with [BlockString].
final class BlockStringScanner {
  /// Creates a scanner of the text of [reader].
  BlockStringScanner(this.reader);

  /// The text and the sink.
  final SourceReader reader;

  static const BlockString _blockString = BlockString();

  /// The block string that starts with the `"""` at [start], or an error
  /// token over it after one diagnostic.
  Token scan(int start) {
    final raw = StringBuffer();
    var chunk = start + 3;
    var position = start + 3;
    while (!_isTripleQuoteAt(position)) {
      if (reader.unitAt(position) == 0x5c && _isTripleQuoteAt(position + 1)) {
        raw.write(reader.slice(chunk, position));
        chunk = position + 1;
        position += 4;
        continue;
      }
      final width = reader.characterWidthAt(position);
      if (width == 0) {
        return _failAt(start, position);
      }
      position += width;
    }
    raw.write(reader.slice(chunk, position));
    final value = _blockString.valueOf('$raw');
    return Token(.blockString, start, position + 3, value: value);
  }

  bool _isTripleQuoteAt(int offset) =>
      reader.unitAt(offset) == 0x22 &&
      reader.unitAt(offset + 1) == 0x22 &&
      reader.unitAt(offset + 2) == 0x22;

  /// Reports a lone surrogate, or the end when [position] is there, and
  /// returns an error token up to the closing quotes.
  Token _failAt(int start, int position) {
    if (reader.unitAt(position) < 0) {
      const message = 'Unterminated string.';
      reader.report(.unterminatedString, message, position, position);
      return Token(.error, start, position);
    }
    final character = reader.describe(position);
    reader.report(
      .invalidCharacter,
      'Invalid character within String: $character.',
      position,
      position + 1,
    );
    var end = position + 1;
    while (end < reader.length && !_isTripleQuoteAt(end)) {
      end += reader.unitAt(end) == 0x5c && _isTripleQuoteAt(end + 1) ? 4 : 1;
    }
    return Token(.error, start, end < reader.length ? end + 3 : end);
  }
}
```

Create `packages/typed_graphql/lib/src/language/lexer/escape_reader.dart`:

```dart
import 'character_class.dart';
import 'source_reader.dart';

/// Reads one escape sequence of a quoted string (spec §2.9.4,
/// `EscapedCharacter` and `EscapedUnicode`).
final class EscapeReader {
  /// Creates a reader of the text of [reader].
  EscapeReader(this.reader);

  /// The text.
  final SourceReader reader;

  static const CharacterClass _classes = CharacterClass();
  static const int _backslash = 0x5c;
  static const int _u = 0x75;

  /// The escape at [position], a backslash: its decoded `value` and the
  /// code units it spans; `value` is null when it is invalid, and `size`
  /// then covers the text graphql-js quotes in its message.
  ({String? value, int size}) read(int position) {
    if (reader.unitAt(position + 1) != _u) {
      return (value: _character(reader.unitAt(position + 1)), size: 2);
    }
    return reader.unitAt(position + 2) == 0x7b
        ? _variableWidth(position)
        : _fixedWidth(position);
  }

  String? _character(int unit) => switch (unit) {
    0x22 => '"',
    0x5c => r'\',
    0x2f => '/',
    0x62 => '\b',
    0x66 => '\f',
    0x6e => '\n',
    0x72 => '\r',
    0x74 => '\t',
    _ => null,
  };

  /// `\u{...}`: at most eight digits, a scalar value. The loop and the
  /// overflow test mirror graphql-js so messages quote the same text.
  ({String? value, int size}) _variableWidth(int position) {
    var point = 0;
    var size = 3;
    while (size < 12) {
      final unit = reader.unitAt(position + size);
      size++;
      if (unit == 0x7d) {
        return size < 5 || !_classes.isScalarValue(point)
            ? (value: null, size: size)
            : (value: String.fromCharCode(point), size: size);
      }
      final digit = _classes.hexValue(unit);
      point = point * 16 + digit;
      if (digit < 0 || point >= 0x80000000) {
        break;
      }
    }
    return (value: null, size: size);
  }

  /// `\uXXXX`, where a leading surrogate must be followed by an escaped
  /// trailing one.
  ({String? value, int size}) _fixedWidth(int position) {
    final code = _hex4(position + 2);
    if (_classes.isScalarValue(code)) {
      return (value: String.fromCharCode(code), size: 6);
    }
    final hasPair =
        _classes.isLeadingSurrogate(code) &&
        reader.unitAt(position + 6) == _backslash &&
        reader.unitAt(position + 7) == _u &&
        _classes.isTrailingSurrogate(_hex4(position + 8));
    return hasPair
        ? (value: String.fromCharCodes([code, _hex4(position + 8)]), size: 12)
        : (value: null, size: 6);
  }

  /// The four hexadecimal digits at [offset], or -1 when one is not.
  int _hex4(int offset) {
    var code = 0;
    for (var i = 0; i < 4; i++) {
      final digit = _classes.hexValue(reader.unitAt(offset + i));
      if (digit < 0) {
        return -1;
      }
      code = code * 16 + digit;
    }
    return code;
  }
}
```

Replace `packages/typed_graphql/lib/src/language/lexer/lexer.dart` whole with:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import 'block_string_scanner.dart';
import 'character_class.dart';
import 'number_scanner.dart';
import 'source_reader.dart';
import 'string_scanner.dart';
import 'token.dart';
import 'token_kind.dart';

/// Turns a [Source] into tokens, one per [advance] (spec §2.1).
///
/// The lexer never throws (R1.2): text that is no token becomes one
/// [TokenKind.error] token over the offending run and one diagnostic in
/// the sink, and scanning resumes after it. Ignored tokens are skipped;
/// comments are returned only when [keepComments] is set.
///
/// With [maxTokens], the token after the limit is replaced by one
/// [DiagnosticCode.tokenLimitExceeded] error, [isLimitReached] becomes
/// true and every later call returns [TokenKind.eof] (R1.6).
final class Lexer {
  /// Creates a lexer of [source] that reports into [sink].
  Lexer(
    Source source,
    DiagnosticSink sink, {
    bool keepComments = false,
    int? maxTokens,
  }) : this._(
         SourceReader(source, sink),
         keepComments: keepComments,
         maxTokens: maxTokens,
       );

  Lexer._(
    SourceReader reader, {
    required this.keepComments,
    required this.maxTokens,
  }) : _reader = reader,
       _numbers = NumberScanner(reader),
       _strings = StringScanner(reader),
       _blockStrings = BlockStringScanner(reader);

  /// Whether [advance] returns [TokenKind.comment] tokens.
  final bool keepComments;

  /// The most tokens [advance] returns, comments and the end not counted;
  /// null for no limit.
  final int? maxTokens;

  final SourceReader _reader;
  final NumberScanner _numbers;
  final StringScanner _strings;
  final BlockStringScanner _blockStrings;
  int _position = 0;
  int _tokenCount = 0;
  bool _isLimitReached = false;

  /// The tokens returned so far, comments and the end not counted.
  int get tokenCount => _tokenCount;

  /// Whether [maxTokens] was exceeded, so the document was not read to
  /// its end.
  bool get isLimitReached => _isLimitReached;

  static const CharacterClass _classes = CharacterClass();

  static const Map<int, TokenKind> _punctuators = {
    0x21: .bang,
    0x24: .dollar,
    0x26: .ampersand,
    0x28: .parenLeft,
    0x29: .parenRight,
    0x3a: .colon,
    0x3d: .equals,
    0x40: .at,
    0x5b: .bracketLeft,
    0x5d: .bracketRight,
    0x7b: .braceLeft,
    0x7c: .pipe,
    0x7d: .braceRight,
  };

  /// The next token; [TokenKind.eof] at the end, and again on every later
  /// call.
  Token advance() {
    if (_isLimitReached) {
      return Token(.eof, _position, _position);
    }
    var token = _scanFrom(_position);
    while (token.kind == .comment && !keepComments) {
      token = _scanFrom(token.end);
    }
    return _counted(token);
  }

  Token _counted(Token token) {
    if (token.kind == .eof || token.kind == .comment) {
      return token;
    }
    _tokenCount++;
    final limit = maxTokens;
    if (limit == null || _tokenCount <= limit) {
      return token;
    }
    _isLimitReached = true;
    _position = token.start;
    _reader.report(
      .tokenLimitExceeded,
      'Document contains more than $limit tokens. Parsing aborted.',
      token.start,
      token.end,
    );
    return Token(.eof, token.start, token.start);
  }

  Token _scanFrom(int offset) {
    final token = _scan(_skipIgnored(offset));
    _position = token.end;
    return token;
  }

  /// The offset of the first character from [offset] on that is not
  /// white space, a line terminator, a comma or a byte order mark.
  int _skipIgnored(int offset) {
    var position = offset;
    while (_isIgnored(_reader.unitAt(position))) {
      position++;
    }
    return position;
  }

  static bool _isIgnored(int unit) => switch (unit) {
    0xfeff || 0x09 || 0x20 || 0x2c || 0x0a || 0x0d => true,
    _ => false,
  };

  Token _scan(int at) {
    final unit = _reader.unitAt(at);
    if (_punctuators[unit] case final kind?) {
      return Token(kind, at, at + 1);
    }
    return switch (unit) {
      -1 => Token(.eof, at, at),
      0x23 => _comment(at),
      0x2e => _dot(at),
      0x22 when _reader.slice(at, at + 3) == '"""' => _blockStrings.scan(at),
      0x22 => _strings.scan(at),
      _ when _classes.isDigit(unit) || unit == 0x2d => _numbers.scan(at),
      _ when _classes.isNameStart(unit) => _name(at),
      _ => _unexpected(at),
    };
  }

  Token _name(int start) {
    var end = start + 1;
    while (_classes.isNameContinue(_reader.unitAt(end))) {
      end++;
    }
    return Token(.name, start, end, value: _reader.slice(start, end));
  }

  /// A comment runs to a line terminator or to a character that is not
  /// a source character, which the next token reports.
  Token _comment(int start) {
    var end = start + 1;
    while (_reader.unitAt(end) != 0x0a && _reader.unitAt(end) != 0x0d) {
      final width = _reader.characterWidthAt(end);
      if (width == 0) {
        break;
      }
      end += width;
    }
    return Token(.comment, start, end, value: _reader.slice(start + 1, end));
  }

  Token _dot(int at) {
    if (_reader.unitAt(at + 1) != 0x2e) {
      return _classes.isDigit(_reader.unitAt(at + 1))
          ? _leadingDot(at)
          : _unexpected(at);
    }
    if (_reader.unitAt(at + 2) == 0x2e) {
      return Token(.spread, at, at + 3);
    }
    const message = 'Unexpected "..", did you mean "..."?';
    _reader.report(.unexpectedCharacter, message, at, at + 2);
    return Token(.error, at, at + 2);
  }

  /// `.5`: a number without its integer part.
  Token _leadingDot(int at) {
    var end = at + 1;
    while (_classes.isDigit(_reader.unitAt(end))) {
      end++;
    }
    final digits = _reader.slice(at + 1, end);
    _reader.report(
      .invalidNumber,
      'Invalid number, expected digit before ".", did you mean "0.$digits"?',
      at,
      end,
    );
    return Token(.error, at, end);
  }

  Token _unexpected(int at) {
    final width = _reader.characterWidthAt(at);
    final character = _reader.describe(at);
    final end = at + (width == 0 ? 1 : width);
    if (_reader.unitAt(at) == 0x27) {
      const message =
          'Unexpected single quote character (\'), did you mean to use a '
          'double quote (")?';
      _reader.report(.unexpectedCharacter, message, at, end);
    } else if (width == 0) {
      final message = 'Invalid character: $character.';
      _reader.report(.invalidCharacter, message, at, end);
    } else {
      final message = 'Unexpected character: $character.';
      _reader.report(.unexpectedCharacter, message, at, end);
    }
    return Token(.error, at, end);
  }
}
```

Create `packages/typed_graphql/lib/src/language/lexer/string_scanner.dart`:

```dart
import 'escape_reader.dart';
import 'source_reader.dart';
import 'token.dart';

/// Scans a quoted `StringValue` (spec §2.9.4) and decodes its escapes.
final class StringScanner {
  /// Creates a scanner of the text of [reader].
  StringScanner(this.reader) : _escapes = EscapeReader(reader);

  /// The text and the sink.
  final SourceReader reader;

  final EscapeReader _escapes;

  static const int _quote = 0x22;
  static const int _backslash = 0x5c;

  /// The string that starts with the quote at [start], or an error token
  /// over the string after one diagnostic.
  Token scan(int start) {
    final value = StringBuffer();
    var chunk = start + 1;
    var position = start + 1;
    while (true) {
      switch (reader.unitAt(position)) {
        case _quote:
          value.write(reader.slice(chunk, position));
          return Token(.string, start, position + 1, value: '$value');
        case _backslash:
          value.write(reader.slice(chunk, position));
          final escape = _escapes.read(position);
          final decoded = escape.value;
          if (decoded == null) {
            return _invalidEscape(start, position, escape.size);
          }
          value.write(decoded);
          position += escape.size;
          chunk = position;
        case final unit when _isLineEnd(unit):
          final end = position + (unit < 0 ? 0 : 1);
          const message = 'Unterminated string.';
          reader.report(.unterminatedString, message, position, end);
          return Token(.error, start, position);
        default:
          final width = reader.characterWidthAt(position);
          if (width == 0) {
            return _invalidCharacter(start, position);
          }
          position += width;
      }
    }
  }

  Token _invalidEscape(int start, int position, int size) {
    final text = reader.slice(position, position + size);
    final kind = reader.unitAt(position + 1) == 0x75 ? 'Unicode' : 'character';
    reader.report(
      .invalidEscapeSequence,
      'Invalid $kind escape sequence: "$text".',
      position,
      position + text.length,
    );
    return _skipRest(start, position + 1);
  }

  Token _invalidCharacter(int start, int position) {
    final character = reader.describe(position);
    reader.report(
      .invalidCharacter,
      'Invalid character within String: $character.',
      position,
      position + 1,
    );
    return _skipRest(start, position + 1);
  }

  /// An error token from [start] to the closing quote or the end of the
  /// line, without a second diagnostic.
  Token _skipRest(int start, int position) {
    var end = position;
    while (true) {
      switch (reader.unitAt(end)) {
        case _quote:
          return Token(.error, start, end + 1);
        case final unit when _isLineEnd(unit):
          return Token(.error, start, end);
        case _backslash:
          end += _isLineEnd(reader.unitAt(end + 1)) ? 1 : 2;
        default:
          end++;
      }
    }
  }

  static bool _isLineEnd(int unit) => unit < 0 || unit == 0x0a || unit == 0x0d;
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/lexer_test.dart test/language/lexer/string_test.dart)
```

Expected: `lexer_test.dart` `+19`, `string_test.dart` `+11`, each `All tests passed!`

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -95,7 +95,7 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `BlockStringValue` and graphql-js's printing rules; lexer and printer share
   it. `Lexer(source, sink).advance()` never throws: bad text becomes one
   `error` token over the run and one diagnostic, with graphql-js's message
-  minus "Syntax Error: ". Scanners (`*_scanner.dart`) share a
+  minus "Syntax Error: ". `maxTokens` is counted here (R1.6). Scanners (`*_scanner.dart`) share a
   `SourceReader` (text, `describe`, `report`); `CharacterClass` holds the
   character tests.
 
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/language/lexer/block_string_scanner.dart packages/typed_graphql/lib/src/language/lexer/escape_reader.dart packages/typed_graphql/lib/src/language/lexer/lexer.dart packages/typed_graphql/lib/src/language/lexer/string_scanner.dart packages/typed_graphql/test/language/lexer/lexer_test.dart packages/typed_graphql/test/language/lexer/string_test.dart
git commit -q -m "feat(typed_graphql): lex strings, block strings and the token limit"
```

### Task 8: Parse values and type references

The first public parser entry points. `TokenCursor` ports graphql-js's `expectToken`, `expectOptionalToken`, `expectKeyword`, `many`, `optionalMany`, `any` and `delimitedMany`, and adds `nested` for `maxDepth`.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/parser/parse_element_result.dart`, `packages/typed_graphql/lib/src/language/parser/parser.dart`, `packages/typed_graphql/lib/src/language/parser/parser_options.dart`, `packages/typed_graphql/lib/src/language/parser/syntax_abort.dart`, `packages/typed_graphql/lib/src/language/parser/token_cursor.dart`, `packages/typed_graphql/lib/src/language/parser/value_parser.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/language/lexer/lexer.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/parser/parse_value_test.dart`

**Interfaces:**
- Consumes: Tasks 2–7: the nodes, `Lexer` (`maxTokens`, `isLimitReached`, `source`), `DiagnosticSink`.
- Produces:
  - `final class const ParserOptions({int? maxTokens = 15000, int? maxDepth = 128, bool allowDirectiveExtensions = false, bool allowEmptySelectionSets = false})`;
  - `final class Parser` (`const Parser({ParserOptions options = const ParserOptions()})`):
    - `ParseElementResult<Value> parseValue(Source source, {bool isConst = false})`;
    - `ParseElementResult<TypeRef> parseTypeRef(Source source)`.
  - `sealed class ParseElementResult<T extends Node>(List<Diagnostic> diagnostics)` = `ParseElementSuccess<T>(T value, diagnostics)` | `ParseElementFailure<T>(diagnostics)`.
  - Internal:
    - `TokenCursor(Lexer lexer, DiagnosticSink sink, {int? maxDepth})`, with `token`, `lookahead()`, `advance()`, `peek`, `peekKeyword`, `expect`, `expectOptional`, `expectKeyword`, `expectOptionalKeyword`, `name()`, `many`, `optionalMany`, `any`, `delimitedMany`, `unexpected([Token?])`, `fail(code, message, {...})`, `nested(parse)`, `balance`, `lastEnd` and `isStopped`;
    - `SyntaxAbort({bool endsDefinition = false})`;
    - `ValueParser(cursor)`, with `value({required bool isConst})`, `variable()`, `string()`, `description()`, `typeRef()`, `namedType()` and `operationType()`.
  - New codes: `GQL007 expectedToken`, `GQL008 unexpectedToken`, `GQL009 variableInConstant`, `GQL010 depthLimitExceeded`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/parser/parse_value_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  Value valueOf(String text) => switch (parser.parseValue(Source(text))) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };

  List<String> errorsOf(ParseElementResult<Node> result) => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];

  group('parseValue', () {
    test('parses every scalar kind with its offsets', () {
      final value = valueOf(r'[1, -2.5e3, "s", """b""", true, null, RED, $v]');
      final items = (value as ListValue).values;
      expect(items.map((item) => item.runtimeType), [
        IntValue,
        FloatValue,
        StringValue,
        StringValue,
        BooleanValue,
        NullValue,
        EnumValue,
        Variable,
      ]);
      expect((items[1] as FloatValue).value, '-2.5e3');
      expect((items[3] as StringValue).isBlock, isTrue);
      expect([items[1].start, items[1].end], [4, 10]);
      expect([items[7].start, items[7].end], [43, 45]);
    });

    test('parses objects with nested lists', () {
      final expected = ObjectValue([
        ObjectField(
          const Name('a'),
          ListValue([
            const IntValue('1'),
            ObjectValue(const [ObjectField(Name('b'), IntValue('2'))]),
          ]),
        ),
        const ObjectField(Name('c'), StringValue('x')),
      ]);
      final value = valueOf('{a: [1, {b: 2}], c: "x"}');
      expect(value.isEquivalentTo(expected), isTrue);
      expect([value.start, value.end], [0, 24]);
    });

    test('rejects a variable in a constant value at the dollar sign', () {
      final result = parser.parseValue(Source(r'[1, $var]'), isConst: true);
      expect(errorsOf(result), [
        r'1:5 GQL009 Unexpected variable "$var" in constant value.',
      ]);
      final bare = parser.parseValue(Source(r'$'), isConst: true);
      expect(errorsOf(bare), [r'1:1 GQL008 Unexpected "$".']);
    });

    test('reports an unexpected and a missing token', () {
      expect(errorsOf(parser.parseValue(Source(')'))), [
        '1:1 GQL008 Unexpected ")".',
      ]);
      expect(errorsOf(parser.parseValue(Source('{a 1}'))), [
        '1:4 GQL007 Expected ":", found Int "1".',
      ]);
      expect(errorsOf(parser.parseValue(Source('1 x'))), [
        '1:3 GQL007 Expected <EOF>, found Name "x".',
      ]);
    });

    test('adds nothing to a lexer error', () {
      expect(errorsOf(parser.parseValue(Source('[1, ~]'))), [
        '1:5 GQL001 Unexpected character: "~".',
      ]);
    });
  });

  group('parseTypeRef', () {
    test('wraps list and non-null types', () {
      final result = parser.parseTypeRef(Source('[String!]!'));
      final type = (result as ParseElementSuccess<TypeRef>).value;
      const expected = NonNullType(
        ListType(NonNullType(NamedType(Name('String')))),
      );
      expect(type.isEquivalentTo(expected), isTrue);
      expect([type.start, type.end], [0, 10]);
    });

    test('reports a missing bracket', () {
      expect(errorsOf(parser.parseTypeRef(Source('[[A]'))), [
        '1:5 GQL007 Expected "]", found <EOF>.',
      ]);
    });
  });

  group('limits', () {
    const shallow = Parser(options: ParserOptions(maxDepth: 3));

    test('accepts nesting up to maxDepth', () {
      expect(
        shallow.parseValue(Source('[[{a: 1}]]')),
        isA<ParseElementSuccess<Value>>(),
      );
      expect(
        shallow.parseTypeRef(Source('[[[A]]]')),
        isA<ParseElementSuccess<TypeRef>>(),
      );
    });

    test('reports one error at the level past maxDepth', () {
      expect(errorsOf(shallow.parseValue(Source('[[[[1]]]]'))), [
        '1:4 GQL010 Document nests deeper than 3 levels.',
      ]);
      expect(errorsOf(shallow.parseTypeRef(Source('[[[[A]]]]'))), [
        '1:4 GQL010 Document nests deeper than 3 levels.',
      ]);
    });

    test('stops at maxTokens with one error', () {
      const short = Parser(options: ParserOptions(maxTokens: 2));
      expect(errorsOf(short.parseValue(Source('[1, 2]'))), [
        '1:5 GQL006 Document contains more than 2 tokens. Parsing aborted.',
      ]);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_value_test.dart)
```

Expected: FAIL to compile: `Method not found: 'Parser'`.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -48,5 +48,21 @@ enum DiagnosticCode(
 
   /// `GQL006`: a document with more tokens than the limit; the rest is not
   /// read.
-  tokenLimitExceeded('GQL006');
+  tokenLimitExceeded('GQL006'),
+
+  /// `GQL007`: the parser needed a certain token, such as `:` or a name,
+  /// and found another.
+  expectedToken('GQL007'),
+
+  /// `GQL008`: a token that cannot appear where it is, such as `)` at the
+  /// start of a value or an unknown definition keyword.
+  unexpectedToken('GQL008'),
+
+  /// `GQL009`: a variable inside a constant value, such as a default value
+  /// or an argument of a type-system directive.
+  variableInConstant('GQL009'),
+
+  /// `GQL010`: selection sets, lists, objects and list types nested deeper
+  /// than the parser's `maxDepth`; the definition is dropped.
+  depthLimitExceeded('GQL010');
 }
```

In `packages/typed_graphql/lib/src/language/lexer/lexer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -56,6 +56,9 @@ final class Lexer {
   int _tokenCount = 0;
   bool _isLimitReached = false;
 
+  /// The document being read.
+  Source get source => _reader.source;
+
   /// The tokens returned so far, comments and the end not counted.
   int get tokenCount => _tokenCount;
 
```

Create `packages/typed_graphql/lib/src/language/parser/parse_element_result.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../ast/node.dart';

/// The result of parsing one value or type reference:
/// [ParseElementSuccess] or [ParseElementFailure], with [diagnostics].
sealed class ParseElementResult<T extends Node>(List<Diagnostic> diagnostics) {
  /// Creates a result.
  this;

  /// Every diagnostic of the parse, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}

/// An element without syntax errors.
final class ParseElementSuccess<T extends Node>(
  /// The element.
  final T value,
  super.diagnostics,
) extends ParseElementResult<T> {
  /// Creates a success.
  this;
}

/// An element with syntax errors; there is no partial element.
final class ParseElementFailure<T extends Node>(super.diagnostics)
    extends ParseElementResult<T> {
  /// Creates a failure.
  this;
}
```

Create `packages/typed_graphql/lib/src/language/parser/parser.dart`:

```dart
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../ast/node.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/lexer.dart';
import 'parse_element_result.dart';
import 'parser_options.dart';
import 'syntax_abort.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses GraphQL documents and single elements; it never throws on bad
/// input (R1.5): the result carries every diagnostic.
///
/// The grammar lives in collaborators, one per part of the language; this
/// class wires them to a [TokenCursor] and assembles results.
final class Parser {
  /// Creates a parser with [options].
  const Parser({this.options = const ParserOptions()});

  /// The limits and the working-draft grammar this parser accepts.
  final ParserOptions options;

  /// Parses [source] as one value, such as `[1, $a]`; with [isConst], a
  /// variable is an error.
  ParseElementResult<Value> parseValue(Source source, {bool isConst = false}) =>
      _element(source, (cursor) => ValueParser(cursor).value(isConst: isConst));

  /// Parses [source] as one type reference, such as `[String!]`.
  ParseElementResult<TypeRef> parseTypeRef(Source source) =>
      _element(source, (cursor) => ValueParser(cursor).typeRef());

  TokenCursor _cursor(Source source, DiagnosticSink sink) => TokenCursor(
    Lexer(source, sink, maxTokens: options.maxTokens),
    sink,
    maxDepth: options.maxDepth,
  );

  /// Parses [source] with [parse], which must read it to the end.
  ParseElementResult<T> _element<T extends Node>(
    Source source,
    T Function(TokenCursor cursor) parse,
  ) {
    final sink = DiagnosticSink();
    final cursor = _cursor(source, sink);
    try {
      final element = parse(cursor);
      cursor.expect(.eof);
      if (!sink.hasErrors) {
        return ParseElementSuccess(element, sink.diagnostics);
      }
    } on SyntaxAbort {
      // The error is in the sink; an element has no partial result.
    }
    return ParseElementFailure(sink.diagnostics);
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/parser_options.dart`:

```dart
import 'package:meta/meta.dart';

/// What a [Parser] accepts and how much: limits against abuse (R1.6) and
/// working-draft grammar (R0.1, R1.4).
@immutable
final class const ParserOptions({
  /// The most tokens a document may have; null for no limit.
  final int? maxTokens = 15000,

  /// The deepest nesting of selection sets, lists, objects and list types;
  /// null for no limit, which lets a hostile document exhaust the stack.
  final int? maxDepth = 128,

  /// Whether the working draft's directive extensions are accepted:
  /// `extend directive @name @directive`, directives on a directive
  /// definition and the `DIRECTIVE_DEFINITION` location.
  final bool allowDirectiveExtensions = false,

  /// Whether the working draft's empty selection set, `{ }`, is accepted.
  final bool allowEmptySelectionSets = false,
}) {
  /// Creates options; the defaults are the September2025 grammar.
  this;
}
```

Create `packages/typed_graphql/lib/src/language/parser/syntax_abort.dart`:

```dart
/// Unwinds the parser from a syntax error, already reported, to the
/// nearest recovery point: the selection or the definition being parsed.
///
/// It never leaves the parser (R0.3): `Parser` catches it and turns the
/// sink into a result.
final class SyntaxAbort implements Exception {
  /// Creates an abort; [endsDefinition] skips the selection recovery.
  const SyntaxAbort({this.endsDefinition = false});

  /// Whether the whole definition is dropped, as after a depth error.
  final bool endsDefinition;
}
```

Create `packages/typed_graphql/lib/src/language/parser/token_cursor.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source_span.dart';
import '../ast/name.dart';
import '../lexer/lexer.dart';
import '../lexer/token.dart';
import '../lexer/token_kind.dart';
import 'syntax_abort.dart';

/// The parser's view of the token stream: the current token, one token of
/// lookahead, the expectations of graphql-js's parser and the way a
/// syntax error is reported.
///
/// A failure reports one diagnostic and throws a [SyntaxAbort]. It stays
/// silent at an error token, which the lexer reported, at an offset that
/// already has a diagnostic, and once [isStopped].
final class TokenCursor {
  /// Creates a cursor over [lexer] that reports into [sink].
  TokenCursor(this.lexer, this.sink, {this.maxDepth})
    : _token = lexer.advance();

  /// The token source.
  final Lexer lexer;

  /// Where syntax errors go.
  final DiagnosticSink sink;

  /// The deepest [nested] call allowed; null for no limit.
  final int? maxDepth;

  Token _token;
  Token? _lookahead;
  int _lastEnd = 0;
  int _balance = 0;
  int _depth = 0;
  final Set<int> _reportedOffsets = {};

  /// The current token, not consumed yet.
  Token get token => _token;

  /// The end of the last consumed token: the end of the node being built.
  int get lastEnd => _lastEnd;

  /// Opening minus closing brackets, braces and parentheses consumed; the
  /// recovery uses it to stay at the level where the error happened.
  int get balance => _balance;

  /// Whether parsing must stop: the token limit or the sink's limit was
  /// reached.
  bool get isStopped => lexer.isLimitReached || sink.isFull;

  /// The token after [token], read without consuming [token].
  Token lookahead() => _lookahead ??= lexer.advance();

  /// Consumes [token].
  void advance() {
    _lastEnd = _token.end;
    _balance += switch (_token.kind) {
      .braceLeft || .bracketLeft || .parenLeft => 1,
      .braceRight || .bracketRight || .parenRight => -1,
      _ => 0,
    };
    _token = _lookahead ?? lexer.advance();
    _lookahead = null;
  }

  /// Whether [token] is of [kind].
  bool peek(TokenKind kind) => _token.kind == kind;

  /// Whether [token] is the name [word].
  bool peekKeyword(String word) => _token.kind == .name && _token.value == word;

  /// Consumes and returns [token] when it is of [kind]; fails otherwise.
  Token expect(TokenKind kind) {
    final token = _token;
    if (token.kind != kind) {
      final found = token.description;
      fail(.expectedToken, 'Expected ${kind.description}, found $found.');
    }
    advance();
    return token;
  }

  /// Consumes [token] when it is of [kind], and says whether it did.
  bool expectOptional(TokenKind kind) {
    if (_token.kind != kind) {
      return false;
    }
    advance();
    return true;
  }

  /// Consumes the keyword [word]; fails when [token] is another token.
  void expectKeyword(String word) {
    if (!expectOptionalKeyword(word)) {
      final found = _token.description;
      fail(.expectedToken, 'Expected "$word", found $found.');
    }
  }

  /// Consumes [token] when it is the keyword [word], and says whether it
  /// did.
  bool expectOptionalKeyword(String word) {
    if (!peekKeyword(word)) {
      return false;
    }
    advance();
    return true;
  }

  /// Consumes a name token and returns it as a [Name] node.
  Name name() {
    final token = _token;
    if (token case Token(kind: .name, :final value?)) {
      advance();
      return Name(value, start: token.start, end: token.end);
    }
    fail(.expectedToken, 'Expected Name, found ${token.description}.');
  }

  /// [open], one or more items, [close]: graphql-js's `many`.
  List<T> many<T>(TokenKind open, T Function() item, TokenKind close) {
    expect(open);
    final items = [item()];
    while (!expectOptional(close)) {
      items.add(item());
    }
    return items;
  }

  /// [many] when [token] is [open], or no items.
  List<T> optionalMany<T>(TokenKind open, T Function() item, TokenKind close) =>
      peek(open) ? many(open, item, close) : <T>[];

  /// [open], zero or more items, [close]: graphql-js's `any`.
  List<T> any<T>(TokenKind open, T Function() item, TokenKind close) {
    expect(open);
    final items = <T>[];
    while (!expectOptional(close)) {
      items.add(item());
    }
    return items;
  }

  /// One or more items separated by [delimiter], which may also lead.
  List<T> delimitedMany<T>(TokenKind delimiter, T Function() item) {
    expectOptional(delimiter);
    final items = [item()];
    while (expectOptional(delimiter)) {
      items.add(item());
    }
    return items;
  }

  /// Fails with `Unexpected <token>.` at [at], or at [token].
  Never unexpected([Token? at]) {
    final token = at ?? _token;
    fail(.unexpectedToken, 'Unexpected ${token.description}.', at: token);
  }

  /// Reports [message] with [code] at [at], or at [token], and throws a
  /// [SyntaxAbort].
  Never fail(
    DiagnosticCode code,
    String message, {
    Token? at,
    bool endsDefinition = false,
  }) {
    final token = at ?? _token;
    final isSilent = token.kind == .error || isStopped;
    if (!isSilent && _reportedOffsets.add(token.start)) {
      final span = SourceSpan(lexer.source, token.start, token.end);
      sink.report(Diagnostic(code, .error, message, span: span));
    }
    throw SyntaxAbort(endsDefinition: endsDefinition);
  }

  /// Runs [parse] one nesting level deeper; fails when that passes
  /// [maxDepth], dropping the whole definition (R1.6).
  T nested<T>(T Function() parse) {
    final limit = maxDepth;
    if (limit != null && _depth >= limit) {
      fail(
        .depthLimitExceeded,
        'Document nests deeper than $limit levels.',
        endsDefinition: true,
      );
    }
    _depth++;
    try {
      return parse();
    } finally {
      _depth--;
    }
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/value_parser.dart`:

```dart
import '../ast/object_field.dart';
import '../ast/operation_type.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/token.dart';
import 'token_cursor.dart';

/// Parses values, variables, type references, descriptions and operation
/// types: the productions every other part of the parser uses (spec
/// §2.9–§2.11).
final class ValueParser {
  /// Creates a parser reading from [cursor].
  ValueParser(this.cursor);

  /// The token stream.
  final TokenCursor cursor;

  /// `Value[?Const]`: with [isConst], a variable is an error.
  Value value({required bool isConst}) {
    final token = cursor.token;
    return switch ((token.kind, token.value)) {
      (.bracketLeft, _) => cursor.nested(() => _list(isConst: isConst)),
      (.braceLeft, _) => cursor.nested(() => _object(isConst: isConst)),
      (.int || .float || .name, _) => _scalar(token),
      (.string || .blockString, _) => string(),
      (.dollar, _) when isConst => _variableInConstant(),
      (.dollar, _) => variable(),
      _ => cursor.unexpected(),
    };
  }

  /// `Variable`: `$name`.
  Variable variable() {
    final start = cursor.token.start;
    cursor.expect(.dollar);
    final name = cursor.name();
    return Variable(name, start: start, end: cursor.lastEnd);
  }

  /// A string or block string.
  StringValue string() {
    final token = cursor.token;
    if (token case Token(kind: .string || .blockString, :final value?)) {
      cursor.advance();
      final isBlock = token.kind == .blockString;
      return StringValue(
        value,
        isBlock: isBlock,
        start: token.start,
        end: token.end,
      );
    }
    cursor.unexpected();
  }

  /// `Description`: a string before a definition, or null.
  StringValue? description() =>
      cursor.peek(.string) || cursor.peek(.blockString) ? string() : null;

  /// `Type`: a named, list or non-null type.
  TypeRef typeRef() {
    final start = cursor.token.start;
    final type = cursor.peek(.bracketLeft)
        ? cursor.nested(() => _listType(start))
        : namedType();
    return cursor.expectOptional(.bang)
        ? NonNullType(type, start: start, end: cursor.lastEnd)
        : type;
  }

  /// `NamedType`: a name.
  NamedType namedType() {
    final name = cursor.name();
    return NamedType(name, start: name.start, end: name.end);
  }

  /// `OperationType`: `query`, `mutation` or `subscription`.
  OperationType operationType() {
    final token = cursor.expect(.name);
    return switch (token.value) {
      'query' => .query,
      'mutation' => .mutation,
      'subscription' => .subscription,
      _ => cursor.unexpected(token),
    };
  }

  /// The number, boolean, null or enum value of [token], consumed.
  Value _scalar(Token token) {
    cursor.advance();
    final (start, end) = (token.start, token.end);
    return switch ((token.kind, token.value)) {
      (.int, final lexeme?) => IntValue(lexeme, start: start, end: end),
      (.float, final lexeme?) => FloatValue(lexeme, start: start, end: end),
      (.name, 'true') => BooleanValue(true, start: start, end: end),
      (.name, 'false') => BooleanValue(false, start: start, end: end),
      (.name, 'null') => NullValue(start: start, end: end),
      (.name, final name?) => EnumValue(name, start: start, end: end),
      _ => throw StateError('$token is not a scalar value token.'),
    };
  }

  /// `$name` where a constant is required: graphql-js names the variable
  /// in the message and points at the `$`.
  Never _variableInConstant() {
    final dollar = cursor.token;
    cursor.advance();
    if (cursor.token case Token(kind: .name, :final value?)) {
      cursor.fail(
        .variableInConstant,
        'Unexpected variable "\$$value" in constant value.',
        at: dollar,
      );
    }
    cursor.unexpected(dollar);
  }

  ListValue _list({required bool isConst}) {
    final start = cursor.token.start;
    final values = cursor.any(
      .bracketLeft,
      () => value(isConst: isConst),
      .bracketRight,
    );
    return ListValue(values, start: start, end: cursor.lastEnd);
  }

  ObjectValue _object({required bool isConst}) {
    final start = cursor.token.start;
    final fields = cursor.any(
      .braceLeft,
      () => _objectField(isConst: isConst),
      .braceRight,
    );
    return ObjectValue(fields, start: start, end: cursor.lastEnd);
  }

  ObjectField _objectField({required bool isConst}) {
    final start = cursor.token.start;
    final name = cursor.name();
    cursor.expect(.colon);
    final value = this.value(isConst: isConst);
    return ObjectField(name, value, start: start, end: cursor.lastEnd);
  }

  ListType _listType(int start) {
    cursor.expect(.bracketLeft);
    final type = typeRef();
    cursor.expect(.bracketRight);
    return ListType(type, start: start, end: cursor.lastEnd);
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_value_test.dart)
```

Expected: `+10: All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -98,6 +98,13 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   minus "Syntax Error: ". `maxTokens` is counted here (R1.6). Scanners (`*_scanner.dart`) share a
   `SourceReader` (text, `describe`, `report`); `CharacterClass` holds the
   character tests.
+- `parser/`: `Parser(options:)` is const and stateless; each call builds a
+  `TokenCursor` (current token, one lookahead, graphql-js's `expect*`,
+  `many`, `any`, `delimitedMany`, `nested` for `maxDepth`) and grammar
+  collaborators (`*_parser.dart`) over it. A syntax error is reported by
+  `TokenCursor.fail`, which throws the internal `SyntaxAbort`; it never
+  leaves `Parser`. The cursor is silent at error tokens (the lexer
+  reported them) and at an offset that already has a diagnostic.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/enum_value_definition.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/field_definition.dart';
export 'src/language/ast/input_value_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/operation_type_definition.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/type_system_definition.dart';
export 'src/language/ast/type_system_extension.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/language/lexer/block_string.dart';
export 'src/language/lexer/lexer.dart';
export 'src/language/lexer/token.dart';
export 'src/language/lexer/token_kind.dart';
export 'src/language/parser/parse_element_result.dart';
export 'src/language/parser/parser.dart';
export 'src/language/parser/parser_options.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/language/lexer/lexer.dart packages/typed_graphql/lib/src/language/parser/parse_element_result.dart packages/typed_graphql/lib/src/language/parser/parser.dart packages/typed_graphql/lib/src/language/parser/parser_options.dart packages/typed_graphql/lib/src/language/parser/syntax_abort.dart packages/typed_graphql/lib/src/language/parser/token_cursor.dart packages/typed_graphql/lib/src/language/parser/value_parser.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/parser/parse_value_test.dart
git commit -q -m "feat(typed_graphql): parse values and type references"
```

### Task 9: Executable documents and error recovery

`Parser.parse` and the recovery policy (R1.5). `token_cursor_test.dart` pins the cursor from Task 8 and passes on its own; the two other test files fail first.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/parser/definition_parser.dart`, `packages/typed_graphql/lib/src/language/parser/directive_parser.dart`, `packages/typed_graphql/lib/src/language/parser/executable_parser.dart`, `packages/typed_graphql/lib/src/language/parser/graphql_syntax_exception.dart`, `packages/typed_graphql/lib/src/language/parser/parse_result.dart`, `packages/typed_graphql/lib/src/language/parser/recovery.dart`, `packages/typed_graphql/lib/src/language/parser/selection_parser.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/language/parser/parser.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/parser/parse_executable_test.dart`, `packages/typed_graphql/test/language/parser/parsed.dart`, `packages/typed_graphql/test/language/parser/recovery_test.dart`, `packages/typed_graphql/test/language/parser/token_cursor_test.dart`

**Interfaces:**
- Consumes: Task 8: `Parser`, `TokenCursor`, `SyntaxAbort`, `ValueParser`; Task 3: the executable nodes.
- Produces:
  - `ParseResult Parser.parse(Source source)`;
  - `sealed class ParseResult(List<Diagnostic> diagnostics)`, with `Document requireDocument()`:
    - `ParseSuccess(Document document, diagnostics)`;
    - `ParseFailure(Document partial, diagnostics)`: everything that parsed completely.
  - `final class GraphQLSyntaxException implements Exception`, with `diagnostics`; `requireDocument` throws it.
  - Internal `DefinitionParser`, `DirectiveParser`, `ExecutableParser`, `SelectionParser` and `Recovery` (`skipDefinition`, `skipSelection`).
  - New codes: `GQL011 misplacedDescription`, `GQL012 emptySelectionSet`.
  - Test helper `Parsed(text, {options})`, with `result`, `document`, `partial` and `errors`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/parser/parse_executable_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  group('operations', () {
    test('a shorthand query is an anonymous query', () {
      final operation = Parsed('{ a }').single<OperationDefinition>();
      expect(operation.operation, OperationType.query);
      expect(operation.name, isNull);
      expect([operation.start, operation.end], [0, 5]);
    });

    test('parses every operation type, named or not', () {
      final document = Parsed(
        'query { a } mutation M { b } subscription S { c }',
      ).document;
      final operations = document.definitions.cast<OperationDefinition>();
      expect(operations.map((operation) => operation.operation), [
        OperationType.query,
        OperationType.mutation,
        OperationType.subscription,
      ]);
      expect(operations.map((operation) => operation.name?.value), [
        null,
        'M',
        'S',
      ]);
    });

    test('parses descriptions, variables, defaults and directives', () {
      final operation = Parsed(
        r'"Op" query Q("V" $v: [Int!] = [1] @d, $w: String) @e { a }',
      ).single<OperationDefinition>();
      expect(operation.description?.value, 'Op');
      final variables = operation.variableDefinitions;
      expect(variables.map((variable) => variable.variable.name.value), [
        'v',
        'w',
      ]);
      expect(variables.first.description?.value, 'V');
      expect(variables.first.defaultValue, isA<ListValue>());
      expect(variables.first.directives.single.name.value, 'd');
      expect(operation.directives.single.name.value, 'e');
    });

    test('a variable default value is constant', () {
      expect(Parsed(r'query ($a: Int = $b) { a }').errors, [
        r'1:18 GQL009 Unexpected variable "$b" in constant value.',
      ]);
    });
  });

  group('selections', () {
    test('parses aliases, arguments, directives and nested sets', () {
      final operation = Parsed(
        r'{ x: a(b: $c, d: {e: 1}) @f(g: true) { h } }',
      ).single<OperationDefinition>();
      final field = operation.selectionSet.selections.single as Field;
      expect(field.alias?.value, 'x');
      expect(field.name.value, 'a');
      expect(field.arguments.map((argument) => argument.name.value), [
        'b',
        'd',
      ]);
      expect(
        field.directives.single.arguments.single.value,
        isA<BooleanValue>(),
      );
      expect(field.selectionSet?.selections.single, isA<Field>());
      expect([field.start, field.end], [2, 42]);
    });

    test('parses fragment spreads and inline fragments', () {
      final operation = Parsed(
        '{ ...F @d ... on T { a } ... @e { b } }',
      ).single<OperationDefinition>();
      final selections = operation.selectionSet.selections;
      expect((selections[0] as FragmentSpread).name.value, 'F');
      expect((selections[1] as InlineFragment).typeCondition?.name.value, 'T');
      expect((selections[2] as InlineFragment).typeCondition, isNull);
      expect((selections[2] as InlineFragment).directives, hasLength(1));
    });

    test('rejects an empty selection set unless allowed', () {
      expect(Parsed('{ }').errors, [
        '1:3 GQL012 Unexpected empty selection set.',
      ]);
      const options = ParserOptions(allowEmptySelectionSets: true);
      final operation = Parsed(
        '{ a { } }',
        options: options,
      ).single<OperationDefinition>();
      final field = operation.selectionSet.selections.single as Field;
      expect(field.selectionSet?.selections, isEmpty);
    });
  });

  group('fragments', () {
    test('parses a described fragment definition', () {
      final fragment = Parsed(
        '"F" fragment F on T @d { a }',
      ).single<FragmentDefinition>();
      expect(fragment.description?.value, 'F');
      expect(fragment.typeCondition.name.value, 'T');
      expect(fragment.directives.single.name.value, 'd');
    });

    test('rejects a fragment named on and a missing type condition', () {
      expect(Parsed('fragment on on T { a }').errors, [
        '1:10 GQL008 Unexpected Name "on".',
      ]);
      expect(Parsed('{ ...MissingOn }\nfragment MissingOn Type').errors, [
        '2:20 GQL007 Expected "on", found Name "Type".',
      ]);
    });
  });

  group('document', () {
    test('an empty document is an error', () {
      expect(Parsed('').errors, ['1:1 GQL008 Unexpected <EOF>.']);
    });

    test('reports misplaced descriptions', () {
      expect(Parsed('"d" { a }').errors, [
        '1:1 GQL011 Unexpected description, descriptions are not supported '
            'on shorthand queries.',
      ]);
      expect(Parsed('"d" foo').errors, [
        '1:1 GQL011 Unexpected description, only GraphQL definitions '
            'support descriptions.',
      ]);
    });

    test('the document spans the whole source', () {
      final document = Parsed(' { a } ').document;
      expect([document.start, document.end], [0, 7]);
    });

    test('requireDocument throws with every diagnostic on failure', () {
      final result = Parsed('{').result;
      expect(
        result.requireDocument,
        throwsA(
          isA<GraphQLSyntaxException>().having(
            (exception) => exception.diagnostics,
            'diagnostics',
            result.diagnostics,
          ),
        ),
      );
      expect(Parsed('{ a }').result.requireDocument(), isA<Document>());
    });
  });
}
```

Create `packages/typed_graphql/test/language/parser/parsed.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// The result of parsing one text, for tests.
final class Parsed {
  /// Parses [text] with [options].
  Parsed(String text, {ParserOptions options = const ParserOptions()})
    : result = Parser(options: options).parse(Source(text));

  /// The parse result.
  final ParseResult result;

  /// The document, which the test expects to have no errors.
  Document get document => switch (result) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// The partial document, which the test expects to have errors.
  Document get partial => switch (result) {
    ParseSuccess() => fail('expected syntax errors'),
    ParseFailure(:final partial) => partial,
  };

  /// Each diagnostic as `line:column id message`.
  List<String> get errors => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];

  /// The only definition of [document].
  T single<T extends Definition>() => document.definitions.single as T;
}
```

Create `packages/typed_graphql/test/language/parser/recovery_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  List<String> fieldNames(Document document) => [
    for (final definition in document.definitions.cast<OperationDefinition>())
      for (final selection in definition.selectionSet.selections)
        (selection as Field).name.value,
  ];

  group('definitions', () {
    test('reports every broken definition and keeps the others', () {
      final parsed = Parsed('query { a(x: ) } query B { b } { c: } { d }');
      expect(parsed.errors, [
        '1:14 GQL008 Unexpected ")".',
        '1:37 GQL007 Expected Name, found "}".',
      ]);
      expect(fieldNames(parsed.partial), ['b', 'd']);
    });

    test('resumes at a keyword or a description at the top level', () {
      final parsed = Parsed('notAnOperation Foo "d" query { a }');
      expect(parsed.errors, ['1:1 GQL008 Unexpected Name "notAnOperation".']);
      expect(fieldNames(parsed.partial), ['a']);
    });

    test('an unterminated definition gives one error', () {
      expect(Parsed(r'query Q($a: Int').errors, [
        r'1:16 GQL007 Expected "$", found <EOF>.',
      ]);
    });
  });

  group('selections', () {
    test('drops a failed selection and keeps the rest', () {
      final parsed = Parsed('{ a(x: ) b c(y: {z: }) d }');
      expect(parsed.errors, [
        '1:8 GQL008 Unexpected ")".',
        '1:21 GQL008 Unexpected "}".',
      ]);
      expect(fieldNames(parsed.partial), ['b', 'd']);
    });

    test('adds nothing to a lexer error', () {
      final parsed = Parsed('{ a ~ b }');
      expect(parsed.errors, ['1:5 GQL001 Unexpected character: "~".']);
      expect(fieldNames(parsed.partial), ['a', 'b']);
    });

    test('a selection set whose every selection failed fails too', () {
      final parsed = Parsed('{ a { b(x: ) } c }');
      expect(parsed.errors, ['1:12 GQL008 Unexpected ")".']);
      expect(fieldNames(parsed.partial), ['c']);
    });

    test('an unclosed selection set fails the definition once', () {
      final parsed = Parsed('{ a { b }');
      expect(parsed.errors, ['1:10 GQL007 Expected Name, found <EOF>.']);
      expect(parsed.partial.definitions, isEmpty);
    });
  });

  group('limits', () {
    test('a document past maxDepth loses only the deep definition', () {
      const options = ParserOptions(maxDepth: 2);
      final parsed = Parsed('{ a { b { c } } } { d }', options: options);
      expect(parsed.errors, [
        '1:9 GQL010 Document nests deeper than 2 levels.',
      ]);
      expect(fieldNames(parsed.partial), ['d']);
    });

    test('maxTokens stops the parse with one error', () {
      const options = ParserOptions(maxTokens: 7);
      expect(Parsed('{ foo(bar: "baz") }', options: options).errors, [
        '1:19 GQL006 Document contains more than 7 tokens. Parsing aborted.',
      ]);
      const enough = ParserOptions(maxTokens: 8);
      expect(Parsed('{ foo(bar: "baz") }', options: enough).errors, isEmpty);
    });

    test('a full sink stops the parse', () {
      final diagnostics = Parsed('~ ' * 150).result.diagnostics;
      expect(diagnostics, hasLength(DiagnosticSink.defaultMaxErrors + 1));
      expect(diagnostics.last.code, DiagnosticCode.diagnosticLimitReached);
    });
  });
}
```

Create `packages/typed_graphql/test/language/parser/token_cursor_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/language/parser/syntax_abort.dart';
import 'package:typed_graphql/src/language/parser/token_cursor.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  TokenCursor cursorOf(String text, DiagnosticSink sink) =>
      TokenCursor(Lexer(Source(text), sink), sink);

  test('lookahead reads the next token without consuming', () {
    final cursor = cursorOf('a b', DiagnosticSink());
    expect(cursor.lookahead().value, 'b');
    expect(cursor.token.value, 'a');
    cursor.advance();
    expect(cursor.token.value, 'b');
    expect(cursor.lastEnd, 1);
  });

  test('the balance counts consumed brackets, braces and parentheses', () {
    final cursor = cursorOf('{ ( [ ] ) }', DiagnosticSink());
    final balances = [
      for (var i = 0; i < 6; i++) (cursor..advance()).balance,
    ];
    expect(balances, [1, 2, 3, 2, 1, 0]);
  });

  test('a second failure at the same offset is not reported', () {
    final sink = DiagnosticSink();
    final cursor = cursorOf('x', sink);
    expect(() => cursor.expect(TokenKind.colon), throwsA(isA<SyntaxAbort>()));
    expect(cursor.unexpected, throwsA(isA<SyntaxAbort>()));
    expect(sink.diagnostics.single.message, 'Expected ":", found Name "x".');
  });

  test('a failure at an error token adds nothing to the lexer error', () {
    final sink = DiagnosticSink();
    final cursor = cursorOf('~', sink);
    expect(cursor.unexpected, throwsA(isA<SyntaxAbort>()));
    expect(sink.diagnostics.single.code, DiagnosticCode.unexpectedCharacter);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_executable_test.dart test/language/parser/recovery_test.dart test/language/parser/token_cursor_test.dart)
```

Expected: FAIL to compile: `Type 'ParseResult' not found` (in `parsed.dart`, for `parse_executable_test.dart` and `recovery_test.dart`). `token_cursor_test.dart` passes (`+4`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -64,5 +64,13 @@ enum DiagnosticCode(
 
   /// `GQL010`: selection sets, lists, objects and list types nested deeper
   /// than the parser's `maxDepth`; the definition is dropped.
-  depthLimitExceeded('GQL010');
+  depthLimitExceeded('GQL010'),
+
+  /// `GQL011`: a description where none is allowed: before a shorthand
+  /// query `{ ... }` or before something that is not a definition.
+  misplacedDescription('GQL011'),
+
+  /// `GQL012`: an empty selection set, `{ }`, which only the working
+  /// draft allows (`ParserOptions.allowEmptySelectionSets`).
+  emptySelectionSet('GQL012');
 }
```

Create `packages/typed_graphql/lib/src/language/parser/definition_parser.dart`:

```dart
import '../ast/definition.dart';
import '../lexer/token.dart';
import 'executable_parser.dart';
import 'token_cursor.dart';

/// Parses one definition of a document: it reads the keyword, after an
/// optional description, and hands over to the part of the grammar that
/// owns it (spec §2.2).
final class DefinitionParser {
  /// Creates a parser reading from [cursor].
  DefinitionParser(this.cursor, this.executable);

  /// The token stream.
  final TokenCursor cursor;

  /// Operations and fragments.
  final ExecutableParser executable;

  /// `Definition`, with graphql-js's messages for a misplaced description.
  Definition definition() {
    if (cursor.peek(.braceLeft)) {
      return executable.operation();
    }
    final hasDescription = cursor.peek(.string) || cursor.peek(.blockString);
    final keyword = hasDescription ? cursor.lookahead() : cursor.token;
    if (hasDescription && keyword.kind == .braceLeft) {
      cursor.fail(
        .misplacedDescription,
        'Unexpected description, descriptions are not supported on '
        'shorthand queries.',
      );
    }
    return switch (keyword) {
      Token(kind: .name, value: 'query' || 'mutation' || 'subscription') =>
        executable.operation(),
      Token(kind: .name, value: 'fragment') => executable.fragment(),
      Token(kind: .name) when hasDescription => cursor.fail(
        .misplacedDescription,
        'Unexpected description, only GraphQL definitions support '
        'descriptions.',
      ),
      _ => cursor.unexpected(keyword),
    };
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/directive_parser.dart`:

```dart
import '../ast/argument.dart';
import '../ast/directive.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses directives and arguments (spec §2.6, §2.12).
final class DirectiveParser {
  /// Creates a parser reading from [cursor] with [values].
  DirectiveParser(this.cursor, this.values);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// `Directives[?Const]`: zero or more `@name(arguments)`.
  List<Directive> directives({required bool isConst}) {
    final directives = <Directive>[];
    while (cursor.peek(.at)) {
      directives.add(_directive(isConst: isConst));
    }
    return directives;
  }

  /// `Arguments[?Const]`: `(name: value ...)`, or none.
  List<Argument> arguments({required bool isConst}) => cursor.optionalMany(
    .parenLeft,
    () => _argument(isConst: isConst),
    .parenRight,
  );

  Directive _directive({required bool isConst}) {
    final start = cursor.token.start;
    cursor.expect(.at);
    final name = cursor.name();
    final arguments = this.arguments(isConst: isConst);
    return Directive(
      name,
      arguments: arguments,
      start: start,
      end: cursor.lastEnd,
    );
  }

  Argument _argument({required bool isConst}) {
    final start = cursor.token.start;
    final name = cursor.name();
    cursor.expect(.colon);
    final value = values.value(isConst: isConst);
    return Argument(name, value, start: start, end: cursor.lastEnd);
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/executable_parser.dart`:

```dart
import '../ast/executable_definition.dart';
import '../ast/variable_definition.dart';
import 'directive_parser.dart';
import 'selection_parser.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses operations and fragment definitions (spec §2.3, §2.8), with
/// the descriptions September2025 allows on them.
final class ExecutableParser {
  /// Creates a parser reading from [cursor].
  ExecutableParser(this.cursor, this.values, this.directives, this.selections);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The selection productions.
  final SelectionParser selections;

  /// `OperationDefinition`: a shorthand query `{ ... }` or a described,
  /// typed, optionally named operation.
  OperationDefinition operation() {
    final start = cursor.token.start;
    if (cursor.peek(.braceLeft)) {
      final selectionSet = selections.selectionSet();
      return OperationDefinition(
        .query,
        selectionSet,
        start: start,
        end: cursor.lastEnd,
      );
    }
    final description = values.description();
    final operation = values.operationType();
    final name = cursor.peek(.name) ? cursor.name() : null;
    final variables = cursor.optionalMany(
      .parenLeft,
      _variableDefinition,
      .parenRight,
    );
    final directiveList = directives.directives(isConst: false);
    final selectionSet = selections.selectionSet();
    return OperationDefinition(
      operation,
      selectionSet,
      description: description,
      name: name,
      variableDefinitions: variables,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// `FragmentDefinition`: `fragment Name on Type { ... }`.
  FragmentDefinition fragment() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('fragment');
    final name = selections.fragmentName();
    cursor.expectKeyword('on');
    final typeCondition = values.namedType();
    final directiveList = directives.directives(isConst: false);
    final selectionSet = selections.selectionSet();
    return FragmentDefinition(
      name,
      typeCondition,
      selectionSet,
      description: description,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  VariableDefinition _variableDefinition() {
    final start = cursor.token.start;
    final description = values.description();
    final variable = values.variable();
    cursor.expect(.colon);
    final type = values.typeRef();
    final defaultValue = cursor.expectOptional(.equals)
        ? values.value(isConst: true)
        : null;
    final directiveList = directives.directives(isConst: true);
    return VariableDefinition(
      variable,
      type,
      description: description,
      defaultValue: defaultValue,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/graphql_syntax_exception.dart`:

```dart
import '../../diagnostics/diagnostic.dart';

/// Thrown by `requireDocument` when a document has syntax errors; it
/// carries every diagnostic of the parse.
final class GraphQLSyntaxException implements Exception {
  /// Creates an exception with [diagnostics].
  GraphQLSyntaxException(List<Diagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);

  /// The diagnostics of the parse, in report order.
  final List<Diagnostic> diagnostics;

  @override
  String toString() =>
      'GraphQLSyntaxException:\n${diagnostics.map((d) => '  $d').join('\n')}';
}
```

Create `packages/typed_graphql/lib/src/language/parser/parse_result.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../ast/document.dart';
import 'graphql_syntax_exception.dart';

/// The result of parsing a document: [ParseSuccess] or [ParseFailure],
/// both with every [diagnostics] (R1.5).
sealed class ParseResult(List<Diagnostic> diagnostics) {
  /// Creates a result.
  this;

  /// Every diagnostic of the parse, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);

  /// The document; throws a [GraphQLSyntaxException] with [diagnostics]
  /// when the parse failed. For tests and scripts.
  Document requireDocument() => switch (this) {
    ParseSuccess(:final document) => document,
    ParseFailure() => throw GraphQLSyntaxException(diagnostics),
  };
}

/// A document without syntax errors; [diagnostics] hold warnings only.
final class ParseSuccess(
  /// The document.
  final Document document,
  super.diagnostics,
) extends ParseResult {
  /// Creates a success.
  this;
}

/// A document with syntax errors.
final class ParseFailure(
  /// Every definition that parsed completely; a definition or selection
  /// with an error is left out, so the tree has no error nodes.
  final Document partial,
  super.diagnostics,
) extends ParseResult {
  /// Creates a failure.
  this;
}
```

Replace `packages/typed_graphql/lib/src/language/parser/parser.dart` whole with:

```dart
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../ast/definition.dart';
import '../ast/document.dart';
import '../ast/node.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/lexer.dart';
import 'definition_parser.dart';
import 'directive_parser.dart';
import 'executable_parser.dart';
import 'parse_element_result.dart';
import 'parse_result.dart';
import 'parser_options.dart';
import 'recovery.dart';
import 'selection_parser.dart';
import 'syntax_abort.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses GraphQL documents and single elements; it never throws on bad
/// input (R1.5): the result carries every diagnostic.
///
/// The grammar lives in collaborators, one per part of the language; this
/// class wires them to a [TokenCursor] and assembles results.
final class Parser {
  /// Creates a parser with [options].
  const Parser({this.options = const ParserOptions()});

  /// The limits and the working-draft grammar this parser accepts.
  final ParserOptions options;

  /// Parses [source] as a document. A definition with a syntax error is
  /// reported and left out, and parsing resumes at the next definition.
  ParseResult parse(Source source) {
    final sink = DiagnosticSink();
    final cursor = _cursor(source, sink);
    final definitions = _definitions(cursor);
    final recovery = Recovery(cursor);
    final parsed = <Definition>[];
    do {
      final first = cursor.token;
      final balance = cursor.balance;
      try {
        parsed.add(definitions.definition());
      } on SyntaxAbort {
        recovery.skipDefinition(first, balance);
      }
    } while (!cursor.peek(.eof) && !cursor.isStopped);
    final document = Document(parsed, start: 0, end: source.body.length);
    return sink.hasErrors
        ? ParseFailure(document, sink.diagnostics)
        : ParseSuccess(document, sink.diagnostics);
  }

  /// Parses [source] as one value, such as `[1, $a]`; with [isConst], a
  /// variable is an error.
  ParseElementResult<Value> parseValue(Source source, {bool isConst = false}) =>
      _element(source, (cursor) => ValueParser(cursor).value(isConst: isConst));

  /// Parses [source] as one type reference, such as `[String!]`.
  ParseElementResult<TypeRef> parseTypeRef(Source source) =>
      _element(source, (cursor) => ValueParser(cursor).typeRef());

  TokenCursor _cursor(Source source, DiagnosticSink sink) => TokenCursor(
    Lexer(source, sink, maxTokens: options.maxTokens),
    sink,
    maxDepth: options.maxDepth,
  );

  DefinitionParser _definitions(TokenCursor cursor) {
    final values = ValueParser(cursor);
    final directives = DirectiveParser(cursor, values);
    final selections = SelectionParser(
      cursor,
      values,
      directives,
      allowsEmpty: options.allowEmptySelectionSets,
    );
    return DefinitionParser(
      cursor,
      ExecutableParser(cursor, values, directives, selections),
    );
  }

  /// Parses [source] with [parse], which must read it to the end.
  ParseElementResult<T> _element<T extends Node>(
    Source source,
    T Function(TokenCursor cursor) parse,
  ) {
    final sink = DiagnosticSink();
    final cursor = _cursor(source, sink);
    try {
      final element = parse(cursor);
      cursor.expect(.eof);
      if (!sink.hasErrors) {
        return ParseElementSuccess(element, sink.diagnostics);
      }
    } on SyntaxAbort {
      // The error is in the sink; an element has no partial result.
    }
    return ParseElementFailure(sink.diagnostics);
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/recovery.dart`:

```dart
import '../lexer/token.dart';
import '../lexer/token_kind.dart';
import 'token_cursor.dart';

/// Where the parser resumes after a syntax error (R1.5): it skips tokens
/// to the next place where a definition or a selection can start, at the
/// bracket level where the failed one started.
final class Recovery {
  /// Creates the policy for [cursor].
  Recovery(this.cursor);

  /// The token stream.
  final TokenCursor cursor;

  static const Set<String> _definitionKeywords = {
    'query',
    'mutation',
    'subscription',
    'fragment',
    'schema',
    'scalar',
    'type',
    'interface',
    'union',
    'enum',
    'input',
    'directive',
    'extend',
  };

  /// Skips the rest of a definition that started at [first] when the
  /// cursor's balance was [balance].
  void skipDefinition(Token first, int balance) =>
      _skip(first, balance, _startsDefinition);

  /// Skips the rest of a selection that started at [first] when the
  /// cursor's balance was [balance]; it stops before a name, `...` or the
  /// `}` that closes the selection set.
  void skipSelection(Token first, int balance) =>
      _skip(first, balance, _startsSelection);

  /// Consumes at least one token, so the parser always moves on, then
  /// every token up to a [isResumable] one at [balance] or below, or the
  /// end.
  void _skip(Token first, int balance, bool Function(Token) isResumable) {
    if (identical(cursor.token, first)) {
      cursor.advance();
    }
    while (!cursor.peek(.eof) &&
        !(cursor.balance <= balance && isResumable(cursor.token))) {
      cursor.advance();
    }
  }

  static bool _startsDefinition(Token token) => switch (token.kind) {
    .braceLeft || .string || .blockString => true,
    .name => _definitionKeywords.contains(token.value),
    _ => false,
  };

  static bool _startsSelection(Token token) =>
      token.kind == TokenKind.name ||
      token.kind == TokenKind.spread ||
      token.kind == TokenKind.braceRight;
}
```

Create `packages/typed_graphql/lib/src/language/parser/selection_parser.dart`:

```dart
import '../ast/name.dart';
import '../ast/selection.dart';
import '../ast/selection_set.dart';
import 'directive_parser.dart';
import 'recovery.dart';
import 'syntax_abort.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses selection sets, fields and fragment spreads (spec §2.4–§2.8);
/// a failed selection is dropped and parsing resumes at the next one.
final class SelectionParser {
  /// Creates a parser reading from [cursor].
  SelectionParser(
    this.cursor,
    this.values,
    this.directives, {
    required this.allowsEmpty,
  }) : _recovery = Recovery(cursor);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// Whether `{ }` is accepted (working draft).
  final bool allowsEmpty;

  final Recovery _recovery;

  /// `SelectionSet`: `{ selection ... }`, one nesting level deeper.
  SelectionSet selectionSet() => cursor.nested(_selectionSet);

  /// `FragmentName`: a name other than `on`.
  Name fragmentName() {
    if (cursor.peekKeyword('on')) {
      cursor.unexpected();
    }
    return cursor.name();
  }

  SelectionSet _selectionSet() {
    final start = cursor.token.start;
    cursor.expect(.braceLeft);
    if (cursor.peek(.braceRight) && !allowsEmpty) {
      cursor.fail(.emptySelectionSet, 'Unexpected empty selection set.');
    }
    final selections = <Selection>[];
    while (!cursor.expectOptional(.braceRight)) {
      if (_selectionOrSkip() case final selection?) {
        selections.add(selection);
      }
    }
    if (selections.isEmpty && !allowsEmpty) {
      // Every selection failed and was reported; an empty set would not
      // be a valid tree, so the enclosing selection fails too.
      throw const SyntaxAbort();
    }
    return SelectionSet(selections, start: start, end: cursor.lastEnd);
  }

  /// A selection, or null when it failed and was skipped; at the end of
  /// the document the whole definition fails.
  Selection? _selectionOrSkip() {
    final first = cursor.token;
    final balance = cursor.balance;
    try {
      return cursor.peek(.spread) ? _fragment() : _field();
    } on SyntaxAbort catch (abort) {
      if (abort.endsDefinition || cursor.isStopped) {
        rethrow;
      }
      _recovery.skipSelection(first, balance);
      if (cursor.peek(.eof)) {
        rethrow;
      }
      return null;
    }
  }

  Field _field() {
    final start = cursor.token.start;
    final nameOrAlias = cursor.name();
    final hasAlias = cursor.expectOptional(.colon);
    final name = hasAlias ? cursor.name() : nameOrAlias;
    final arguments = directives.arguments(isConst: false);
    final directiveList = directives.directives(isConst: false);
    final selectionSet = cursor.peek(.braceLeft) ? this.selectionSet() : null;
    return Field(
      hasAlias ? nameOrAlias : null,
      name,
      arguments: arguments,
      directives: directiveList,
      selectionSet: selectionSet,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// `...Name` or `... on Type { }` (an inline fragment may omit the
  /// type condition).
  Selection _fragment() {
    final start = cursor.token.start;
    cursor.expect(.spread);
    final hasTypeCondition = cursor.expectOptionalKeyword('on');
    if (!hasTypeCondition && cursor.peek(.name)) {
      final name = fragmentName();
      final directiveList = directives.directives(isConst: false);
      return FragmentSpread(
        name,
        directives: directiveList,
        start: start,
        end: cursor.lastEnd,
      );
    }
    final typeCondition = hasTypeCondition ? values.namedType() : null;
    final directiveList = directives.directives(isConst: false);
    final selectionSet = this.selectionSet();
    return InlineFragment(
      typeCondition,
      selectionSet,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_executable_test.dart test/language/parser/recovery_test.dart test/language/parser/token_cursor_test.dart)
```

Expected: `parse_executable_test.dart` `+13`, `recovery_test.dart` `+10`, `token_cursor_test.dart` `+4`, each `All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -105,6 +105,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `TokenCursor.fail`, which throws the internal `SyntaxAbort`; it never
   leaves `Parser`. The cursor is silent at error tokens (the lexer
   reported them) and at an offset that already has a diagnostic.
+  `Recovery` resynchronises (R1.5): `Parser.parse` drops a failed
+  definition and skips to the next definition keyword, `{` or description;
+  `SelectionParser` drops a failed selection and skips to a name, `...` or
+  `}`; both only at the bracket `balance` where the failed part started,
+  and always consume a token. A selection set left empty fails too.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/enum_value_definition.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/field_definition.dart';
export 'src/language/ast/input_value_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/operation_type_definition.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/type_system_definition.dart';
export 'src/language/ast/type_system_extension.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/language/lexer/block_string.dart';
export 'src/language/lexer/lexer.dart';
export 'src/language/lexer/token.dart';
export 'src/language/lexer/token_kind.dart';
export 'src/language/parser/graphql_syntax_exception.dart';
export 'src/language/parser/parse_element_result.dart';
export 'src/language/parser/parse_result.dart';
export 'src/language/parser/parser.dart';
export 'src/language/parser/parser_options.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/language/parser/definition_parser.dart packages/typed_graphql/lib/src/language/parser/directive_parser.dart packages/typed_graphql/lib/src/language/parser/executable_parser.dart packages/typed_graphql/lib/src/language/parser/graphql_syntax_exception.dart packages/typed_graphql/lib/src/language/parser/parse_result.dart packages/typed_graphql/lib/src/language/parser/parser.dart packages/typed_graphql/lib/src/language/parser/recovery.dart packages/typed_graphql/lib/src/language/parser/selection_parser.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/parser/parse_executable_test.dart packages/typed_graphql/test/language/parser/parsed.dart packages/typed_graphql/test/language/parser/recovery_test.dart packages/typed_graphql/test/language/parser/token_cursor_test.dart
git commit -q -m "feat(typed_graphql): parse executable documents with error recovery"
```

### Task 10: Type-system definitions

**Files:**
- Create: `packages/typed_graphql/lib/src/language/parser/type_member_parser.dart`, `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/language/parser/definition_parser.dart`, `packages/typed_graphql/lib/src/language/parser/parser.dart`
- Test: `packages/typed_graphql/test/language/parser/parse_type_system_test.dart`

**Interfaces:**
- Consumes: Tasks 8–9: `TokenCursor`, `ValueParser`, `DirectiveParser`, `DefinitionParser`; Task 4: the type-system nodes.
- Produces:
  - internal `TypeMemberParser(cursor, values, directives)`, shared with Task 11's extensions: `interfaces()`, `unionMembers()`, `fields()`, `arguments()`, `inputFields()`, `enumValues()` and `operationType()`;
  - internal `TypeSystemParser(cursor, values, directives, members)` with `definition(String keyword)`: schema, scalar, type, interface, union, enum, input and directive definitions, with descriptions;
  - new code: `GQL013 reservedEnumValueName` (`true`, `false`, `null` as an enum value).

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/parser/parse_type_system_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  group('types', () {
    test('parses an object type with a described field and arguments', () {
      const text =
          '"""Hi""" type Hello implements & A & B @d { '
          '"w" world(flag: Boolean = true @e, list: [Int]): String! }';
      final type = Parsed(text).single<ObjectTypeDefinition>();
      expect(type.description?.isBlock, isTrue);
      expect(type.name.value, 'Hello');
      expect(type.interfaces.map((interface) => interface.name.value), [
        'A',
        'B',
      ]);
      final field = type.fields.single;
      expect(field.description?.value, 'w');
      expect(field.arguments.first.defaultValue, isA<BooleanValue>());
      expect(field.arguments.first.directives.single.name.value, 'e');
      expect(field.type, isA<NonNullType>());
      expect([type.start, type.end], [0, text.length]);
    });

    test('parses interfaces, unions, enums, inputs and scalars', () {
      final document = Parsed(
        'interface I implements J { a: Int } '
        'union U = | A | B '
        'enum E { "d" ONE TWO @d } '
        'input In { a: Int = 1 } '
        'scalar S @specifiedBy(url: "u")',
      ).document;
      if (document.definitions case [
        final InterfaceTypeDefinition interface,
        final UnionTypeDefinition union,
        final EnumTypeDefinition enumType,
        final InputObjectTypeDefinition input,
        final ScalarTypeDefinition scalar,
      ]) {
        expect(interface.interfaces.single.name.value, 'J');
        expect(union.types.map((type) => type.name.value), ['A', 'B']);
        expect(enumType.values.map((value) => value.name.value), [
          'ONE',
          'TWO',
        ]);
        expect(enumType.values.first.description?.value, 'd');
        expect(input.fields.single.defaultValue, isA<IntValue>());
        expect(scalar.directives.single.name.value, 'specifiedBy');
      } else {
        fail('unexpected definitions: ${document.definitions}');
      }
    });

    test('a type without fields has none', () {
      expect(
        Parsed('type Hello').single<ObjectTypeDefinition>().fields,
        isEmpty,
      );
    });
  });

  group('schema and directives', () {
    test('parses a described schema definition', () {
      final schema = Parsed(
        '"S" schema @d { query: Q mutation: M subscription: S }',
      ).single<SchemaDefinition>();
      expect(schema.description?.value, 'S');
      expect(schema.operationTypes.map((type) => type.operation), [
        OperationType.query,
        OperationType.mutation,
        OperationType.subscription,
      ]);
    });

    test('parses a repeatable directive definition', () {
      final directive = Parsed(
        'directive @d(a: Int) repeatable on | FIELD | OBJECT',
      ).single<DirectiveDefinition>();
      expect(directive.isRepeatable, isTrue);
      expect(directive.arguments.single.name.value, 'a');
      expect(directive.locations.map((location) => location.value), [
        'FIELD',
        'OBJECT',
      ]);
    });
  });

  group('errors', () {
    test('rejects an unknown directive location', () {
      expect(Parsed('directive @d on FIELD | INCORRECT_LOCATION').errors, [
        '1:25 GQL008 Unexpected Name "INCORRECT_LOCATION".',
      ]);
    });

    test('rejects true, false and null as enum values', () {
      expect(Parsed('enum Test { VALID, true }').errors, [
        '1:20 GQL013 Name "true" is reserved and cannot be used for an '
            'enum value.',
      ]);
    });

    test('rejects a union without members and input fields with arguments', () {
      expect(Parsed('union Hello = |').errors, [
        '1:16 GQL007 Expected Name, found <EOF>.',
      ]);
      expect(Parsed('input Hello { world(foo: Int): String }').errors, [
        '1:20 GQL007 Expected ":", found "(".',
      ]);
    });

    test('type-system directive arguments are constant', () {
      expect(Parsed(r'type T @d(a: $x)').errors, [
        r'1:14 GQL009 Unexpected variable "$x" in constant value.',
      ]);
    });

    test('a bad definition between good ones is dropped', () {
      final parsed = Parsed('type A { a: Int } enum E { null } scalar S');
      expect(parsed.errors, hasLength(1));
      expect(
        parsed.partial.definitions.map((definition) => definition.runtimeType),
        [
          ObjectTypeDefinition,
          ScalarTypeDefinition,
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_type_system_test.dart)
```

Expected: FAIL. `parse_type_system_test.dart` reports `Expected: ['1:25 GQL008 Unexpected Name "INCORRECT_LOCATION".']` and similar, because type-system keywords are not definitions yet.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -72,5 +72,9 @@ enum DiagnosticCode(
 
   /// `GQL012`: an empty selection set, `{ }`, which only the working
   /// draft allows (`ParserOptions.allowEmptySelectionSets`).
-  emptySelectionSet('GQL012');
+  emptySelectionSet('GQL012'),
+
+  /// `GQL013`: an enum value named `true`, `false` or `null` (spec
+  /// §3.9, `EnumValue`).
+  reservedEnumValueName('GQL013');
 }
```

In `packages/typed_graphql/lib/src/language/parser/definition_parser.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,13 +2,14 @@ import '../ast/definition.dart';
 import '../lexer/token.dart';
 import 'executable_parser.dart';
 import 'token_cursor.dart';
+import 'type_system_parser.dart';
 
 /// Parses one definition of a document: it reads the keyword, after an
 /// optional description, and hands over to the part of the grammar that
 /// owns it (spec §2.2).
 final class DefinitionParser {
   /// Creates a parser reading from [cursor].
-  DefinitionParser(this.cursor, this.executable);
+  DefinitionParser(this.cursor, this.executable, this.typeSystem);
 
   /// The token stream.
   final TokenCursor cursor;
@@ -16,6 +17,9 @@ final class DefinitionParser {
   /// Operations and fragments.
   final ExecutableParser executable;
 
+  /// Schema, type and directive definitions.
+  final TypeSystemParser typeSystem;
+
   /// `Definition`, with graphql-js's messages for a misplaced description.
   Definition definition() {
     if (cursor.peek(.braceLeft)) {
@@ -31,6 +35,9 @@ final class DefinitionParser {
       );
     }
     return switch (keyword) {
+      Token(kind: .name, :final value?)
+          when TypeSystemParser.keywords.contains(value) =>
+        typeSystem.definition(value),
       Token(kind: .name, value: 'query' || 'mutation' || 'subscription') =>
         executable.operation(),
       Token(kind: .name, value: 'fragment') => executable.fragment(),
```

In `packages/typed_graphql/lib/src/language/parser/parser.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,6 +16,8 @@ import 'recovery.dart';
 import 'selection_parser.dart';
 import 'syntax_abort.dart';
 import 'token_cursor.dart';
+import 'type_member_parser.dart';
+import 'type_system_parser.dart';
 import 'value_parser.dart';
 
 /// Parses GraphQL documents and single elements; it never throws on bad
@@ -77,9 +79,11 @@ final class Parser {
       directives,
       allowsEmpty: options.allowEmptySelectionSets,
     );
+    final members = TypeMemberParser(cursor, values, directives);
     return DefinitionParser(
       cursor,
       ExecutableParser(cursor, values, directives, selections),
+      TypeSystemParser(cursor, values, directives, members),
     );
   }
 
```

Create `packages/typed_graphql/lib/src/language/parser/type_member_parser.dart`:

```dart
import '../ast/enum_value_definition.dart';
import '../ast/field_definition.dart';
import '../ast/input_value_definition.dart';
import '../ast/name.dart';
import '../ast/operation_type_definition.dart';
import '../ast/type_ref.dart';
import '../lexer/token.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses what type-system definitions and extensions share: fields,
/// input values, enum values, interfaces, union members and root
/// operation types (spec §3).
final class TypeMemberParser {
  /// Creates a parser reading from [cursor].
  TypeMemberParser(this.cursor, this.values, this.directives);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// `ImplementsInterfaces`: `implements A & B`, or none.
  List<NamedType> interfaces() => cursor.expectOptionalKeyword('implements')
      ? cursor.delimitedMany(.ampersand, values.namedType)
      : <NamedType>[];

  /// `UnionMemberTypes`: `= A | B`, or none.
  List<NamedType> unionMembers() => cursor.expectOptional(.equals)
      ? cursor.delimitedMany(.pipe, values.namedType)
      : <NamedType>[];

  /// `FieldsDefinition`: `{ field ... }`, or none.
  List<FieldDefinition> fields() =>
      cursor.optionalMany(.braceLeft, _field, .braceRight);

  /// `ArgumentsDefinition`: `(input ...)`, or none.
  List<InputValueDefinition> arguments() =>
      cursor.optionalMany(.parenLeft, _inputValue, .parenRight);

  /// `InputFieldsDefinition`: `{ input ... }`, or none.
  List<InputValueDefinition> inputFields() =>
      cursor.optionalMany(.braceLeft, _inputValue, .braceRight);

  /// `EnumValuesDefinition`: `{ VALUE ... }`, or none.
  List<EnumValueDefinition> enumValues() =>
      cursor.optionalMany(.braceLeft, _enumValue, .braceRight);

  /// `RootOperationTypeDefinition`: `query: Query`.
  OperationTypeDefinition operationType() {
    final start = cursor.token.start;
    final operation = values.operationType();
    cursor.expect(.colon);
    final type = values.namedType();
    return OperationTypeDefinition(
      operation,
      type,
      start: start,
      end: cursor.lastEnd,
    );
  }

  FieldDefinition _field() {
    final start = cursor.token.start;
    final description = values.description();
    final name = cursor.name();
    final arguments = this.arguments();
    cursor.expect(.colon);
    final type = values.typeRef();
    final directiveList = directives.directives(isConst: true);
    return FieldDefinition(
      name,
      type,
      description: description,
      arguments: arguments,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InputValueDefinition _inputValue() {
    final start = cursor.token.start;
    final description = values.description();
    final name = cursor.name();
    cursor.expect(.colon);
    final type = values.typeRef();
    final defaultValue = cursor.expectOptional(.equals)
        ? values.value(isConst: true)
        : null;
    final directiveList = directives.directives(isConst: true);
    return InputValueDefinition(
      name,
      type,
      description: description,
      defaultValue: defaultValue,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  EnumValueDefinition _enumValue() {
    final start = cursor.token.start;
    final description = values.description();
    final name = _enumValueName();
    final directiveList = directives.directives(isConst: true);
    return EnumValueDefinition(
      name,
      description: description,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  Name _enumValueName() {
    final token = cursor.token;
    if (token case Token(kind: .name, value: 'true' || 'false' || 'null')) {
      cursor.fail(
        .reservedEnumValueName,
        '${token.description} is reserved and cannot be used for an enum '
        'value.',
      );
    }
    return cursor.name();
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart`:

```dart
import '../ast/name.dart';
import '../ast/type_system_definition.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'type_member_parser.dart';
import 'value_parser.dart';

/// Parses schema, type and directive definitions (spec §3).
final class TypeSystemParser {
  /// Creates a parser reading from [cursor].
  TypeSystemParser(this.cursor, this.values, this.directives, this.members);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The shared members of types.
  final TypeMemberParser members;

  /// The keywords that start a type-system definition.
  static const Set<String> keywords = {
    'schema',
    'scalar',
    'type',
    'interface',
    'union',
    'enum',
    'input',
    'directive',
  };

  /// The September2025 directive locations (spec §3.13).
  static const Set<String> locations = {
    'QUERY',
    'MUTATION',
    'SUBSCRIPTION',
    'FIELD',
    'FRAGMENT_DEFINITION',
    'FRAGMENT_SPREAD',
    'INLINE_FRAGMENT',
    'VARIABLE_DEFINITION',
    'SCHEMA',
    'SCALAR',
    'OBJECT',
    'FIELD_DEFINITION',
    'ARGUMENT_DEFINITION',
    'INTERFACE',
    'UNION',
    'ENUM',
    'ENUM_VALUE',
    'INPUT_OBJECT',
    'INPUT_FIELD_DEFINITION',
  };

  /// The definition that [keyword], one of [keywords], starts, after an
  /// optional description.
  TypeSystemDefinition definition(String keyword) => switch (keyword) {
    'schema' => _schema(),
    'scalar' => _scalar(),
    'type' => _object(),
    'interface' => _interface(),
    'union' => _union(),
    'enum' => _enum(),
    'input' => _inputObject(),
    'directive' => _directive(),
    _ => throw ArgumentError.value(keyword, 'keyword', 'not in keywords'),
  };

  SchemaDefinition _schema() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('schema');
    final directiveList = directives.directives(isConst: true);
    final operationTypes = cursor.many(
      .braceLeft,
      members.operationType,
      .braceRight,
    );
    return SchemaDefinition(
      description: description,
      directives: directiveList,
      operationTypes: operationTypes,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ScalarTypeDefinition _scalar() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('scalar');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    return ScalarTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ObjectTypeDefinition _object() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('type');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    return ObjectTypeDefinition(
      name,
      description: description,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InterfaceTypeDefinition _interface() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('interface');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    return InterfaceTypeDefinition(
      name,
      description: description,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  UnionTypeDefinition _union() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('union');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final types = members.unionMembers();
    return UnionTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      types: types,
      start: start,
      end: cursor.lastEnd,
    );
  }

  EnumTypeDefinition _enum() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('enum');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final enumValues = members.enumValues();
    return EnumTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      values: enumValues,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InputObjectTypeDefinition _inputObject() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('input');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final fields = members.inputFields();
    return InputObjectTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  DirectiveDefinition _directive() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('directive');
    cursor.expect(.at);
    final name = cursor.name();
    final arguments = members.arguments();
    final isRepeatable = cursor.expectOptionalKeyword('repeatable');
    cursor.expectKeyword('on');
    final locations = cursor.delimitedMany(.pipe, _location);
    return DirectiveDefinition(
      name,
      description: description,
      arguments: arguments,
      isRepeatable: isRepeatable,
      locations: locations,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// `DirectiveLocation`: one of [locations].
  Name _location() {
    final token = cursor.token;
    final name = cursor.name();
    if (!locations.contains(name.value)) {
      cursor.unexpected(token);
    }
    return name;
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_type_system_test.dart)
```

Expected: `+10: All tests passed!`

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -110,6 +110,7 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `SelectionParser` drops a failed selection and skips to a name, `...` or
   `}`; both only at the bracket `balance` where the failed part started,
   and always consume a token. A selection set left empty fails too.
+  Type-system definitions and extensions share `TypeMemberParser`.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/language/parser/definition_parser.dart packages/typed_graphql/lib/src/language/parser/parser.dart packages/typed_graphql/lib/src/language/parser/type_member_parser.dart packages/typed_graphql/lib/src/language/parser/type_system_parser.dart packages/typed_graphql/test/language/parser/parse_type_system_test.dart
git commit -q -m "feat(typed_graphql): parse type system definitions"
```

### Task 11: Type-system extensions and the working-draft grammar

The extensions, and the extension point for draft and experimental grammar (R1.4, decision 8).

**Files:**
- Create: `packages/typed_graphql/lib/src/language/parser/definition_grammar.dart`, `packages/typed_graphql/lib/src/language/parser/directive_extension_grammar.dart`, `packages/typed_graphql/lib/src/language/parser/extension_parser.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/language/parser/definition_parser.dart`, `packages/typed_graphql/lib/src/language/parser/parser.dart`, `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart`
- Test: `packages/typed_graphql/test/language/parser/parse_extension_test.dart`

**Interfaces:**
- Consumes: Task 10: `TypeSystemParser`, `TypeMemberParser`, `DefinitionParser`; Task 8: `ParserOptions.allowDirectiveExtensions`.
- Produces:
  - internal `ExtensionParser(cursor, directives, members)` with `extension()`, covering `extend schema|scalar|type|interface|union|enum|input`. An extension with nothing in it is `Unexpected <EOF>.`, at graphql-js's location;
  - internal `abstract interface class DefinitionGrammar { bool startsDefinition(); Definition definition(); }`, which `DefinitionParser(cursor, executable, typeSystem, extensions, grammars)` asks before the base productions;
  - internal `DirectiveExtensionGrammar(cursor, directives, {required bool isEnabled})`;
  - `TypeSystemParser(..., {required bool allowsDirectiveExtensions})` gates directives on a directive definition and the `DIRECTIVE_DEFINITION` location;
  - new code: `GQL014 workingDraftFeatureDisabled`, whose message names `ParserOptions.allowDirectiveExtensions`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/parser/parse_extension_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  const drafts = ParserOptions(allowDirectiveExtensions: true);

  group('type extensions', () {
    test('parses a schema extension with directives and root types', () {
      const text = 'extend schema @d { mutation: M }';
      final extension = Parsed(text).single<SchemaExtension>();
      expect(extension.directives.single.name.value, 'd');
      expect(extension.operationTypes.single.type.name.value, 'M');
      expect([extension.start, extension.end], [0, text.length]);
    });

    test('parses an object extension that only adds interfaces', () {
      final extension = Parsed(
        'extend type A implements B & C',
      ).single<ObjectTypeExtension>();
      expect(extension.name.value, 'A');
      expect(extension.interfaces.map((type) => type.name.value), ['B', 'C']);
      expect(extension.fields, isEmpty);
    });

    test('parses scalar, interface, union, enum and input extensions', () {
      final document = Parsed(
        'extend scalar S @d '
        'extend interface I { a: Int } '
        'extend union U = A '
        'extend enum E { V } '
        'extend input In { a: Int }',
      ).document;
      expect(document.definitions.map((definition) => definition.runtimeType), [
        ScalarTypeExtension,
        InterfaceTypeExtension,
        UnionTypeExtension,
        EnumTypeExtension,
        InputObjectTypeExtension,
      ]);
    });

    test('rejects a type extension that adds nothing', () {
      expect(Parsed('extend type Foo').errors, [
        '1:16 GQL008 Unexpected <EOF>.',
      ]);
    });

    test('rejects a schema extension that adds nothing', () {
      expect(Parsed('extend schema').errors, [
        '1:14 GQL008 Unexpected <EOF>.',
      ]);
    });

    test('rejects an extension of an unknown kind', () {
      expect(Parsed('extend foo').errors, [
        '1:8 GQL008 Unexpected Name "foo".',
      ]);
    });

    test('rejects a description on an extension', () {
      expect(Parsed('"d" extend type A @d').errors, [
        '1:1 GQL011 Unexpected description, only GraphQL definitions '
            'support descriptions.',
      ]);
    });
  });

  group('directive extensions', () {
    test('parse when the option is on', () {
      final extension = Parsed(
        'extend directive @foo @bar',
        options: drafts,
      ).single<DirectiveExtension>();
      expect(extension.name.value, 'foo');
      expect(extension.directives.single.name.value, 'bar');
    });

    test('are reported as working draft when the option is off', () {
      expect(Parsed('extend directive @foo @bar').errors, [
        '1:1 GQL014 Directive extensions are a working-draft feature; '
            'enable them with ParserOptions.allowDirectiveExtensions.',
      ]);
    });

    test('report once and let the next definition parse', () {
      final parsed = Parsed('extend directive @foo @bar type A { a: Int }');
      expect(parsed.errors, hasLength(1));
      expect(parsed.partial.definitions.single, isA<ObjectTypeDefinition>());
    });

    test('must add a directive', () {
      expect(Parsed('extend directive @foo', options: drafts).errors, [
        '1:22 GQL008 Unexpected <EOF>.',
      ]);
    });
  });

  group('directive definitions', () {
    test('accept directives and DIRECTIVE_DEFINITION with the option', () {
      final directive = Parsed(
        'directive @a @b on DIRECTIVE_DEFINITION',
        options: drafts,
      ).single<DirectiveDefinition>();
      expect(directive.directives.single.name.value, 'b');
      expect(directive.locations.single.value, 'DIRECTIVE_DEFINITION');
    });

    test('report their directives as working draft without it', () {
      expect(Parsed('directive @a @b on FIELD').errors, [
        '1:14 GQL014 Directives on a directive definition are a '
            'working-draft feature; enable them with '
            'ParserOptions.allowDirectiveExtensions.',
      ]);
    });

    test('report DIRECTIVE_DEFINITION as working draft without it', () {
      expect(Parsed('directive @a on DIRECTIVE_DEFINITION').errors, [
        '1:17 GQL014 The DIRECTIVE_DEFINITION location is a working-draft '
            'feature; enable it with ParserOptions.allowDirectiveExtensions.',
      ]);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_extension_test.dart)
```

Expected: FAIL. `parse_extension_test.dart` reports `Expected: ['1:16 GQL008 Unexpected <EOF>.']` and similar, because `extend` is not a definition yet.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -76,5 +76,11 @@ enum DiagnosticCode(
 
   /// `GQL013`: an enum value named `true`, `false` or `null` (spec
   /// §3.9, `EnumValue`).
-  reservedEnumValueName('GQL013');
+  reservedEnumValueName('GQL013'),
+
+  /// `GQL014`: working-draft grammar that the parser's options leave off:
+  /// a directive extension, directives on a directive definition or the
+  /// `DIRECTIVE_DEFINITION` location without
+  /// `ParserOptions.allowDirectiveExtensions`.
+  workingDraftFeatureDisabled('GQL014');
 }
```

Create `packages/typed_graphql/lib/src/language/parser/definition_grammar.dart`:

```dart
import '../ast/definition.dart';

/// A definition production outside the September2025 grammar: the
/// parser's extension point for working-draft and experimental grammar
/// (R1.4). `DefinitionParser` asks every registered grammar before the
/// base productions, so a new one never edits them.
abstract interface class DefinitionGrammar {
  /// Whether the definition at the cursor belongs to this grammar.
  bool startsDefinition();

  /// Parses that definition; a syntax error fails through the cursor.
  Definition definition();
}
```

In `packages/typed_graphql/lib/src/language/parser/definition_parser.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,15 +1,23 @@
 import '../ast/definition.dart';
 import '../lexer/token.dart';
+import 'definition_grammar.dart';
 import 'executable_parser.dart';
+import 'extension_parser.dart';
 import 'token_cursor.dart';
 import 'type_system_parser.dart';
 
 /// Parses one definition of a document: it reads the keyword, after an
 /// optional description, and hands over to the part of the grammar that
-/// owns it (spec §2.2).
+/// owns it (spec §2.2). The [grammars] come first.
 final class DefinitionParser {
   /// Creates a parser reading from [cursor].
-  DefinitionParser(this.cursor, this.executable, this.typeSystem);
+  DefinitionParser(
+    this.cursor,
+    this.executable,
+    this.typeSystem,
+    this.extensions,
+    this.grammars,
+  );
 
   /// The token stream.
   final TokenCursor cursor;
@@ -20,8 +28,19 @@ final class DefinitionParser {
   /// Schema, type and directive definitions.
   final TypeSystemParser typeSystem;
 
+  /// Schema and type extensions.
+  final ExtensionParser extensions;
+
+  /// The working-draft and experimental productions, asked in order.
+  final List<DefinitionGrammar> grammars;
+
   /// `Definition`, with graphql-js's messages for a misplaced description.
   Definition definition() {
+    for (final grammar in grammars) {
+      if (grammar.startsDefinition()) {
+        return grammar.definition();
+      }
+    }
     if (cursor.peek(.braceLeft)) {
       return executable.operation();
     }
@@ -46,6 +65,7 @@ final class DefinitionParser {
         'Unexpected description, only GraphQL definitions support '
         'descriptions.',
       ),
+      Token(kind: .name, value: 'extend') => extensions.extension(),
       _ => cursor.unexpected(keyword),
     };
   }
```

Create `packages/typed_graphql/lib/src/language/parser/directive_extension_grammar.dart`:

```dart
import '../ast/type_system_extension.dart';
import 'definition_grammar.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';

/// The working draft's `extend directive @name Directives[Const]`. It is
/// always registered, so that with the option off the parser names the
/// feature (`GQL014`) instead of failing at `directive`.
final class DirectiveExtensionGrammar implements DefinitionGrammar {
  /// Creates the grammar; [isEnabled] mirrors
  /// `ParserOptions.allowDirectiveExtensions`.
  DirectiveExtensionGrammar(
    this.cursor,
    this.directives, {
    required this.isEnabled,
  });

  /// The token stream.
  final TokenCursor cursor;

  /// The directive productions.
  final DirectiveParser directives;

  /// Whether directive extensions are accepted.
  final bool isEnabled;

  @override
  bool startsDefinition() {
    if (!cursor.peekKeyword('extend')) {
      return false;
    }
    final keyword = cursor.lookahead();
    return keyword.kind == .name && keyword.value == 'directive';
  }

  @override
  DirectiveExtension definition() {
    final extend = cursor.token;
    cursor.expectKeyword('extend');
    cursor.expectKeyword('directive');
    if (!isEnabled) {
      // Past `directive`, so recovery does not resume at it as a definition.
      cursor.fail(
        .workingDraftFeatureDisabled,
        'Directive extensions are a working-draft feature; enable them '
        'with ParserOptions.allowDirectiveExtensions.',
        at: extend,
      );
    }
    cursor.expect(.at);
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    if (directiveList.isEmpty) {
      cursor.unexpected();
    }
    return DirectiveExtension(
      name,
      directives: directiveList,
      start: extend.start,
      end: cursor.lastEnd,
    );
  }
}
```

Create `packages/typed_graphql/lib/src/language/parser/extension_parser.dart`:

```dart
import '../ast/node.dart';
import '../ast/type_system_extension.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'type_member_parser.dart';

/// Parses `extend` definitions of the schema and of types (spec §3.3.2,
/// §3.4.3): the parts of the matching definition, at least one present.
final class ExtensionParser {
  /// Creates a parser reading from [cursor].
  ExtensionParser(this.cursor, this.directives, this.members);

  /// The token stream.
  final TokenCursor cursor;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The shared members of types.
  final TypeMemberParser members;

  /// The extension that `extend` at the cursor starts; the keyword after
  /// it says which.
  TypeSystemExtension extension() {
    final keyword = cursor.lookahead();
    return switch ((keyword.kind, keyword.value)) {
      (.name, 'schema') => _schema(),
      (.name, 'scalar') => _scalar(),
      (.name, 'type') => _object(),
      (.name, 'interface') => _interface(),
      (.name, 'union') => _union(),
      (.name, 'enum') => _enum(),
      (.name, 'input') => _inputObject(),
      _ => cursor.unexpected(keyword),
    };
  }

  SchemaExtension _schema() {
    final start = _extend('schema');
    final directiveList = directives.directives(isConst: true);
    final operationTypes = cursor.optionalMany(
      .braceLeft,
      members.operationType,
      .braceRight,
    );
    _requireAny([directiveList, operationTypes]);
    return SchemaExtension(
      directives: directiveList,
      operationTypes: operationTypes,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ScalarTypeExtension _scalar() {
    final start = _extend('scalar');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    _requireAny([directiveList]);
    return ScalarTypeExtension(
      name,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ObjectTypeExtension _object() {
    final start = _extend('type');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    _requireAny([interfaces, directiveList, fields]);
    return ObjectTypeExtension(
      name,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InterfaceTypeExtension _interface() {
    final start = _extend('interface');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    _requireAny([interfaces, directiveList, fields]);
    return InterfaceTypeExtension(
      name,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  UnionTypeExtension _union() {
    final start = _extend('union');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final types = members.unionMembers();
    _requireAny([directiveList, types]);
    return UnionTypeExtension(
      name,
      directives: directiveList,
      types: types,
      start: start,
      end: cursor.lastEnd,
    );
  }

  EnumTypeExtension _enum() {
    final start = _extend('enum');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final values = members.enumValues();
    _requireAny([directiveList, values]);
    return EnumTypeExtension(
      name,
      directives: directiveList,
      values: values,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InputObjectTypeExtension _inputObject() {
    final start = _extend('input');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final fields = members.inputFields();
    _requireAny([directiveList, fields]);
    return InputObjectTypeExtension(
      name,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// Consumes `extend` and [keyword]; returns where the extension starts.
  int _extend(String keyword) {
    final start = cursor.token.start;
    cursor.expectKeyword('extend');
    cursor.expectKeyword(keyword);
    return start;
  }

  /// Fails at the current token when every part is absent: an extension
  /// that adds nothing is a syntax error, as in graphql-js.
  void _requireAny(List<List<Node>> parts) {
    if (parts.every((part) => part.isEmpty)) {
      cursor.unexpected();
    }
  }
}
```

In `packages/typed_graphql/lib/src/language/parser/parser.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,8 +7,10 @@ import '../ast/type_ref.dart';
 import '../ast/value.dart';
 import '../lexer/lexer.dart';
 import 'definition_parser.dart';
+import 'directive_extension_grammar.dart';
 import 'directive_parser.dart';
 import 'executable_parser.dart';
+import 'extension_parser.dart';
 import 'parse_element_result.dart';
 import 'parse_result.dart';
 import 'parser_options.dart';
@@ -80,10 +82,25 @@ final class Parser {
       allowsEmpty: options.allowEmptySelectionSets,
     );
     final members = TypeMemberParser(cursor, values, directives);
+    final allowsDirectiveExtensions = options.allowDirectiveExtensions;
     return DefinitionParser(
       cursor,
       ExecutableParser(cursor, values, directives, selections),
-      TypeSystemParser(cursor, values, directives, members),
+      TypeSystemParser(
+        cursor,
+        values,
+        directives,
+        members,
+        allowsDirectiveExtensions: allowsDirectiveExtensions,
+      ),
+      ExtensionParser(cursor, directives, members),
+      [
+        DirectiveExtensionGrammar(
+          cursor,
+          directives,
+          isEnabled: allowsDirectiveExtensions,
+        ),
+      ],
     );
   }
 
```

Replace `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart` whole with:

```dart
import '../ast/directive.dart';
import '../ast/name.dart';
import '../ast/type_system_definition.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'type_member_parser.dart';
import 'value_parser.dart';

/// Parses schema, type and directive definitions (spec §3).
final class TypeSystemParser {
  /// Creates a parser reading from [cursor].
  TypeSystemParser(
    this.cursor,
    this.values,
    this.directives,
    this.members, {
    required this.allowsDirectiveExtensions,
  });

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The shared members of types.
  final TypeMemberParser members;

  /// Whether a directive definition may carry directives and name the
  /// `DIRECTIVE_DEFINITION` location (working draft).
  final bool allowsDirectiveExtensions;

  /// The keywords that start a type-system definition.
  static const Set<String> keywords = {
    'schema',
    'scalar',
    'type',
    'interface',
    'union',
    'enum',
    'input',
    'directive',
  };

  /// The working draft's location for directives on a directive
  /// definition.
  static const String directiveDefinitionLocation = 'DIRECTIVE_DEFINITION';

  /// The September2025 directive locations (spec §3.13).
  static const Set<String> locations = {
    'QUERY',
    'MUTATION',
    'SUBSCRIPTION',
    'FIELD',
    'FRAGMENT_DEFINITION',
    'FRAGMENT_SPREAD',
    'INLINE_FRAGMENT',
    'VARIABLE_DEFINITION',
    'SCHEMA',
    'SCALAR',
    'OBJECT',
    'FIELD_DEFINITION',
    'ARGUMENT_DEFINITION',
    'INTERFACE',
    'UNION',
    'ENUM',
    'ENUM_VALUE',
    'INPUT_OBJECT',
    'INPUT_FIELD_DEFINITION',
  };

  /// The definition that [keyword], one of [keywords], starts, after an
  /// optional description.
  TypeSystemDefinition definition(String keyword) => switch (keyword) {
    'schema' => _schema(),
    'scalar' => _scalar(),
    'type' => _object(),
    'interface' => _interface(),
    'union' => _union(),
    'enum' => _enum(),
    'input' => _inputObject(),
    'directive' => _directive(),
    _ => throw ArgumentError.value(keyword, 'keyword', 'not in keywords'),
  };

  SchemaDefinition _schema() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('schema');
    final directiveList = directives.directives(isConst: true);
    final operationTypes = cursor.many(
      .braceLeft,
      members.operationType,
      .braceRight,
    );
    return SchemaDefinition(
      description: description,
      directives: directiveList,
      operationTypes: operationTypes,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ScalarTypeDefinition _scalar() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('scalar');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    return ScalarTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ObjectTypeDefinition _object() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('type');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    return ObjectTypeDefinition(
      name,
      description: description,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InterfaceTypeDefinition _interface() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('interface');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    return InterfaceTypeDefinition(
      name,
      description: description,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  UnionTypeDefinition _union() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('union');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final types = members.unionMembers();
    return UnionTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      types: types,
      start: start,
      end: cursor.lastEnd,
    );
  }

  EnumTypeDefinition _enum() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('enum');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final enumValues = members.enumValues();
    return EnumTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      values: enumValues,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InputObjectTypeDefinition _inputObject() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('input');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final fields = members.inputFields();
    return InputObjectTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  DirectiveDefinition _directive() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('directive');
    cursor.expect(.at);
    final name = cursor.name();
    final arguments = members.arguments();
    final directiveList = _directivesOfDirective();
    final isRepeatable = cursor.expectOptionalKeyword('repeatable');
    cursor.expectKeyword('on');
    final locations = cursor.delimitedMany(.pipe, _location);
    return DirectiveDefinition(
      name,
      description: description,
      arguments: arguments,
      directives: directiveList,
      isRepeatable: isRepeatable,
      locations: locations,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// The working draft's `Directives[Const]?` of a directive definition.
  List<Directive> _directivesOfDirective() {
    if (cursor.peek(.at) && !allowsDirectiveExtensions) {
      cursor.fail(
        .workingDraftFeatureDisabled,
        'Directives on a directive definition are a working-draft feature; '
        'enable them with ParserOptions.allowDirectiveExtensions.',
      );
    }
    return directives.directives(isConst: true);
  }

  /// `DirectiveLocation`: one of [locations], or the working draft's
  /// [directiveDefinitionLocation].
  Name _location() {
    final token = cursor.token;
    final name = cursor.name();
    if (name.value == directiveDefinitionLocation) {
      if (!allowsDirectiveExtensions) {
        cursor.fail(
          .workingDraftFeatureDisabled,
          'The $directiveDefinitionLocation location is a working-draft '
          'feature; enable it with ParserOptions.allowDirectiveExtensions.',
          at: token,
        );
      }
    } else if (!locations.contains(name.value)) {
      cursor.unexpected(token);
    }
    return name;
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_extension_test.dart)
```

Expected: `+14: All tests passed!`

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -111,6 +111,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `}`; both only at the bracket `balance` where the failed part started,
   and always consume a token. A selection set left empty fails too.
   Type-system definitions and extensions share `TypeMemberParser`.
+  `DefinitionGrammar` is the internal extension point for working-draft and
+  experimental productions (R1.4): `DefinitionParser` asks each registered
+  grammar before the base ones. `DirectiveExtensionGrammar` is always
+  registered; with `allowDirectiveExtensions` off, it and the directive
+  definition's draft parts report `GQL014` instead of a generic error.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/language/parser/definition_grammar.dart packages/typed_graphql/lib/src/language/parser/definition_parser.dart packages/typed_graphql/lib/src/language/parser/directive_extension_grammar.dart packages/typed_graphql/lib/src/language/parser/extension_parser.dart packages/typed_graphql/lib/src/language/parser/parser.dart packages/typed_graphql/lib/src/language/parser/type_system_parser.dart packages/typed_graphql/test/language/parser/parse_extension_test.dart
git commit -q -m "feat(typed_graphql): parse type system extensions and working-draft grammar"
```

### Task 12: Printer

A port of graphql-js's `print` (R1.10), to the character, including the 80-column wrapping. The foreign nodes in `print_type_system_test.dart` import `src/language/ast/child_reader.dart`, which the core's own tests may do.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/printer/executable_printer.dart`, `packages/typed_graphql/lib/src/language/printer/extension_printer.dart`, `packages/typed_graphql/lib/src/language/printer/print_layout.dart`, `packages/typed_graphql/lib/src/language/printer/printer.dart`, `packages/typed_graphql/lib/src/language/printer/quoted_string.dart`, `packages/typed_graphql/lib/src/language/printer/type_member_printer.dart`, `packages/typed_graphql/lib/src/language/printer/type_system_printer.dart`, `packages/typed_graphql/lib/src/language/printer/value_printer.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/printer/print_executable_test.dart`, `packages/typed_graphql/test/language/printer/print_type_system_test.dart`

**Interfaces:**
- Consumes: Tasks 2–4: every node; Task 5: `BlockString.print`.
- Produces:
  - `final class Printer` (`const Printer()`) with `String print(Node node)`. A node class the library does not define throws `ArgumentError`;
  - internal `PrintLayout` (`join`, `wrap`, `indent`, `block`, `hasMultilineItems`, `withArguments`, `argumentDefinitions`) and `QuotedString().print(value)`, a port of `printString`;
  - internal `ValuePrinter`, `ExecutablePrinter(values)`, `TypeMemberPrinter(values)`, `TypeSystemPrinter(values, members)` and `ExtensionPrinter(values, members)`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/printer/print_executable_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const printer = Printer();

  String reprint(String text, {ParserOptions? options}) => printer.print(
    Parsed(text, options: options ?? const ParserOptions()).document,
  );

  group('executable definitions', () {
    test('prints an anonymous query as the shorthand', () {
      expect(reprint('query { id }'), '{\n  id\n}');
    });

    test('prints an operation with variables, directives and selections', () {
      const text =
          r'query Q($a: Int = 1 @d, $b: [String!]!) @op '
          '{ alias: f(x: 1) @skip(if: true) { ...F ... on T { a } '
          r'... @include(if: $a) { b } } }';
      expect(
        reprint(text),
        'query Q(\$a: Int = 1 @d, \$b: [String!]!) @op {\n'
        '  alias: f(x: 1) @skip(if: true) {\n'
        '    ...F\n'
        '    ... on T {\n'
        '      a\n'
        '    }\n'
        '    ... @include(if: \$a) {\n'
        '      b\n'
        '    }\n'
        '  }\n'
        '}',
      );
    });

    test('prints a described fragment', () {
      expect(
        reprint('"F" fragment F on T @d { a }'),
        '"F"\nfragment F on T @d {\n  a\n}',
      );
    });

    test('puts variables on separate lines when one has a description', () {
      expect(
        reprint(r'query Q("d" $a: Int, $b: Int) { a }'),
        'query Q(\n"d"\n\$a: Int\n\$b: Int\n) {\n  a\n}',
      );
    });

    test('wraps arguments that pass 80 columns', () {
      final text =
          '{ field(argument1: "${'a' * 30}", argument2: "${'b' * 30}") }';
      expect(
        reprint(text),
        '{\n'
        '  field(\n'
        '    argument1: "${'a' * 30}"\n'
        '    argument2: "${'b' * 30}"\n'
        '  )\n'
        '}',
      );
    });

    test('prints an empty selection set as braces', () {
      const drafts = ParserOptions(allowEmptySelectionSets: true);
      expect(reprint('{ a { } }', options: drafts), '{\n  a {}\n}');
    });
  });

  group('values', () {
    test('prints every scalar value', () {
      expect(
        reprint(r'{ f(a: 1, b: 1.5e3, c: true, d: null, e: E, g: $v) }'),
        '{\n  f(a: 1, b: 1.5e3, c: true, d: null, e: E, g: \$v)\n}',
      );
    });

    test('escapes a quoted string as graphql-js does', () {
      expect(
        printer.print(const StringValue('a"\\\n\u0001\u007f\u{1F600}')),
        r'"a\"\\\n\u0001\u007F'
        '\u{1F600}"',
      );
    });

    test('prints a block string with BlockString', () {
      expect(
        printer.print(const StringValue('a\nb', isBlock: true)),
        '"""\na\nb\n"""',
      );
    });

    test('wraps a list value that passes 80 columns', () {
      final item = '"${'x' * 30}"';
      expect(
        printer.print(Parsed('{ f(a: [$item, $item, $item]) }').document),
        contains('[\n      $item\n      $item\n      $item\n    ]'),
      );
    });

    test('puts a long object value in a block', () {
      final item = '"${'x' * 30}"';
      final source = Source('{a: $item, b: $item, c: $item}');
      final value = switch (const Parser().parseValue(source)) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };
      expect(printer.print(value), '{\n  a: $item\n  b: $item\n  c: $item\n}');
    });
  });
}
```

Create `packages/typed_graphql/test/language/printer/print_type_system_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/language/ast/child_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const printer = Printer();
  const drafts = ParserOptions(allowDirectiveExtensions: true);

  String reprint(String text) =>
      printer.print(Parsed(text, options: drafts).document);

  group('definitions', () {
    test('prints a described object type with multiline arguments', () {
      const text =
          '"""Type""" type T implements A & B @d '
          '{ "f" f("arg" a: Int = 1 @e): String! g(a: Int, b: [Int]): T }';
      expect(
        reprint(text),
        '"""Type"""\n'
        'type T implements A & B @d {\n'
        '  "f"\n'
        '  f(\n'
        '    "arg"\n'
        '    a: Int = 1 @e\n'
        '  ): String!\n'
        '  g(a: Int, b: [Int]): T\n'
        '}',
      );
    });

    test('prints every other kind of definition', () {
      const definitions = [
        'schema @d {\n  query: Q\n  mutation: M\n}',
        'scalar S @d',
        'interface I implements J {\n  a: Int\n}',
        'union U @d = A | B',
        'enum E {\n  A @d\n  B\n}',
        'input I {\n  a: Int = 1\n}',
        'directive @d(a: Int) @e repeatable on FIELD | DIRECTIVE_DEFINITION',
      ];
      expect(
        reprint(definitions.join(' ')),
        definitions.join('\n\n'),
      );
    });
  });

  group('extensions', () {
    test('prints every kind of extension', () {
      const extensions = [
        'extend schema @d {\n  query: Q\n}',
        'extend scalar S @d',
        'extend type T implements A {\n  a: Int\n}',
        'extend interface I @d',
        'extend union U = A',
        'extend enum E {\n  A\n}',
        'extend input I {\n  a: Int\n}',
        'extend directive @d @e',
      ];
      expect(reprint(extensions.join(' ')), extensions.join('\n\n'));
    });
  });

  group('foreign nodes', () {
    test('a node this library does not define is an argument error', () {
      expect(() => printer.print(_ForeignNode()), throwsArgumentError);
    });

    test('a definition this library does not define is an argument error', () {
      expect(
        () => printer.print(Document([_ForeignDefinition()])),
        throwsArgumentError,
      );
    });
  });
}

/// A node that only a user of the library could define.
final class _ForeignNode extends Node {
  @override
  List<Node> get children => const [];

  @override
  Node rebuildFrom(ChildReader read) => this;
}

/// A definition that only a user of the library could define.
final class _ForeignDefinition extends Definition {
  @override
  List<Node> get children => const [];

  @override
  Node rebuildFrom(ChildReader read) => this;
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/printer/print_executable_test.dart test/language/printer/print_type_system_test.dart)
```

Expected: FAIL to compile: `Method not found: 'Printer'`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/language/printer/executable_printer.dart`:

```dart
import '../ast/executable_definition.dart';
import '../ast/selection.dart';
import '../ast/selection_set.dart';
import '../ast/type_ref.dart';
import '../ast/variable_definition.dart';
import 'print_layout.dart';
import 'value_printer.dart';

/// Prints operations, fragments and selections as graphql-js does.
final class ExecutablePrinter {
  /// Creates a printer that prints values with [values].
  const ExecutablePrinter(this.values);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  static const PrintLayout _layout = PrintLayout();

  /// An operation or a fragment.
  String definition(ExecutableDefinition definition) => switch (definition) {
    OperationDefinition() => _operation(definition),
    FragmentDefinition() => _fragment(definition),
  };

  /// A selection set, one selection per line. An empty one, which only
  /// the working draft parses, prints as `{}` so it parses back.
  String selectionSet(SelectionSet set) => set.selections.isEmpty
      ? '{}'
      : _layout.block(set.selections.map(selection));

  /// A field, a fragment spread or an inline fragment.
  String selection(Selection selection) => switch (selection) {
    Field() => _field(selection),
    FragmentSpread(:final name, :final directives) =>
      '...${name.value}${_layout.wrap(' ', values.directives(directives))}',
    InlineFragment(:final typeCondition, :final directives) => _layout.join([
      '...',
      _layout.wrap('on ', _typeName(typeCondition)),
      values.directives(directives),
      selectionSet(selection.selectionSet),
    ], ' '),
  };

  /// `$name: Type = default @directives`, after its description.
  String variableDefinition(VariableDefinition definition) {
    final description = values.description(definition.description);
    final variable = values.value(definition.variable);
    final type = values.typeRef(definition.type);
    final defaultValue = _layout.wrap(' = ', _defaultValue(definition));
    final directives = values.directives(definition.directives);
    return '$description$variable: $type$defaultValue'
        '${_layout.wrap(' ', directives)}';
  }

  String _operation(OperationDefinition operation) {
    final variables = operation.variableDefinitions
        .map(variableDefinition)
        .toList();
    final variableList = _layout.hasMultilineItems(variables)
        ? _layout.wrap('(\n', _layout.join(variables, '\n'), '\n)')
        : _layout.wrap('(', _layout.join(variables, ', '), ')');
    final prefix =
        values.description(operation.description) +
        _layout.join([
          operation.operation.name,
          _layout.join([operation.name?.value ?? '', variableList]),
          values.directives(operation.directives),
        ], ' ');
    // graphql-js: an anonymous query with nothing else prints as `{ ... }`.
    final head = prefix == 'query' ? '' : '$prefix ';
    return head + selectionSet(operation.selectionSet);
  }

  String _fragment(FragmentDefinition fragment) =>
      '${values.description(fragment.description)}'
      'fragment ${fragment.name.value} '
      'on ${fragment.typeCondition.name.value} '
      '${_layout.wrap('', values.directives(fragment.directives), ' ')}'
      '${selectionSet(fragment.selectionSet)}';

  String _field(Field field) {
    final prefix =
        _layout.wrap('', field.alias?.value, ': ') + field.name.value;
    final arguments = field.arguments.map(values.argument).toList();
    final set = field.selectionSet;
    return _layout.withArguments(prefix, arguments) +
        _layout.wrap(' ', values.directives(field.directives)) +
        (set == null ? '' : ' ${selectionSet(set)}');
  }

  String? _defaultValue(VariableDefinition definition) {
    final value = definition.defaultValue;
    return value == null ? null : values.value(value);
  }

  static String? _typeName(NamedType? type) => type?.name.value;
}
```

Create `packages/typed_graphql/lib/src/language/printer/extension_printer.dart`:

```dart
import '../ast/type_system_extension.dart';
import 'print_layout.dart';
import 'type_member_printer.dart';
import 'value_printer.dart';

/// Prints schema, type and directive extensions as graphql-js does.
final class ExtensionPrinter {
  /// Creates a printer over [values] and [members].
  const ExtensionPrinter(this.values, this.members);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  /// The shared members of types.
  final TypeMemberPrinter members;

  static const PrintLayout _layout = PrintLayout();

  /// An extension: `extend`, the keyword and the parts it adds.
  String extension(TypeSystemExtension extension) => _layout.join([
    'extend ${_keyword(extension)}',
    ?_name(extension),
    if (extension case ObjectTypeExtension(:final interfaces))
      members.interfaces(interfaces),
    if (extension case InterfaceTypeExtension(:final interfaces))
      members.interfaces(interfaces),
    values.directives(extension.directives),
    _body(extension),
  ], ' ');

  String _body(TypeSystemExtension extension) => switch (extension) {
    SchemaExtension(:final operationTypes) => members.operationTypes(
      operationTypes,
    ),
    ScalarTypeExtension() || DirectiveExtension() => '',
    ObjectTypeExtension(:final fields) => members.fields(fields),
    InterfaceTypeExtension(:final fields) => members.fields(fields),
    UnionTypeExtension(:final types) => members.unionMembers(types),
    EnumTypeExtension(:final values) => members.enumValues(values),
    InputObjectTypeExtension(:final fields) => members.inputFields(fields),
  };

  static String? _name(TypeSystemExtension extension) => switch (extension) {
    SchemaExtension() => null,
    DirectiveExtension(:final name) => '@${name.value}',
    TypeExtension(:final name) => name.value,
  };

  static String _keyword(TypeSystemExtension extension) => switch (extension) {
    SchemaExtension() => 'schema',
    DirectiveExtension() => 'directive',
    ScalarTypeExtension() => 'scalar',
    ObjectTypeExtension() => 'type',
    InterfaceTypeExtension() => 'interface',
    UnionTypeExtension() => 'union',
    EnumTypeExtension() => 'enum',
    InputObjectTypeExtension() => 'input',
  };
}
```

Create `packages/typed_graphql/lib/src/language/printer/print_layout.dart`:

```dart
/// graphql-js's printer combinators, so printed text matches it to the
/// character: joining that skips empty parts, wrapping, indentation,
/// blocks and the 80-column rule for argument lists.
final class PrintLayout {
  /// Creates the combinators; they keep no state.
  const PrintLayout();

  /// The longest argument list or list value kept on one line.
  static const int maxLineLength = 80;

  /// The non-empty [parts] joined with [separator].
  String join(Iterable<String> parts, [String separator = '']) =>
      parts.where((part) => part.isNotEmpty).join(separator);

  /// [text] between [start] and [end], or `''` when [text] is null or
  /// empty.
  String wrap(String start, String? text, [String end = '']) =>
      text == null || text.isEmpty ? '' : '$start$text$end';

  /// [text] with every line indented by two spaces.
  String indent(String text) => wrap('  ', text.replaceAll('\n', '\n  '));

  /// [items] one per line, indented, between braces; `''` for none.
  String block(Iterable<String> items) =>
      wrap('{\n', indent(join(items, '\n')), '\n}');

  /// Whether any of [items] spans several lines.
  bool hasMultilineItems(Iterable<String> items) =>
      items.any((item) => item.contains('\n'));

  /// [prefix] and its [arguments] in parentheses, one per line when the
  /// line would pass [maxLineLength].
  String withArguments(String prefix, List<String> arguments) {
    final line = prefix + wrap('(', join(arguments, ', '), ')');
    if (line.length <= maxLineLength) {
      return line;
    }
    return prefix + wrap('(\n', indent(join(arguments, '\n')), '\n)');
  }

  /// An `ArgumentsDefinition`: one per line when any of [arguments]
  /// spans several lines, such as one with a description.
  String argumentDefinitions(List<String> arguments) =>
      hasMultilineItems(arguments)
      ? wrap('(\n', indent(join(arguments, '\n')), '\n)')
      : wrap('(', join(arguments, ', '), ')');
}
```

Create `packages/typed_graphql/lib/src/language/printer/printer.dart`:

```dart
import '../ast/argument.dart';
import '../ast/definition.dart';
import '../ast/directive.dart';
import '../ast/document.dart';
import '../ast/enum_value_definition.dart';
import '../ast/executable_definition.dart';
import '../ast/field_definition.dart';
import '../ast/input_value_definition.dart';
import '../ast/name.dart';
import '../ast/node.dart';
import '../ast/object_field.dart';
import '../ast/operation_type_definition.dart';
import '../ast/selection.dart';
import '../ast/selection_set.dart';
import '../ast/type_ref.dart';
import '../ast/type_system_definition.dart';
import '../ast/type_system_extension.dart';
import '../ast/value.dart';
import '../ast/variable_definition.dart';
import 'executable_printer.dart';
import 'extension_printer.dart';
import 'type_member_printer.dart';
import 'type_system_printer.dart';
import 'value_printer.dart';

/// Prints a syntax tree as GraphQL text (R1.10), character for character
/// as graphql-js's `print`.
///
/// Parsing the output gives a tree equivalent to the input.
final class Printer {
  /// Creates a printer.
  const Printer();

  static const ValuePrinter _values = ValuePrinter();
  static const ExecutablePrinter _executable = ExecutablePrinter(_values);
  static const TypeMemberPrinter _members = TypeMemberPrinter(_values);
  static const TypeSystemPrinter _typeSystem = TypeSystemPrinter(
    _values,
    _members,
  );
  static const ExtensionPrinter _extensions = ExtensionPrinter(
    _values,
    _members,
  );

  /// [node] as GraphQL text. Throws an [ArgumentError] for a [Node]
  /// subclass this library does not define.
  String print(Node node) => switch (node) {
    Document(:final definitions) => definitions.map(_definition).join('\n\n'),
    Definition() => _definition(node),
    SelectionSet() => _executable.selectionSet(node),
    Selection() => _executable.selection(node),
    VariableDefinition() => _executable.variableDefinition(node),
    Value() => _values.value(node),
    TypeRef() => _values.typeRef(node),
    Argument() => _values.argument(node),
    ObjectField() => _values.objectField(node),
    Directive() => _values.directive(node),
    Name(:final value) => value,
    FieldDefinition() => _members.field(node),
    InputValueDefinition() => _members.inputValue(node),
    EnumValueDefinition() => _members.enumValue(node),
    OperationTypeDefinition() => _members.operationType(node),
    _ => throw ArgumentError.value(node, 'node', 'is not a GraphQL node'),
  };

  String _definition(Definition definition) => switch (definition) {
    ExecutableDefinition() => _executable.definition(definition),
    TypeSystemDefinition() => _typeSystem.definition(definition),
    TypeSystemExtension() => _extensions.extension(definition),
    _ => throw ArgumentError.value(
      definition,
      'definition',
      'is not a GraphQL definition',
    ),
  };
}
```

Create `packages/typed_graphql/lib/src/language/printer/quoted_string.dart`:

```dart
/// A string value as a quoted GraphQL string, escaped as graphql-js's
/// `printString` does: control characters, `"`, `\` and U+007F–U+009F.
final class QuotedString {
  /// Creates the printer; it keeps no state.
  const QuotedString();

  /// [value] between double quotes, escaped.
  String print(String value) {
    final buffer = StringBuffer('"');
    for (final unit in value.codeUnits) {
      final escape = _escape(unit);
      if (escape == null) {
        buffer.writeCharCode(unit);
      } else {
        buffer.write(escape);
      }
    }
    buffer.write('"');
    return buffer.toString();
  }

  static String? _escape(int unit) => switch (unit) {
    0x08 => r'\b',
    0x09 => r'\t',
    0x0a => r'\n',
    0x0c => r'\f',
    0x0d => r'\r',
    0x22 => r'\"',
    0x5c => r'\\',
    < 0x20 || (>= 0x7f && <= 0x9f) =>
      '\\u${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}',
    _ => null,
  };
}
```

Create `packages/typed_graphql/lib/src/language/printer/type_member_printer.dart`:

```dart
import '../ast/enum_value_definition.dart';
import '../ast/field_definition.dart';
import '../ast/input_value_definition.dart';
import '../ast/operation_type_definition.dart';
import '../ast/type_ref.dart';
import 'print_layout.dart';
import 'value_printer.dart';

/// Prints the members that type definitions and extensions share:
/// fields, input values, enum values, root operation types and the lists
/// they form.
final class TypeMemberPrinter {
  /// Creates a printer that prints values with [values].
  const TypeMemberPrinter(this.values);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  static const PrintLayout _layout = PrintLayout();

  /// `implements A & B`; `''` for none.
  String interfaces(List<NamedType> interfaces) => _layout.wrap(
    'implements ',
    _layout.join(interfaces.map(values.typeRef), ' & '),
  );

  /// `= A | B`; `''` for none.
  String unionMembers(List<NamedType> types) =>
      _layout.wrap('= ', _layout.join(types.map(values.typeRef), ' | '));

  /// `{ field ... }` of an object or interface; `''` for none.
  String fields(List<FieldDefinition> fields) =>
      _layout.block(fields.map(field));

  /// `{ input ... }` of an input object; `''` for none.
  String inputFields(List<InputValueDefinition> fields) =>
      _layout.block(fields.map(inputValue));

  /// `{ VALUE ... }` of an enum; `''` for none.
  String enumValues(List<EnumValueDefinition> enumValues) =>
      _layout.block(enumValues.map(enumValue));

  /// `{ query: Query ... }` of a schema; `''` for none.
  String operationTypes(List<OperationTypeDefinition> types) =>
      _layout.block(types.map(operationType));

  /// `(input ...)` of a field or a directive; `''` for none.
  String argumentDefinitions(List<InputValueDefinition> arguments) =>
      _layout.argumentDefinitions(arguments.map(inputValue).toList());

  /// `query: Query`.
  String operationType(OperationTypeDefinition definition) =>
      '${definition.operation.name}: ${values.typeRef(definition.type)}';

  /// A field definition, after its description.
  String field(FieldDefinition field) {
    final description = values.description(field.description);
    final arguments = argumentDefinitions(field.arguments);
    final type = values.typeRef(field.type);
    final directives = values.directives(field.directives);
    return '$description${field.name.value}$arguments: $type'
        '${_layout.wrap(' ', directives)}';
  }

  /// An argument or input field definition, after its description.
  String inputValue(InputValueDefinition value) {
    final defaultValue = value.defaultValue;
    return values.description(value.description) +
        _layout.join([
          '${value.name.value}: ${values.typeRef(value.type)}',
          if (defaultValue != null) '= ${values.value(defaultValue)}',
          values.directives(value.directives),
        ], ' ');
  }

  /// An enum value definition, after its description.
  String enumValue(EnumValueDefinition value) =>
      values.description(value.description) +
      _layout.join([
        value.name.value,
        values.directives(value.directives),
      ], ' ');
}
```

Create `packages/typed_graphql/lib/src/language/printer/type_system_printer.dart`:

```dart
import '../ast/type_system_definition.dart';
import 'print_layout.dart';
import 'type_member_printer.dart';
import 'value_printer.dart';

/// Prints schema, type and directive definitions as graphql-js does.
final class TypeSystemPrinter {
  /// Creates a printer over [values] and [members].
  const TypeSystemPrinter(this.values, this.members);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  /// The shared members of types.
  final TypeMemberPrinter members;

  static const PrintLayout _layout = PrintLayout();

  /// A definition, its description on the line before it.
  String definition(TypeSystemDefinition definition) =>
      values.description(definition.description) +
      switch (definition) {
        SchemaDefinition(:final directives, :final operationTypes) =>
          _layout.join([
            'schema',
            values.directives(directives),
            members.operationTypes(operationTypes),
          ], ' '),
        DirectiveDefinition() => _directive(definition),
        TypeDefinition() => _type(definition),
      };

  String _type(TypeDefinition type) {
    final head = [
      _keyword(type),
      type.name.value,
      if (type case ObjectTypeDefinition(:final interfaces))
        members.interfaces(interfaces),
      if (type case InterfaceTypeDefinition(:final interfaces))
        members.interfaces(interfaces),
      values.directives(type.directives),
    ];
    final body = switch (type) {
      ScalarTypeDefinition() => '',
      ObjectTypeDefinition(:final fields) => members.fields(fields),
      InterfaceTypeDefinition(:final fields) => members.fields(fields),
      UnionTypeDefinition(:final types) => members.unionMembers(types),
      EnumTypeDefinition(:final values) => members.enumValues(values),
      InputObjectTypeDefinition(:final fields) => members.inputFields(fields),
    };
    return _layout.join([...head, body], ' ');
  }

  String _directive(DirectiveDefinition directive) =>
      'directive @${directive.name.value}'
      '${members.argumentDefinitions(directive.arguments)}'
      '${_layout.wrap(' ', values.directives(directive.directives))}'
      '${directive.isRepeatable ? ' repeatable' : ''}'
      ' on ${directive.locations.map((location) => location.value).join(' | ')}';

  static String _keyword(TypeDefinition type) => switch (type) {
    ScalarTypeDefinition() => 'scalar',
    ObjectTypeDefinition() => 'type',
    InterfaceTypeDefinition() => 'interface',
    UnionTypeDefinition() => 'union',
    EnumTypeDefinition() => 'enum',
    InputObjectTypeDefinition() => 'input',
  };
}
```

Create `packages/typed_graphql/lib/src/language/printer/value_printer.dart`:

```dart
import '../ast/argument.dart';
import '../ast/directive.dart';
import '../ast/object_field.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/block_string.dart';
import 'print_layout.dart';
import 'quoted_string.dart';

/// Prints values, type references, arguments and directives: the parts
/// every definition shares.
final class ValuePrinter {
  /// Creates the printer; it keeps no state.
  const ValuePrinter();

  static const PrintLayout _layout = PrintLayout();

  /// A value; a list or object value too long for one line is wrapped.
  String value(Value value) => switch (value) {
    Variable(:final name) => '\$${name.value}',
    IntValue(:final value) || FloatValue(:final value) => value,
    StringValue(:final value, isBlock: true) => const BlockString().print(
      value,
    ),
    StringValue(:final value) => const QuotedString().print(value),
    BooleanValue(:final value) => '$value',
    NullValue() => 'null',
    EnumValue(:final value) => value,
    ListValue(:final values) => _list(values.map(this.value).toList()),
    ObjectValue(:final fields) => _object(fields.map(objectField).toList()),
  };

  /// A type reference, such as `[String!]!`.
  String typeRef(TypeRef type) => switch (type) {
    NamedType(:final name) => name.value,
    ListType(:final type) => '[${typeRef(type)}]',
    NonNullType(:final type) => '${typeRef(type)}!',
  };

  /// `name: value` of an argument.
  String argument(Argument argument) =>
      '${argument.name.value}: ${value(argument.value)}';

  /// `name: value` of an input object field.
  String objectField(ObjectField field) =>
      '${field.name.value}: ${value(field.value)}';

  /// `@name(arguments)`.
  String directive(Directive directive) {
    final arguments = _layout.join(directive.arguments.map(argument), ', ');
    return '@${directive.name.value}${_layout.wrap('(', arguments, ')')}';
  }

  /// [directives] separated by spaces; `''` for none.
  String directives(List<Directive> directives) =>
      _layout.join(directives.map(directive), ' ');

  /// A description on its own line before a definition; `''` for none.
  String description(StringValue? description) =>
      description == null ? '' : '${value(description)}\n';

  String _list(List<String> values) {
    final line = '[${_layout.join(values, ', ')}]';
    return line.length > PrintLayout.maxLineLength
        ? '[\n${_layout.indent(_layout.join(values, '\n'))}\n]'
        : line;
  }

  String _object(List<String> fields) {
    final line = '{ ${_layout.join(fields, ', ')} }';
    return line.length > PrintLayout.maxLineLength
        ? _layout.block(fields)
        : line;
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/printer/print_executable_test.dart test/language/printer/print_type_system_test.dart)
```

Expected: `print_executable_test.dart` `+11`, `print_type_system_test.dart` `+5`, each `All tests passed!`

- [ ] **Step 5: Update the barrel and the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -116,6 +116,12 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   grammar before the base ones. `DirectiveExtensionGrammar` is always
   registered; with `allowDirectiveExtensions` off, it and the directive
   definition's draft parts report `GQL014` instead of a generic error.
+- `printer/`: `Printer` prints any node as graphql-js's `print` does, to
+  the character (80-column wrapping included), through collaborators:
+  `ValuePrinter` (values, types, arguments, directives), `ExecutablePrinter`,
+  `TypeMemberPrinter`, `TypeSystemPrinter`, `ExtensionPrinter`, over the
+  `PrintLayout` combinators (`join`, `wrap`, `indent`, `block`) and
+  `QuotedString`. An empty selection set prints as `{}`.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/enum_value_definition.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/field_definition.dart';
export 'src/language/ast/input_value_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/operation_type_definition.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/type_system_definition.dart';
export 'src/language/ast/type_system_extension.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/language/lexer/block_string.dart';
export 'src/language/lexer/lexer.dart';
export 'src/language/lexer/token.dart';
export 'src/language/lexer/token_kind.dart';
export 'src/language/parser/graphql_syntax_exception.dart';
export 'src/language/parser/parse_element_result.dart';
export 'src/language/parser/parse_result.dart';
export 'src/language/parser/parser.dart';
export 'src/language/parser/parser_options.dart';
export 'src/language/printer/printer.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/printer/executable_printer.dart packages/typed_graphql/lib/src/language/printer/extension_printer.dart packages/typed_graphql/lib/src/language/printer/print_layout.dart packages/typed_graphql/lib/src/language/printer/printer.dart packages/typed_graphql/lib/src/language/printer/quoted_string.dart packages/typed_graphql/lib/src/language/printer/type_member_printer.dart packages/typed_graphql/lib/src/language/printer/type_system_printer.dart packages/typed_graphql/lib/src/language/printer/value_printer.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/printer/print_executable_test.dart packages/typed_graphql/test/language/printer/print_type_system_test.dart
git commit -q -m "feat(typed_graphql): print syntax trees as graphql-js does"
```

### Task 13: Minified printing and parse-print stability

**Files:**
- Create: `packages/typed_graphql/lib/src/language/printer/minifier.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/language/printer/printer.dart`
- Test: `packages/typed_graphql/test/language/printer/print_minified_test.dart`

**Interfaces:**
- Consumes: Task 12: `Printer`; Tasks 6–7: `Lexer` (with `maxTokens: null`); Task 2: `isEquivalentTo`.
- Produces:
  - `const Printer({bool isMinified = false})`. Minified output is the canonical text without ignored tokens: a space only between two non-punctuators or before `...`, and block strings in their shortest form;
  - internal `Minifier().minify(String text)`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/printer/print_minified_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const drafts = ParserOptions(
    allowDirectiveExtensions: true,
    allowEmptySelectionSets: true,
  );

  String minify(String text) =>
      const Printer(isMinified: true).print(Parsed(text).document);

  group('minified', () {
    test('drops whitespace and commas between punctuators', () {
      expect(
        minify(r'query Q($a: Int) { a(x: 1, y: "s") { ...F } }'),
        r'query Q($a:Int){a(x:1 y:"s"){...F}}',
      );
    });

    test('keeps one space between names and before a spread', () {
      expect(minify('{ a ...F }'), '{a ...F}');
    });

    test('prints block strings in their shortest form', () {
      expect(
        minify('"""\n  a\n  b\n""" type T { f: Int }'),
        '"""a\nb""" type T{f:Int}',
      );
    });
  });

  group('parse, print, parse', () {
    const text =
        r'"Q" query Q("v" $a: [Int!] = [1] @d) @op { alias: f(x: {a: "s"}) '
        '{ ...F ... on T @d { a } b { } } } '
        'fragment F on T { c } '
        'schema { query: Q } '
        '"""Long\n  description""" type T implements A & B @d '
        '{ "f" f("arg" a: Int = 1): String! } '
        'directive @d(a: Int) @e repeatable on FIELD | DIRECTIVE_DEFINITION '
        'extend type T @d extend directive @d @e';
    final original = Parsed(text, options: drafts).document;

    test('canonical output parses to an equivalent tree', () {
      final printed = const Printer().print(original);
      final reparsed = Parsed(printed, options: drafts).document;
      expect(reparsed.isEquivalentTo(original), isTrue);
    });

    test('minified output parses to an equivalent tree', () {
      final printed = const Printer(isMinified: true).print(original);
      final reparsed = Parsed(printed, options: drafts).document;
      expect(reparsed.isEquivalentTo(original), isTrue);
    });

    test('canonical output is stable when printed again', () {
      final printed = const Printer().print(original);
      final reparsed = Parsed(printed, options: drafts).document;
      expect(const Printer().print(reparsed), printed);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/printer/print_minified_test.dart)
```

Expected: FAIL to compile: `No named parameter with the name 'isMinified'`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/language/printer/minifier.dart`:

```dart
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../lexer/block_string.dart';
import '../lexer/lexer.dart';
import '../lexer/token.dart';
import '../lexer/token_kind.dart';

/// Removes insignificant characters from GraphQL text as graphql-js's
/// `stripIgnoredCharacters` does: no whitespace, commas or comments, a
/// space only between two tokens that would merge, and block strings
/// printed in their shortest form.
final class Minifier {
  /// Creates the minifier; it keeps no state.
  const Minifier();

  /// [text] without its ignored tokens.
  String minify(String text) {
    final lexer = Lexer(Source(text), DiagnosticSink(), maxTokens: null);
    final buffer = StringBuffer();
    var wasNonPunctuator = false;
    for (
      var token = lexer.advance();
      token.kind != TokenKind.eof;
      token = lexer.advance()
    ) {
      final isNonPunctuator = !token.kind.isPunctuator;
      // `1...` would lex as a bad number, so a spread is separated too.
      if (wasNonPunctuator && (isNonPunctuator || token.kind == .spread)) {
        buffer.write(' ');
      }
      buffer.write(switch (token) {
        Token(kind: .blockString, :final value?) => const BlockString().print(
          value,
          isMinified: true,
        ),
        _ => text.substring(token.start, token.end),
      });
      wasNonPunctuator = isNonPunctuator;
    }
    return buffer.toString();
  }
}
```

In `packages/typed_graphql/lib/src/language/printer/printer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -19,17 +19,22 @@ import '../ast/value.dart';
 import '../ast/variable_definition.dart';
 import 'executable_printer.dart';
 import 'extension_printer.dart';
+import 'minifier.dart';
 import 'type_member_printer.dart';
 import 'type_system_printer.dart';
 import 'value_printer.dart';
 
-/// Prints a syntax tree as GraphQL text (R1.10), character for character
-/// as graphql-js's `print`.
+/// Prints a syntax tree as GraphQL text (R1.10): canonically, character for
+/// character as graphql-js's `print`, or minified, with no insignificant
+/// characters, for the wire and for persisted-query hashes.
 ///
 /// Parsing the output gives a tree equivalent to the input.
 final class Printer {
-  /// Creates a printer.
-  const Printer();
+  /// Creates a printer; [isMinified] selects the minified form.
+  const Printer({this.isMinified = false});
+
+  /// Whether the output has no insignificant characters.
+  final bool isMinified;
 
   static const ValuePrinter _values = ValuePrinter();
   static const ExecutablePrinter _executable = ExecutablePrinter(_values);
@@ -45,7 +50,12 @@ final class Printer {
 
   /// [node] as GraphQL text. Throws an [ArgumentError] for a [Node]
   /// subclass this library does not define.
-  String print(Node node) => switch (node) {
+  String print(Node node) {
+    final canonical = _canonical(node);
+    return isMinified ? const Minifier().minify(canonical) : canonical;
+  }
+
+  String _canonical(Node node) => switch (node) {
     Document(:final definitions) => definitions.map(_definition).join('\n\n'),
     Definition() => _definition(node),
     SelectionSet() => _executable.selectionSet(node),
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/printer/print_minified_test.dart)
```

Expected: `+6: All tests passed!`

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -122,6 +122,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `TypeMemberPrinter`, `TypeSystemPrinter`, `ExtensionPrinter`, over the
   `PrintLayout` combinators (`join`, `wrap`, `indent`, `block`) and
   `QuotedString`. An empty selection set prints as `{}`.
+  `Printer(isMinified: true)` passes the canonical text through `Minifier`
+  (graphql-js's `stripIgnoredCharacters`: a space only between two
+  non-punctuators or before `...`, block strings in their shortest form).
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

Replace `packages/typed_graphql/CHANGELOG.md` whole with:

```markdown
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
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/printer/minifier.dart packages/typed_graphql/lib/src/language/printer/printer.dart packages/typed_graphql/test/language/printer/print_minified_test.dart
git commit -q -m "feat(typed_graphql): print minified text and check parse-print stability"
```

### Task 14: Hostile input

These tests pin behaviour that Tasks 6–11 built, at the scale of an attack (Review Focus 1, 2, 3 and 5). They pass on the first run; Task 19 also runs them with dart2js and dart2wasm.

**Files:**
- Test: `packages/typed_graphql/test/language/parser/hostile_input_test.dart`

**Interfaces:**
- Consumes: Task 9: `Parsed`; Tasks 6–11: the lexer and the parser.
- Produces:
  - no new code; the tests named in Review Focus 1, 2, 3 and 5.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/language/parser/hostile_input_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  group('limits (R1.6)', () {
    test('a selection set 100 000 levels deep gives one depth error', () {
      const depth = 100000;
      final text = '${'{a' * depth}${'}' * depth}';
      final parsed = Parsed(
        text,
        options: const ParserOptions(maxTokens: null),
      );
      expect(parsed.errors, [
        '1:257 GQL010 Document nests deeper than 128 levels.',
      ]);
    });

    test('the token limit stops a long document with one error', () {
      final parsed = Parsed('{ ${'a ' * 20000}}');
      expect(
        parsed.result.diagnostics.single.code,
        DiagnosticCode.tokenLimitExceeded,
      );
    });

    test('the sink stops after maxErrors errors with GQL000', () {
      final parsed = Parsed('{ a } ! ' * 300);
      final codes = parsed.result.diagnostics.map(
        (diagnostic) => diagnostic.code,
      );
      expect(codes, hasLength(DiagnosticSink.defaultMaxErrors + 1));
      expect(codes.last, DiagnosticCode.diagnosticLimitReached);
    });
  });

  group('unterminated input gives one error and ends', () {
    test('in a string argument', () {
      expect(Parsed('{ a(b: "x').errors, ['1:10 GQL004 Unterminated string.']);
    });

    test('in a block string', () {
      expect(Parsed('"""abc').errors, ['1:7 GQL004 Unterminated string.']);
    });

    test('in nested selection sets', () {
      expect(Parsed('{ a { b ').errors, [
        '1:9 GQL007 Expected Name, found <EOF>.',
      ]);
    });

    test('in an argument definition list', () {
      expect(Parsed('type T { f(a: Int').errors, [
        '1:18 GQL007 Expected Name, found <EOF>.',
      ]);
    });
  });

  group('values', () {
    test('an integer past 64 bits keeps its raw lexeme', () {
      const lexeme = '123456789012345678901234567890';
      final value = switch (const Parser().parseValue(Source(lexeme))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };
      expect(
        value,
        isA<IntValue>().having((literal) => literal.value, 'value', lexeme),
      );
    });

    test('a lone surrogate in a selection is one error', () {
      expect(Parsed('{ a \uD800 b }').errors, [
        '1:5 GQL002 Invalid character: U+D800.',
      ]);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/hostile_input_test.dart)
```

Expected: `+9: All tests passed!`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql/test/language/parser/hostile_input_test.dart
git commit -q -m "test(typed_graphql): pin parser limits and hostile input"
```

### Task 15: Conformance mapping table and its check

The table of R0.7 and R10.3, and the test that keeps it honest. `GraphqlJsSuite` reads a Prettier-formatted graphql-js test file: the indentation of a line tells which `describe` holds it.

**Files:**
- Create: `.gitattributes`, `packages/typed_graphql_conformance/LICENSE-graphql-js`, `packages/typed_graphql_conformance/mapping/language.csv`
- Modify: `CLAUDE.md`, `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/README.md`, `packages/typed_graphql_conformance/pubspec.yaml`
- Test: `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/csv_table.dart`, `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`, `packages/typed_graphql_conformance/test/support_test.dart`

**Interfaces:**
- Consumes: The conformance package skeleton from M1.
- Produces:
  - `mapping/language.csv`, with the header `graphql_js_file,group,test,status,dart_file,reason`;
  - test code:
    - `CsvTable.parse(text)`, an RFC 4180 reader, with `header` and `rows` (`List<Map<String, String>>`);
    - `GraphqlJsSuite.read(file)` / `.parse(source)`, with `tests` (`List<(String, String)>`, the group path and the name), `directory` and `isAvailable`;
    - `mapping_test.dart`: documented columns, a known status, a reason for `adapted` and `skipped`, unique keys, and a named Dart file holding the `group` and `test`. It also has a coverage check for each file in `portedFiles`, which starts empty.
  - The conformance pubspec depends on `typed_graphql` only.
  - `LICENSE-graphql-js` and `.gitattributes`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql_conformance/test/mapping_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/csv_table.dart';
import 'support/graphql_js_suite.dart';

/// The graphql-js language test files whose every test has a row (R10.3).
/// A port task adds its file here with its rows.
const Set<String> portedFiles = {};

void main() {
  final table = CsvTable.parse(
    File('mapping/language.csv').readAsStringSync(),
  );

  test('has the documented columns', () {
    expect(table.header, [
      'graphql_js_file',
      'group',
      'test',
      'status',
      'dart_file',
      'reason',
    ]);
  });

  test('every row has a known status', () {
    for (final row in table.rows) {
      expect(row['status'], isIn(['ported', 'adapted', 'skipped']));
    }
  });

  test('adapted and skipped rows give a reason', () {
    for (final row in table.rows.where((row) => row['status'] != 'ported')) {
      expect(row['reason'], isNotEmpty, reason: '$row');
    }
  });

  test('no graphql-js test has two rows', () {
    final keys = [
      for (final row in table.rows)
        (row['graphql_js_file'], row['group'], row['test']),
    ];
    expect(keys.toSet(), hasLength(keys.length));
  });

  test('ported and adapted rows name a Dart test that exists', () {
    // `name(` and the quoted argument, with any whitespace between: the
    // formatter moves a long name to its own line.
    RegExp call(String name, String argument) =>
        RegExp('$name\\(\\s*${RegExp.escape("'$argument'")}');
    for (final row in table.rows.where((row) => row['status'] != 'skipped')) {
      final file = File('${row['dart_file']}');
      expect(file.existsSync(), isTrue, reason: '$row');
      final text = file.readAsStringSync();
      for (final group in '${row['group']}'.split(' > ')) {
        expect(text, contains(call('group', group)), reason: '$row');
      }
      expect(text, contains(call('test', '${row['test']}')), reason: '$row');
    }
  });

  group('rows cover every test of', () {
    for (final file in portedFiles) {
      test(file, skip: !GraphqlJsSuite.isAvailable, () {
        final mapped = {
          for (final row in table.rows)
            if (row['graphql_js_file'] == file) (row['group'], row['test']),
        };
        expect(mapped, GraphqlJsSuite.read(file).tests.toSet());
      });
    }
  });
}
```

Create `packages/typed_graphql_conformance/test/support/csv_table.dart`:

```dart
/// A CSV text with a header row, read as RFC 4180: a quoted field may
/// hold commas, line breaks and doubled quotes; `\r\n` ends a record too.
final class CsvTable {
  /// Reads [text]; the first record is the header.
  factory CsvTable.parse(String text) {
    final records = _records(text);
    if (records.isEmpty) {
      throw const FormatException('A CSV table needs a header row.');
    }
    final [header, ...body] = records;
    return CsvTable._(header, [
      for (final record in body)
        {
          for (var i = 0; i < header.length; i++)
            header[i]: i < record.length ? record[i] : '',
        },
    ]);
  }

  CsvTable._(this.header, this.rows);

  /// The column names.
  final List<String> header;

  /// Every record after the header, by column name.
  final List<Map<String, String>> rows;

  static List<List<String>> _records(String text) {
    final records = <List<String>>[];
    var record = <String>[];
    final field = StringBuffer();
    var isQuoted = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (isQuoted) {
        if (char != '"') {
          field.write(char);
        } else if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          isQuoted = false;
        }
        continue;
      }
      if (char == '\r') {
        continue;
      }
      switch (char) {
        case '"':
          isQuoted = true;
        case ',':
          record.add('$field');
          field.clear();
        case '\n':
          record.add('$field');
          field.clear();
          records.add(record);
          record = <String>[];
        default:
          field.write(char);
      }
    }
    if (field.isNotEmpty || record.isNotEmpty) {
      record.add('$field');
      records.add(record);
    }
    return records;
  }
}
```

Create `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`:

```dart
import 'dart:io';

/// The tests of one graphql-js test file in `reference/` (fetched by
/// `tool/fetch_reference.sh`, absent in CI): each `it` with the path of
/// the `describe` blocks around it, joined by ` > `.
final class GraphqlJsSuite {
  /// Reads `src/language/__tests__/[file]` of the fetched graphql-js.
  factory GraphqlJsSuite.read(String file) =>
      GraphqlJsSuite.parse(File('$directory/$file').readAsStringSync());

  /// Finds the tests in [source], a graphql-js test file formatted by
  /// Prettier: a block's indentation says which `describe` holds it.
  factory GraphqlJsSuite.parse(String source) {
    final groups = <(int, String)>[];
    final tests = <(String, String)>[];
    for (final line in source.split('\n')) {
      final match = _block.firstMatch(line);
      if (match?.groups([1, 2, 3]) case [
        final indent?,
        final kind?,
        final name?,
      ]) {
        groups.removeWhere((group) => group.$1 >= indent.length);
        if (kind == 'describe') {
          groups.add((indent.length, name));
        } else {
          tests.add((groups.map((group) => group.$2).join(' > '), name));
        }
      }
    }
    return GraphqlJsSuite._(tests);
  }

  GraphqlJsSuite._(this.tests);

  /// The language tests of graphql-js, relative to a package directory.
  static const String directory =
      '../../reference/graphql-js/src/language/__tests__';

  /// Whether graphql-js was fetched into `reference/`.
  static bool get isAvailable => Directory(directory).existsSync();

  static final RegExp _block = RegExp(r"^(\s*)(describe|it)\('([^']*)'");

  /// Each test as its group path and its name, in file order.
  final List<(String, String)> tests;
}
```

Create `packages/typed_graphql_conformance/test/support_test.dart`:

```dart
import 'package:test/test.dart';

import 'support/csv_table.dart';
import 'support/graphql_js_suite.dart';

void main() {
  group('CsvTable', () {
    test('reads quoted fields with commas, quotes and CRLF', () {
      final table = CsvTable.parse(
        'a,b\r\n"x, y","say ""hi"""\r\n',
      );
      expect(table.rows, [
        {'a': 'x, y', 'b': 'say "hi"'},
      ]);
    });

    test('fills missing trailing fields with empty strings', () {
      expect(CsvTable.parse('a,b\nx').rows, [
        {'a': 'x', 'b': ''},
      ]);
    });
  });

  group('GraphqlJsSuite', () {
    test('names each test with the describe blocks around it', () {
      const source = '''
describe('Parser', () => {
  it('parses', () => {});
  describe('parseValue', () => {
    it('parses null value', () => {});
  });
  it('limits', () => {});
});
describe('isPunctuatorTokenKind', () => {
  it('returns true', () => {});
});
''';
      expect(GraphqlJsSuite.parse(source).tests, [
        ('Parser', 'parses'),
        ('Parser > parseValue', 'parses null value'),
        ('Parser', 'limits'),
        ('isPunctuatorTokenKind', 'returns true'),
      ]);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart test/support_test.dart)
```

Expected: FAIL. `mapping_test.dart` fails to load: `Cannot open file, path = 'mapping/language.csv'`. `support_test.dart` passes (`+3`): its support classes are test code and came in Step 1.

- [ ] **Step 3: Write the implementation**

Create `.gitattributes`:

```text
# Test sources hold multi-line literals whose line ends are data.
* text=auto eol=lf
```

Create `packages/typed_graphql_conformance/LICENSE-graphql-js`:

```text
MIT License

Copyright (c) GraphQL Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Create `packages/typed_graphql_conformance/mapping/language.csv`:

```csv
graphql_js_file,group,test,status,dart_file,reason
```

In `packages/typed_graphql_conformance/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,11 +8,6 @@ environment:
 
 dependencies:
   typed_graphql: any
-  typed_graphql_builder: any
-  typed_graphql_client: any
-  typed_graphql_codegen: any
-  typed_graphql_server: any
-  typed_graphql_shelf: any
 
 dev_dependencies:
   test: ^1.31.0
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart test/support_test.dart)
```

Expected: `mapping_test.dart` `+5`, `support_test.dart` `+3`, each `All tests passed!`

- [ ] **Step 5: Check that the table check bites**

Append the row `lexer-test.ts,Lexer,no such test,ported,test/language/lexer_test.dart,` to `mapping/language.csv`, then run `(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)`.

Expected: `ported and adapted rows name a Dart test that exists` fails. Remove the row again.

With `reference/` fetched, add `'lexer-test.ts'` to `portedFiles` and run the same command.

Expected: `rows cover every test of lexer-test.ts` fails and lists the missing tests. Restore the empty set.

Afterwards `git status --short` lists only this task's files.

- [ ] **Step 6: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -256,4 +256,6 @@ fails when it finds none.
   and its scanners).
 - Core layer test: `packages/typed_graphql/test/quality/layers_test.dart`.
 - Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
+- Conformance mapping table: `packages/typed_graphql_conformance/mapping/language.csv`,
+  checked by `test/mapping_test.dart` there; port helpers in its `test/support/`.
 - CI: `.github/workflows/ci.yml`.
```

Replace `packages/typed_graphql_conformance/CHANGELOG.md` whole with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- Depends on `typed_graphql` only.
- `mapping/language.csv`, the conformance mapping table, and the test that
  checks it.
```

Replace `packages/typed_graphql_conformance/README.md` whole with:

```markdown
# typed_graphql_conformance

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-tool-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**Repository tool of typed_graphql: ported graphql-js suites, fuzzers and benchmarks. Never published.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** Stage M2 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)
> ports the graphql-js language suites; nothing is exported.

## Ported suites

Tests under `test/language/` are ported from graphql-js 17
(`reference/graphql-js`, fetched by `tool/fetch_reference.sh`), one Dart test
per graphql-js test, with the same group and test names.
`mapping/language.csv` records each graphql-js test:

| Column | Meaning |
|---|---|
| `graphql_js_file` | the file in `src/language/__tests__/`, such as `lexer-test.ts` |
| `group` | the `describe` blocks around the test, joined by ` > ` |
| `test` | the `it` name |
| `status` | `ported` (same assertions), `adapted` (a deliberate design difference changes them) or `skipped` (behaviour this library does not have) |
| `dart_file` | the Dart test file, relative to this package; empty when skipped |
| `reason` | why, for `adapted` and `skipped` |

`test/mapping_test.dart` checks the table; with `reference/` fetched it also
checks that every test of a ported file has a row.

## License

MIT — see [LICENSE](LICENSE). The ported tests derive from graphql-js,
MIT, Copyright (c) GraphQL Contributors — see
[LICENSE-graphql-js](LICENSE-graphql-js).
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add .gitattributes CLAUDE.md packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/LICENSE-graphql-js packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/mapping/language.csv packages/typed_graphql_conformance/pubspec.yaml packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/csv_table.dart packages/typed_graphql_conformance/test/support/graphql_js_suite.dart packages/typed_graphql_conformance/test/support_test.dart
git commit -q -m "test(typed_graphql_conformance): add the language mapping table and its check"
```

### Task 16: Port lexer-test.ts and blockString-test.ts

**How a graphql-js test is ported.** This applies to Tasks 16–18.

1. **Source.** The tests come from `reference/graphql-js/src/language/__tests__/<file>`: graphql-js 17.0.2, commit `ee5ce41`, fetched by `tool/fetch_reference.sh`. Port **every** `it` of each file the task names, in file order, one Dart test per graphql-js test.
2. **Names.** Each Dart file starts with `// Ported from graphql-js src/language/__tests__/<file>; see` and `// mapping/language.csv.`
   - Each `describe` becomes a `group` with the same name and the same nesting. Each `it` becomes a `test` whose name is copied verbatim.
   - A test goes into the Dart file that its row in the table names. A suite that would pass 500 lines is split, and every part repeats the `group` wrappers of its tests: the table check searches the named file for `group('<segment>'` and `test('<name>'`.
3. **Helpers.** graphql-js's test helpers map to the classes in `test/support/`:

   | graphql-js | Dart |
   |---|---|
   | `lexOne(text)`, `lexSecond(text)` | `LexerPort().lexOne` / `lexSecond`: a map of `kind`, `start`, `end`, `line`, `column`, `value` (`value` is `null` where graphql-js has `undefined`) |
   | `expect(x).to.contain({...})` | `expect(x, contain({...}))` with `const contain = Contain();` |
   | `expect(x).to.deep.equal(y)`, `expectJSON(x).toDeepEqual(y)` | `expect(x, y)` with plain maps and lists |
   | `expectSyntaxError(text)` in the lexer suite | `LexerPort().syntaxError(text)` |
   | `expectSyntaxError(text)` in the parser suites | `ParserPort().syntaxError(text)`: the **first** diagnostic as `{'message': 'Syntax Error: …', 'locations': [{'line': …, 'column': …}]}`. graphql-js throws at its first error, while the Dart parser goes on, so only the first one is compared |
   | `parse(text)` | `ParserPort().document(text)`, which fails the test on any diagnostic; `ParserPort(options: ParserOptions(...))` for parse options |
   | `toJSONDeep(parse(text))` | `ParserPort().parse(text)`, which is `AstJson` (decision 11) |
   | `toDeepNestedProperty('definitions[0].<key>', x)` | `expect(SchemaNodes().firstDefinition(document, '<key>'), x)` |
   | `parseValue`, `parseConstValue`, `parseType` | `ParserPort().parseValue` / `parseConstValue` / `parseType`; their errors: `valueSyntaxError` / `constValueSyntaxError` |
   | `print(ast)` | `const Printer().print(node)` |
   | `printString(s)` | `const Printer().print(StringValue(s))` |
   | `dedentBlockStringLines`, `isPrintableAsBlockString`, `printBlockString(s, { minimize })` | `BlockString().dedentLines` / `isPrintable` / `print(s, isMinified: ...)` |
   | `` dedent`...` `` | `Dedent()('''...''')` |
   | `kitchenSinkQuery`, `kitchenSinkSDL` | `KitchenSink.query`, `KitchenSink.sdl` |
   | the schema-parser node builders (`nameNode`, `typeNode`, …) | `SchemaNodes()` |

   A TypeScript template literal becomes a `'''` string. Make it a raw string (`r'''`) when it holds `\` or `$` that must stay as they are. `` \` `` becomes `` ` ``. A long literal that graphql-js builds with `+` uses adjacent literals in Dart, because the lints reject `+`.
4. **Status.**
   - `ported`: the expectation is transcribed unchanged; helpers are allowed.
   - `adapted`: a deliberate design difference changes the expectation. The Dart test has a `// Adapted: <why>` comment above it, and the row gives the reason.
   - `skipped`: the behaviour does not exist here. There is no Dart test, `dart_file` is empty, and the row gives the reason.

   The rows in the task are final: use their statuses and reasons as they are.
5. **A failing ported expectation is a porting mistake first.** All seven files were ported against this library while this plan was verified, and every expectation passed unchanged. Never weaken an expectation. If the library really differs, stop and report it.
6. **The rows.** The columns are `graphql_js_file,group,test,status,dart_file,reason`. `group` is the `describe` path joined by ` > `. The rows follow graphql-js file order. A field that holds a comma or a quote is quoted, and a quote inside it is doubled (RFC 4180).
7. **Coverage.** When every test of a file has its row, add the file name to `portedFiles` in `test/mapping_test.dart`. The test `rows cover every test of <file>` then compares the rows with the file. It runs only where `reference/` is fetched, which CI does not do, so run it locally.
8. **Code rules.** Test code follows them too:
   - no top-level functions: a helper is a local closure in `main`, or a method of a class in `test/support/`;
   - at most 500 lines per file;
   - raw strings where the lints ask for them;
   - full names, not dot shorthands, in `expect` arguments.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql_conformance/test/language/block_string_test.dart`, `packages/typed_graphql_conformance/test/language/lexer_test.dart`, `packages/typed_graphql_conformance/test/support/contain.dart`, `packages/typed_graphql_conformance/test/support/error_json.dart`, `packages/typed_graphql_conformance/test/support/lexer_port.dart`
- Create, while porting: the rest of the files that the rows of Step 5 name (`test/language/lexer_strings_test.dart`)
- Modify: `packages/typed_graphql_conformance/test/mapping_test.dart` (`portedFiles`)

**Interfaces:**
- Consumes: Task 15: the table and its check; Tasks 5–7: `BlockString`, `Lexer`, `TokenKind`.
- Produces:
  - test helpers:
    - `LexerPort`, with `lexOne`, `lexSecond`, `firstKind`, `kindsWithComments`, `firstComment`, `syntaxError` and `kindOf(TokenKind)` (graphql-js's kind strings);
    - `ErrorJson().of(Diagnostic)`, a `GraphQLError`-shaped map with the `Syntax Error: ` prefix;
    - `Contain()`, a matcher for a subset of a map.
  - Rows: 24 for `lexer-test.ts` (18 ported, 3 adapted, 3 skipped) and 25 for `blockString-test.ts` (all ported).

- [ ] **Step 1: Write the port helpers**

Create `packages/typed_graphql_conformance/test/support/contain.dart`:

```dart
import 'package:test/test.dart';

/// chai's `.to.contain({...})` on an object: every given key has the given
/// value; other keys are ignored.
final class Contain {
  /// Creates the matcher factory.
  const Contain();

  /// A matcher for a map that holds every entry of [expected].
  Matcher call(Map<String, Object?> expected) => allOf([
    for (final MapEntry(:key, :value) in expected.entries)
      containsPair(key, value),
  ]);
}
```

Create `packages/typed_graphql_conformance/test/support/error_json.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// A diagnostic as graphql-js's `GraphQLError` JSON for a syntax error, so a
/// ported `expectSyntaxError(...)` expectation is copied unchanged.
final class ErrorJson {
  /// Creates the converter; it keeps no state.
  const ErrorJson();

  /// `{message: 'Syntax Error: ...', locations: [{line, column}]}`.
  Map<String, Object?> of(Diagnostic diagnostic) {
    final location = diagnostic.span?.location;
    return {
      'message': 'Syntax Error: ${diagnostic.message}',
      'locations': [
        if (location != null)
          {'line': location.line, 'column': location.column},
      ],
    };
  }
}
```

Create `packages/typed_graphql_conformance/test/support/lexer_port.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'error_json.dart';

/// graphql-js's lexer test helpers over [Lexer]: tokens as graphql-js
/// `Token` fields and lexer diagnostics as `GraphQLError` JSON.
final class LexerPort {
  /// Creates the helpers; they keep no state.
  const LexerPort();

  /// The first token of [text]: `lexOne`.
  Map<String, Object?> lexOne(String text) => _tokens(text, 1).last;

  /// The second token of [text]: `lexSecond`.
  Map<String, Object?> lexSecond(String text) => _tokens(text, 2).last;

  /// The kind of the first token of [text].
  TokenKind firstKind(String text) =>
      Lexer(Source(text), DiagnosticSink()).advance().kind;

  /// Every token of [text] up to the end, comments included, as graphql-js
  /// kinds (`<EOF>` last).
  List<String> kindsWithComments(String text) {
    final lexer = Lexer(Source(text), DiagnosticSink(), keepComments: true);
    final kinds = <String>[];
    for (var token = lexer.advance(); ; token = lexer.advance()) {
      kinds.add(kindOf(token.kind));
      if (token.kind == TokenKind.eof) {
        return kinds;
      }
    }
  }

  /// The first comment token of [text]: graphql-js reads it as
  /// `lexOne(text).prev`.
  Map<String, Object?> firstComment(String text) {
    final source = Source(text);
    final lexer = Lexer(source, DiagnosticSink(), keepComments: true);
    return _json(source, lexer.advance());
  }

  /// The first diagnostic of lexing two tokens of [text]:
  /// `expectSyntaxError`, which throws at the first error.
  Map<String, Object?> syntaxError(String text) {
    final sink = DiagnosticSink();
    final lexer = Lexer(Source(text), sink);
    lexer
      ..advance()
      ..advance();
    return const ErrorJson().of(sink.diagnostics.first);
  }

  /// [kind] as graphql-js's `TokenKind` value, such as `Name` or `{`.
  String kindOf(TokenKind kind) => kind.isPunctuator
      ? kind.description.replaceAll('"', '')
      : kind.description;

  List<Map<String, Object?>> _tokens(String text, int count) {
    final source = Source(text);
    final lexer = Lexer(source, DiagnosticSink());
    return [for (var i = 0; i < count; i++) _json(source, lexer.advance())];
  }

  Map<String, Object?> _json(Source source, Token token) {
    final location = source.locationOf(token.start);
    return {
      'kind': kindOf(token.kind),
      'start': token.start,
      'end': token.end,
      'line': location.line,
      'column': location.column,
      'value': token.value,
    };
  }
}
```

- [ ] **Step 2: Write the worked examples**

Each file starts with the first tests of its suite; Step 4 adds the rest.

Create `packages/typed_graphql_conformance/test/language/block_string_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/blockString-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const blockString = BlockString();

  group('dedentBlockStringLines', () {
    List<String> dedent(List<String> lines) => blockString.dedentLines(lines);

    test('removes minimal indentation length', () {
      expect(dedent(['', ' a', '  b']), ['a', ' b']);
      expect(dedent(['', '  a', ' b']), [' a', 'b']);
      expect(dedent(['', '  a', ' b', 'c']), ['  a', ' b', 'c']);
    });
  });

  group('printBlockString', () {
    void expectBlockString(String value, String readable, [String? minimize]) {
      expect(blockString.print(value), readable);
      expect(blockString.print(value, isMinified: true), minimize ?? readable);
    }

    test(
      'by default print block strings ending with triple quotation as multi-line',
      () {
        expectBlockString(
          'triple quotation """',
          '"""\ntriple quotation \\"""\n"""',
          r'"""triple quotation \""""""',
        );
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/language/lexer_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/lexer-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../support/contain.dart';
import '../support/lexer_port.dart';

void main() {
  const port = LexerPort();
  const contain = Contain();

  group('Lexer', () {
    test('ignores BOM header', () {
      expect(
        port.lexOne('\uFEFF foo'),
        contain({'kind': 'Name', 'start': 2, 'end': 5, 'value': 'foo'}),
      );
    });

    test('lex reports useful information for dashes in names', () {
      expect(
        port.lexOne('a-b'),
        contain({'kind': 'Name', 'start': 0, 'end': 1, 'value': 'a'}),
      );
      expect(port.syntaxError('a-b'), {
        'message': 'Syntax Error: Invalid number, expected digit but got: "b".',
        'locations': [
          {'line': 1, 'column': 3},
        ],
      });
    });

    test('lexes comments', () {
      expect(
        port.firstComment('# Comment'),
        contain({
          'kind': 'Comment',
          'start': 0,
          'end': 9,
          'value': ' Comment',
        }),
      );
      expect(
        port.firstComment('# Comment\nAnother line'),
        contain({
          'kind': 'Comment',
          'start': 0,
          'end': 9,
          'value': ' Comment',
        }),
      );
      expect(
        port.firstComment('# Comment\r\nAnother line'),
        contain({
          'kind': 'Comment',
          'start': 0,
          'end': 9,
          'value': ' Comment',
        }),
      );
      expect(
        port.firstComment('# Comment \u{1f600}'),
        contain({
          'kind': 'Comment',
          'start': 0,
          'end': 12,
          'value': ' Comment \u{1f600}',
        }),
      );
      expect(port.syntaxError('# Invalid surrogate \uDEAD'), {
        'message': 'Syntax Error: Invalid character: U+DEAD.',
        'locations': [
          {'line': 1, 'column': 21},
        ],
      });
    });
  });

  group('isPunctuatorTokenKind', () {
    bool isPunctuatorToken(String text) => port.firstKind(text).isPunctuator;

    test('returns false for non-punctuator tokens', () {
      expect(isPunctuatorToken(''), false);
      expect(isPunctuatorToken('name'), false);
      expect(isPunctuatorToken('1'), false);
      expect(isPunctuatorToken('3.14'), false);
      expect(isPunctuatorToken('"str"'), false);
      expect(isPunctuatorToken('"""str"""'), false);
    });
  });
}
```

- [ ] **Step 3: Run the worked examples**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/block_string_test.dart test/language/lexer_test.dart)
```

Expected: `lexer_test.dart` `+4`, `block_string_test.dart` `+2`, each `All tests passed!`

- [ ] **Step 4: Port every other test of `lexer-test.ts`, `blockString-test.ts`**

Follow the procedure above for every remaining `it` of both files. Put each test in the Dart file that its row in Step 5 names. The five string tests ('lexes strings' to 'lex reports useful block string errors') go into `test/language/lexer_strings_test.dart`, which keeps `lexer_test.dart` under 500 lines.

- `expectToken(text, kind, value)`-style checks become `expect(port.lexOne(text), contain({...}))`.
- 'tracks line breaks' and 'records line and column' read `line` and `column` from `lexOne`.
- 'produces double linked list of tokens, including comments' is adapted. It compares `port.kindsWithComments(text)` with graphql-js's kinds without `<SOF>`, because tokens are not linked.
- 'lexes comments' is adapted. It reads the comment from `Lexer(keepComments: true)` instead of `token.prev`.
- 'errors respect whitespace' is adapted. It compares only the message and the location 3:2, because the source excerpt that graphql-js prints is M2b's `printLocation`.
- The `printBlockString` tests use the local `expectBlockString(value, readable, [minimize])` of the worked example.

- [ ] **Step 5: Write the rows**

Append these rows to `packages/typed_graphql_conformance/mapping/language.csv`, after the rows that are already there. They are final, in graphql-js order, with one row per graphql-js test. The worked examples of Step 2 are among them.

```csv
lexer-test.ts,Lexer,ignores BOM header,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,tracks line breaks,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,records line and column,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,"can be Object.toStringified, JSON.stringified, or jsutils.inspected",skipped,,Dart tokens have no JS inspect/JSON protocol.
lexer-test.ts,Lexer,skips whitespace and comments,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,reports unexpected characters,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,errors respect whitespace,adapted,test/language/lexer_test.dart,The printLocation source excerpt arrives in M2b: only message and location 3:2 are checked.
lexer-test.ts,Lexer,updates line numbers in error for file context,skipped,,Source has no locationOffset.
lexer-test.ts,Lexer,updates column numbers in error for file context,skipped,,Source has no locationOffset.
lexer-test.ts,Lexer,lexes strings,ported,test/language/lexer_strings_test.dart,
lexer-test.ts,Lexer,lex reports useful string errors,ported,test/language/lexer_strings_test.dart,
lexer-test.ts,Lexer,lexes block strings,ported,test/language/lexer_strings_test.dart,
lexer-test.ts,Lexer,advance line after lexing multiline block string,ported,test/language/lexer_strings_test.dart,
lexer-test.ts,Lexer,lex reports useful block string errors,ported,test/language/lexer_strings_test.dart,
lexer-test.ts,Lexer,lexes numbers,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,lex reports useful number errors,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,lex does not allow name-start after a number,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,lexes punctuation,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,lex reports useful unknown character error,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,lex reports useful information for dashes in names,ported,test/language/lexer_test.dart,
lexer-test.ts,Lexer,"produces double linked list of tokens, including comments",adapted,test/language/lexer_test.dart,"Tokens are not linked: token kinds checked with kindsWithComments, which has no <SOF>."
lexer-test.ts,Lexer,lexes comments,adapted,test/language/lexer_test.dart,"Tokens are not linked: the comment comes from Lexer(keepComments: true), not from token.prev."
lexer-test.ts,isPunctuatorTokenKind,returns true for punctuator tokens,ported,test/language/lexer_test.dart,
lexer-test.ts,isPunctuatorTokenKind,returns false for non-punctuator tokens,ported,test/language/lexer_test.dart,
blockString-test.ts,dedentBlockStringLines,handles empty string,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,does not dedent first line,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,removes minimal indentation length,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,dedent both tab and space as single character,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,dedent do not take empty lines into account,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,removes uniform indentation from a string,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,removes empty leading and trailing lines,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,removes blank leading and trailing lines,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,retains indentation from first line,ported,test/language/block_string_test.dart,
blockString-test.ts,dedentBlockStringLines,does not alter trailing spaces,ported,test/language/block_string_test.dart,
blockString-test.ts,isPrintableAsBlockString,accepts valid strings,ported,test/language/block_string_test.dart,
blockString-test.ts,isPrintableAsBlockString,rejects strings with only whitespace,ported,test/language/block_string_test.dart,
blockString-test.ts,isPrintableAsBlockString,rejects strings with non-printable characters,ported,test/language/block_string_test.dart,
blockString-test.ts,isPrintableAsBlockString,rejects strings with only empty lines,ported,test/language/block_string_test.dart,
blockString-test.ts,isPrintableAsBlockString,rejects strings with carriage return,ported,test/language/block_string_test.dart,
blockString-test.ts,isPrintableAsBlockString,rejects strings with leading empty lines,ported,test/language/block_string_test.dart,
blockString-test.ts,isPrintableAsBlockString,rejects strings with trailing empty lines,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,does not escape characters,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,by default print block strings as single line,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,by default print block strings ending with triple quotation as multi-line,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,correctly prints single-line with leading space,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,correctly prints single-line with leading space and trailing quotation,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,correctly prints single-line with trailing backslash,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,correctly prints multi-line with internal indent,ported,test/language/block_string_test.dart,
blockString-test.ts,printBlockString,correctly prints string with a first line indentation,ported,test/language/block_string_test.dart,
```

- [ ] **Step 6: Mark the files as ported**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, add `'lexer-test.ts'` and `'blockString-test.ts'` to `portedFiles`, after the names already there:

```dart
const Set<String> portedFiles = {
  'lexer-test.ts',
  'blockString-test.ts',
};
```

- [ ] **Step 7: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+58: All tests passed!`: 46 ported or adapted tests, 7 table checks, 3 support tests and 2 pubspec tests. Without `reference/` it is `+56` with 2 skipped.

- [ ] **Step 8: Update the changelog**

Replace `packages/typed_graphql_conformance/CHANGELOG.md` whole with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- Depends on `typed_graphql` only.
- `mapping/language.csv`, the conformance mapping table, and the test that
  checks it.
- Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`.
```

- [ ] **Step 9: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 10: Commit**

```sh
git add packages/typed_graphql_conformance
git commit -q -m "test(typed_graphql_conformance): port the graphql-js lexer and block string suites"
```

### Task 17: Port parser-test.ts and schema-parser-test.ts

The procedure is the one in Task 16.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql_conformance/test/language/parser/parser_test.dart`, `packages/typed_graphql_conformance/test/language/parser/parser_values_test.dart`, `packages/typed_graphql_conformance/test/language/parser/schema_parser_definitions_test.dart`, `packages/typed_graphql_conformance/test/language/parser/schema_parser_test.dart`, `packages/typed_graphql_conformance/test/support/ast_json.dart`, `packages/typed_graphql_conformance/test/support/dedent.dart`, `packages/typed_graphql_conformance/test/support/kitchen_sink.dart`, `packages/typed_graphql_conformance/test/support/parser_port.dart`, `packages/typed_graphql_conformance/test/support/schema_nodes.dart`
- Create, while porting: the rest of the files that the rows of Step 5 name (`test/language/parser/parser_ast_test.dart`, `parser_descriptions_test.dart`, `schema_parser_types_test.dart`, `schema_parser_extensions_test.dart`)
- Modify: `packages/typed_graphql_conformance/test/mapping_test.dart` (`portedFiles`)

**Interfaces:**
- Consumes: Task 16: `ErrorJson`, `Contain`, the procedure; Tasks 8–11: `Parser`, `ParserOptions`.
- Produces:
  - test helpers:
    - `AstJson().of(Node?)`, graphql-js's `toJSONDeep` (decision 11);
    - `ParserPort({options})`, with `document`, `parse`, `syntaxError`, `parseValue`, `parseConstValue`, `parseType`, `valueSyntaxError` and `constValueSyntaxError`;
    - `Dedent`, graphql-js's `dedent`;
    - `KitchenSink.query` and `KitchenSink.sdl`;
    - `SchemaNodes`, graphql-js's schema-parser node builders and `firstDefinition`.
  - Rows: 58 for `parser-test.ts` (34 ported, 3 adapted, 21 skipped) and 46 for `schema-parser-test.ts` (44 ported, 2 adapted).

- [ ] **Step 1: Write the port helpers**

Create `packages/typed_graphql_conformance/test/support/ast_json.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// A node as graphql-js's `toJSONDeep` shows it, so a ported AST
/// expectation is copied unchanged: `kind` is graphql-js's `Kind`, `loc` is
/// `{start, end}`, every field graphql-js sets is present, and an absent
/// child or an absent optional list is `null` (graphql-js's `undefined`).
final class AstJson {
  /// Creates the converter; it keeps no state.
  const AstJson();

  /// [node] as graphql-js JSON; `null` for no node.
  Object? of(Node? node) => switch (node) {
    null => null,
    Name(:final value) => _node(node, 'Name', {'value': value}),
    Document(:final definitions) => _node(node, 'Document', {
      'definitions': _all(definitions),
    }),
    Value() => _value(node),
    TypeRef() => _type(node),
    Argument(:final name, :final value) ||
    ObjectField(:final name, :final value) => _node(
      node,
      node is Argument ? 'Argument' : 'ObjectField',
      {
        'name': of(name),
        'value': of(value),
      },
    ),
    Directive(:final name, :final arguments) => _node(node, 'Directive', {
      'name': of(name),
      'arguments': _optional(arguments),
    }),
    ExecutableDefinition() ||
    SelectionSet() ||
    Selection() ||
    VariableDefinition() => _executable(node),
    TypeSystemExtension() => _extension(node),
    _ => _typeSystem(node),
  };

  Map<String, Object?> _node(
    Node node,
    String kind,
    Map<String, Object?> fields,
  ) => {
    'kind': kind,
    'loc': {'start': node.start, 'end': node.end},
    ...fields,
  };

  /// A list graphql-js always sets, such as `ListValue.values`.
  List<Object?> _all(List<Node> nodes) => [for (final node in nodes) of(node)];

  /// A list graphql-js leaves `undefined` when absent, such as `arguments`.
  List<Object?>? _optional(List<Node> nodes) =>
      nodes.isEmpty ? null : _all(nodes);

  Map<String, Object?> _value(Value value) => switch (value) {
    Variable(:final name) => _node(value, 'Variable', {'name': of(name)}),
    IntValue(value: final lexeme) => _node(value, 'IntValue', {
      'value': lexeme,
    }),
    FloatValue(value: final lexeme) => _node(value, 'FloatValue', {
      'value': lexeme,
    }),
    StringValue(value: final text, :final isBlock) => _node(
      value,
      'StringValue',
      {'value': text, 'block': isBlock},
    ),
    BooleanValue(value: final flag) => _node(value, 'BooleanValue', {
      'value': flag,
    }),
    NullValue() => _node(value, 'NullValue', {}),
    EnumValue(value: final name) => _node(value, 'EnumValue', {
      'value': name,
    }),
    ListValue(:final values) => _node(value, 'ListValue', {
      'values': _all(values),
    }),
    ObjectValue(:final fields) => _node(value, 'ObjectValue', {
      'fields': _all(fields),
    }),
  };

  Map<String, Object?> _type(TypeRef type) => switch (type) {
    NamedType(:final name) => _node(type, 'NamedType', {'name': of(name)}),
    ListType(type: final item) => _node(type, 'ListType', {'type': of(item)}),
    NonNullType(type: final item) => _node(type, 'NonNullType', {
      'type': of(item),
    }),
  };

  Map<String, Object?> _executable(Node node) => switch (node) {
    OperationDefinition() => _node(node, 'OperationDefinition', {
      'description': of(node.description),
      'operation': node.operation.name,
      'name': of(node.name),
      'variableDefinitions': _optional(node.variableDefinitions),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    FragmentDefinition() => _node(node, 'FragmentDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'typeCondition': of(node.typeCondition),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    VariableDefinition() => _node(node, 'VariableDefinition', {
      'description': of(node.description),
      'variable': of(node.variable),
      'type': of(node.type),
      'defaultValue': of(node.defaultValue),
      'directives': _optional(node.directives),
    }),
    SelectionSet(:final selections) => _node(node, 'SelectionSet', {
      'selections': _all(selections),
    }),
    Field() => _node(node, 'Field', {
      'alias': of(node.alias),
      'name': of(node.name),
      'arguments': _optional(node.arguments),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    FragmentSpread(:final name, :final directives) => _node(
      node,
      'FragmentSpread',
      {'name': of(name), 'directives': _optional(directives)},
    ),
    InlineFragment() => _node(node, 'InlineFragment', {
      'typeCondition': of(node.typeCondition),
      'directives': _optional(node.directives),
      'selectionSet': of(node.selectionSet),
    }),
    _ => throw ArgumentError.value(node, 'node', 'is not executable'),
  };

  Map<String, Object?> _typeSystem(Node node) => switch (node) {
    SchemaDefinition() => _node(node, 'SchemaDefinition', {
      'description': of(node.description),
      'directives': _optional(node.directives),
      'operationTypes': _all(node.operationTypes),
    }),
    OperationTypeDefinition(:final operation, :final type) => _node(
      node,
      'OperationTypeDefinition',
      {'operation': operation.name, 'type': of(type)},
    ),
    DirectiveDefinition() => _node(node, 'DirectiveDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'arguments': _optional(node.arguments),
      'directives': _optional(node.directives),
      'repeatable': node.isRepeatable,
      'locations': _all(node.locations),
    }),
    TypeDefinition() => _typeDefinition(node),
    FieldDefinition() => _node(node, 'FieldDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'arguments': _optional(node.arguments),
      'type': of(node.type),
      'directives': _optional(node.directives),
    }),
    InputValueDefinition() => _node(node, 'InputValueDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'type': of(node.type),
      'defaultValue': of(node.defaultValue),
      'directives': _optional(node.directives),
    }),
    EnumValueDefinition() => _node(node, 'EnumValueDefinition', {
      'description': of(node.description),
      'name': of(node.name),
      'directives': _optional(node.directives),
    }),
    _ => throw ArgumentError.value(node, 'node', 'is not a GraphQL node'),
  };

  Map<String, Object?> _typeDefinition(TypeDefinition type) => _node(
    type,
    switch (type) {
      ScalarTypeDefinition() => 'ScalarTypeDefinition',
      ObjectTypeDefinition() => 'ObjectTypeDefinition',
      InterfaceTypeDefinition() => 'InterfaceTypeDefinition',
      UnionTypeDefinition() => 'UnionTypeDefinition',
      EnumTypeDefinition() => 'EnumTypeDefinition',
      InputObjectTypeDefinition() => 'InputObjectTypeDefinition',
    },
    {
      'description': of(type.description),
      'name': of(type.name),
      ..._typeParts(type),
    },
  );

  Map<String, Object?> _extension(TypeSystemExtension extension) => _node(
    extension,
    switch (extension) {
      SchemaExtension() => 'SchemaExtension',
      DirectiveExtension() => 'DirectiveExtension',
      ScalarTypeExtension() => 'ScalarTypeExtension',
      ObjectTypeExtension() => 'ObjectTypeExtension',
      InterfaceTypeExtension() => 'InterfaceTypeExtension',
      UnionTypeExtension() => 'UnionTypeExtension',
      EnumTypeExtension() => 'EnumTypeExtension',
      InputObjectTypeExtension() => 'InputObjectTypeExtension',
    },
    switch (extension) {
      SchemaExtension(:final directives, :final operationTypes) => {
        'directives': _optional(directives),
        'operationTypes': _optional(operationTypes),
      },
      DirectiveExtension(:final name) || TypeExtension(:final name) => {
        'name': of(name),
        ..._typeParts(extension),
      },
    },
  );

  /// The fields after the name, in graphql-js's order.
  Map<String, Object?> _typeParts(Node type) => switch (type) {
    ObjectTypeDefinition(:final interfaces, :final directives, :final fields) ||
    InterfaceTypeDefinition(
      :final interfaces,
      :final directives,
      :final fields,
    ) ||
    ObjectTypeExtension(:final interfaces, :final directives, :final fields) ||
    InterfaceTypeExtension(
      :final interfaces,
      :final directives,
      :final fields,
    ) => {
      'interfaces': _optional(interfaces),
      'directives': _optional(directives),
      'fields': _optional(fields),
    },
    UnionTypeDefinition(:final directives, :final types) ||
    UnionTypeExtension(:final directives, :final types) => {
      'directives': _optional(directives),
      'types': _optional(types),
    },
    EnumTypeDefinition(:final directives, :final values) ||
    EnumTypeExtension(:final directives, :final values) => {
      'directives': _optional(directives),
      'values': _optional(values),
    },
    InputObjectTypeDefinition(:final directives, :final fields) ||
    InputObjectTypeExtension(:final directives, :final fields) => {
      'directives': _optional(directives),
      'fields': _optional(fields),
    },
    ScalarTypeDefinition(:final directives) ||
    ScalarTypeExtension(:final directives) ||
    DirectiveExtension(:final directives) => {
      'directives': _optional(directives),
    },
    _ => throw ArgumentError.value(type, 'type', 'has no type parts'),
  };
}
```

Create `packages/typed_graphql_conformance/test/support/dedent.dart`:

```dart
/// graphql-js's `dedent` test tag: drops leading line breaks, trailing
/// blanks and the first line's indentation from every line.
final class Dedent {
  /// Creates the function; it keeps no state.
  const Dedent();

  static final RegExp _leadingBreaks = RegExp(r'^\n*');
  static final RegExp _trailingBlanks = RegExp(r'[ \t\n]*$');
  static final RegExp _indent = RegExp(r'^[ \t]*');

  /// [text] dedented, as `dedentString` does.
  String call(String text) {
    final trimmed = text
        .replaceFirst(_leadingBreaks, '')
        .replaceFirst(_trailingBlanks, '');
    final indent = _indent.stringMatch(trimmed) ?? '';
    final everyIndent = RegExp('^${RegExp.escape(indent)}', multiLine: true);
    return trimmed.replaceAll(everyIndent, '');
  }
}
```

Create `packages/typed_graphql_conformance/test/support/kitchen_sink.dart`:

```dart
/// graphql-js's kitchen-sink documents (`src/__testUtils__/`), which use
/// every part of the grammar.
abstract final class KitchenSink {
  /// `kitchenSinkQuery`. Dart drops the first line break of a multi-line
  /// literal; graphql-js's text starts with one, so it is put back.
  static const String query =
      '\n'
      r'''
"Query description"
query queryName(
  "Very complex variable"
  $foo: ComplexType,
  $site: Site = MOBILE
) @onQuery {
  whoever123is: node(id: [123, 456]) {
    id
    ... on User @onInlineFragment {
      field2 {
        id
        alias: field1(first: 10, after: $foo) @include(if: $foo) {
          id
          ...frag @onFragmentSpread
        }
      }
    }
    ... @skip(unless: $foo) {
      id
    }
    ... {
      id
    }
  }
}

mutation likeStory @onMutation {
  like(story: 123) @onField {
    story {
      id @onField
    }
  }
}

subscription StoryLikeSubscription(
  $input: StoryLikeSubscribeInput @onVariableDefinition
)
  @onSubscription {
  storyLikeSubscribe(input: $input) {
    story {
      likers {
        count
      }
      likeSentence {
        text
      }
    }
  }
}

"""
  Fragment description
"""
fragment frag on Friend @onFragmentDefinition {
  foo(
    size: $size
    bar: $b
    obj: {
      key: "value"
      block: """
      block string uses \"""
      """
    }
  )
}

{
  unnamed(truthy: true, falsy: false, nullish: null)
  query
}

query {
  __typename
}
''';

  /// `kitchenSinkSDL`, which needs `allowDirectiveExtensions`.
  static const String sdl =
      '\n'
      '''
"""This is a description of the schema as a whole."""
schema {
  query: QueryType
  mutation: MutationType
}

"""
This is a description
of the `Foo` type.
"""
type Foo implements Bar & Baz & Two {
  "Description of the `one` field."
  one: Type
  """
  This is a description of the `two` field.
  """
  two(
    """
    This is a description of the `argument` argument.
    """
    argument: InputType!
  ): Type
  """This is a description of the `three` field."""
  three(argument: InputType, other: String): Int
  four(argument: String = "string"): String
  five(argument: [String] = ["string", "string"]): String
  six(argument: InputType = {key: "value"}): Type
  seven(argument: Int = null): Type
  eight(argument: OneOfInputType): Type
}

type AnnotatedObject @onObject(arg: "value") {
  annotatedField(arg: Type = "default" @onArgumentDefinition): Type @onField
}

type UndefinedType

extend type Foo {
  seven(argument: [String]): Type
}

extend type Foo @onType

interface Bar {
  one: Type
  four(argument: String = "string"): String
}

interface AnnotatedInterface @onInterface {
  annotatedField(arg: Type @onArgumentDefinition): Type @onField
}

interface UndefinedInterface

extend interface Bar implements Two {
  two(argument: InputType!): Type
}

extend interface Bar @onInterface

interface Baz implements Bar & Two {
  one: Type
  two(argument: InputType!): Type
  four(argument: String = "string"): String
}

union Feed =
  | Story
  | Article
  | Advert

union AnnotatedUnion @onUnion = A | B

union AnnotatedUnionTwo @onUnion = | A | B

union UndefinedUnion

extend union Feed = Photo | Video

extend union Feed @onUnion

scalar CustomScalar

scalar AnnotatedScalar @onScalar

extend scalar CustomScalar @onScalar

enum Site {
  """
  This is a description of the `DESKTOP` value
  """
  DESKTOP

  """This is a description of the `MOBILE` value"""
  MOBILE

  "This is a description of the `WEB` value"
  WEB
}

enum AnnotatedEnum @onEnum {
  ANNOTATED_VALUE @onEnumValue
  OTHER_VALUE
}

enum UndefinedEnum

extend enum Site {
  VR
}

extend enum Site @onEnum

input InputType {
  key: String!
  answer: Int = 42
}

input OneOfInputType @oneOf {
  string: String
  int: Int
}

input AnnotatedInput @onInputObject {
  annotatedField: Type @onInputFieldDefinition
}

input UndefinedInput

extend input InputType {
  other: Float = 1.23e4 @onInputFieldDefinition
}

extend input InputType @onInputObject

directive @onDirectiveDefinition on DIRECTIVE_DEFINITION

"""
This is a description of the `@skip` directive
"""
directive @skip(
  """This is a description of the `if` argument"""
  if: Boolean! @onArgumentDefinition
) @onDirectiveDefinition on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

directive @include(if: Boolean!)
  on FIELD
   | FRAGMENT_SPREAD
   | INLINE_FRAGMENT

directive @include2(if: Boolean!) on
  | FIELD
  | FRAGMENT_SPREAD
  | INLINE_FRAGMENT

directive @myRepeatableDir(name: String!) repeatable on
  | OBJECT
  | INTERFACE

extend directive @skip @onDirectiveDefinition

extend schema @onSchema

extend schema @onSchema {
  subscription: SubscriptionType
}
''';
}
```

Create `packages/typed_graphql_conformance/test/support/parser_port.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'ast_json.dart';
import 'error_json.dart';

/// graphql-js's parser test helpers over [Parser]: results as graphql-js
/// AST JSON ([AstJson]) and the first diagnostic as `GraphQLError` JSON.
final class ParserPort {
  /// Creates the helpers; [options] stand for graphql-js's parse options.
  const ParserPort({this.options = const ParserOptions()});

  /// The parser options of every call.
  final ParserOptions options;

  Parser get _parser => Parser(options: options);

  /// `parse(text)`, which must succeed; the test fails otherwise.
  Document document(String text) => switch (_parser.parse(Source(text))) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// `toJSONDeep(parse(text))`.
  Object? parse(String text) => const AstJson().of(document(text));

  /// `expectSyntaxError(text)`: the first diagnostic of `parse(text)`.
  Map<String, Object?> syntaxError(String text) =>
      _firstError(_parser.parse(Source(text)).diagnostics);

  /// `toJSONDeep(parseValue(text))`.
  Object? parseValue(String text) =>
      const AstJson().of(_element(_parser.parseValue(Source(text))));

  /// `toJSONDeep(parseConstValue(text))`.
  Object? parseConstValue(String text) => const AstJson().of(
    _element(_parser.parseValue(Source(text), isConst: true)),
  );

  /// `toJSONDeep(parseType(text))`.
  Object? parseType(String text) =>
      const AstJson().of(_element(_parser.parseTypeRef(Source(text))));

  /// The first diagnostic of `parseValue(text)`.
  Map<String, Object?> valueSyntaxError(String text) =>
      _firstError(_parser.parseValue(Source(text)).diagnostics);

  /// The first diagnostic of `parseConstValue(text)`.
  Map<String, Object?> constValueSyntaxError(String text) => _firstError(
    _parser.parseValue(Source(text), isConst: true).diagnostics,
  );

  T _element<T extends Node>(ParseElementResult<T> result) => switch (result) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };

  Map<String, Object?> _firstError(List<Diagnostic> diagnostics) {
    if (diagnostics.isEmpty) {
      fail('expected a syntax error');
    }
    return const ErrorJson().of(diagnostics.first);
  }
}
```

Create `packages/typed_graphql_conformance/test/support/schema_nodes.dart`:

```dart
import 'package:test/test.dart';

/// graphql-js's node builders of `schema-parser-test.ts` (`nameNode`,
/// `typeNode`, `fieldNode`, `fieldNodeWithArgs`, `enumValueNode`,
/// `inputValueNode`) as `AstJson` maps, shared by the files the suite is
/// split into.
final class SchemaNodes {
  /// Creates the builders; they keep no state.
  const SchemaNodes();

  /// A location, graphql-js's `{ start, end }`.
  Map<String, int> loc(int start, int end) => {'start': start, 'end': end};

  /// A `Document` node.
  Map<String, Object?> document(
    List<Object?> definitions,
    Map<String, int> loc,
  ) => {'kind': 'Document', 'definitions': definitions, 'loc': loc};

  /// A `Name` node.
  Map<String, Object?> nameNode(String name, Map<String, int> loc) => {
    'kind': 'Name',
    'value': name,
    'loc': loc,
  };

  /// A `NamedType` node.
  Map<String, Object?> typeNode(String name, Map<String, int> loc) => {
    'kind': 'NamedType',
    'name': nameNode(name, loc),
    'loc': loc,
  };

  /// A `FieldDefinition` node without arguments.
  Map<String, Object?> fieldNode(
    Object? name,
    Object? type,
    Map<String, int> loc,
  ) => fieldNodeWithArgs(name, type, null, loc);

  /// A `FieldDefinition` node.
  Map<String, Object?> fieldNodeWithArgs(
    Object? name,
    Object? type,
    Object? arguments,
    Map<String, int> loc,
  ) => {
    'kind': 'FieldDefinition',
    'description': null,
    'name': name,
    'arguments': arguments,
    'type': type,
    'directives': null,
    'loc': loc,
  };

  /// An `EnumValueDefinition` node.
  Map<String, Object?> enumValueNode(String name, Map<String, int> loc) => {
    'kind': 'EnumValueDefinition',
    'name': nameNode(name, loc),
    'description': null,
    'directives': null,
    'loc': loc,
  };

  /// An `InputValueDefinition` node.
  Map<String, Object?> inputValueNode(
    Object? name,
    Object? type,
    Object? defaultValue,
    Map<String, int> loc,
  ) => {
    'kind': 'InputValueDefinition',
    'name': name,
    'description': null,
    'type': type,
    'defaultValue': defaultValue,
    'directives': null,
    'loc': loc,
  };

  /// graphql-js's `toDeepNestedProperty('definitions[0].<key>')`: the field
  /// [key] of the first definition of a [document] from `ParserPort.parse`.
  Object? firstDefinition(Object? document, String key) {
    if (document case {
      'definitions': [final Map<String, Object?> first, ...],
    }) {
      return first[key];
    }
    fail('$document has no definitions');
  }
}
```

- [ ] **Step 2: Write the worked examples**

Each file starts with the first tests of its suite; Step 4 adds the rest.

Create `packages/typed_graphql_conformance/test/language/parser/parser_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/dedent.dart';
import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';

void main() {
  const port = ParserPort();
  const dedent = Dedent();

  group('Parser', () {
    test('parses constant default values', () {
      expect(
        port.syntaxError(
          r'query Foo($x: Complex = { a: { b: [ $var ] } }) { field }',
        ),
        {
          'message':
              r'Syntax Error: Unexpected variable "$var" in constant value.',
          'locations': [
            {'line': 1, 'column': 37},
          ],
        },
      );
    });

    test('parses kitchen sink', () {
      expect(() => port.document(KitchenSink.query), returnsNormally);
    });

    test('creates ast', () {
      final result = port.parse(
        dedent('''
          {
            node(id: 4) {
              id,
              name
            }
          }
        '''),
      );

      expect(result, {
        'kind': 'Document',
        'loc': {'start': 0, 'end': 40},
        'definitions': [
          {
            'kind': 'OperationDefinition',
            'description': null,
            'loc': {'start': 0, 'end': 40},
            'operation': 'query',
            'name': null,
            'variableDefinitions': null,
            'directives': null,
            'selectionSet': {
              'kind': 'SelectionSet',
              'loc': {'start': 0, 'end': 40},
              'selections': [
                {
                  'kind': 'Field',
                  'loc': {'start': 4, 'end': 38},
                  'alias': null,
                  'name': {
                    'kind': 'Name',
                    'loc': {'start': 4, 'end': 8},
                    'value': 'node',
                  },
                  'arguments': [
                    {
                      'kind': 'Argument',
                      'name': {
                        'kind': 'Name',
                        'loc': {'start': 9, 'end': 11},
                        'value': 'id',
                      },
                      'value': {
                        'kind': 'IntValue',
                        'loc': {'start': 13, 'end': 14},
                        'value': '4',
                      },
                      'loc': {'start': 9, 'end': 14},
                    },
                  ],
                  'directives': null,
                  'selectionSet': {
                    'kind': 'SelectionSet',
                    'loc': {'start': 16, 'end': 38},
                    'selections': [
                      {
                        'kind': 'Field',
                        'loc': {'start': 22, 'end': 24},
                        'alias': null,
                        'name': {
                          'kind': 'Name',
                          'loc': {'start': 22, 'end': 24},
                          'value': 'id',
                        },
                        'arguments': null,
                        'directives': null,
                        'selectionSet': null,
                      },
                      {
                        'kind': 'Field',
                        'loc': {'start': 30, 'end': 34},
                        'alias': null,
                        'name': {
                          'kind': 'Name',
                          'loc': {'start': 30, 'end': 34},
                          'value': 'name',
                        },
                        'arguments': null,
                        'directives': null,
                        'selectionSet': null,
                      },
                    ],
                  },
                },
              ],
            },
          },
        ],
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/language/parser/parser_values_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/parser_port.dart';

void main() {
  const port = ParserPort();

  group('Parser', () {
    group('parseValue', () {
      test('parses list values', () {
        expect(port.parseValue('[123 "abc"]'), {
          'kind': 'ListValue',
          'loc': {'start': 0, 'end': 11},
          'values': [
            {
              'kind': 'IntValue',
              'loc': {'start': 1, 'end': 4},
              'value': '123',
            },
            {
              'kind': 'StringValue',
              'loc': {'start': 5, 'end': 10},
              'value': 'abc',
              'block': false,
            },
          ],
        });
      });
    });

    group('parseConstValue', () {
      test('correct message for unexpected token', () {
        expect(port.constValueSyntaxError(r'$'), {
          'message': r'Syntax Error: Unexpected "$".',
          'locations': [
            {'line': 1, 'column': 1},
          ],
        });
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/language/parser/schema_parser_definitions_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/schema-parser-test.ts;
// see mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const drafts = ParserPort(
    options: ParserOptions(allowDirectiveExtensions: true),
  );
  const nodes = SchemaNodes();

  group('Schema Parser', () {
    // Adapted: directive extensions are a working-draft feature, so the
    // parse enables them (ParserOptions.allowDirectiveExtensions).
    test('Directive extension', () {
      expect(
        drafts.parse('extend directive @foo @bar'),
        nodes.document([
          {
            'kind': 'DirectiveExtension',
            'name': nodes.nameNode('foo', nodes.loc(18, 21)),
            'directives': [
              {
                'kind': 'Directive',
                'name': nodes.nameNode('bar', nodes.loc(23, 26)),
                'arguments': null,
                'loc': nodes.loc(22, 26),
              },
            ],
            'loc': nodes.loc(0, 26),
          },
        ], nodes.loc(0, 26)),
      );
    });

    // Adapted: the kitchen sink holds directive extensions and directives
    // on a directive definition, which are working-draft features.
    test('parses kitchen sink schema', () {
      expect(() => drafts.document(KitchenSink.sdl), returnsNormally);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/language/parser/schema_parser_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/schema-parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/dedent.dart';
import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const port = ParserPort();
  const dedent = Dedent();
  const nodes = SchemaNodes();

  group('Schema Parser', () {
    test('Simple type', () {
      final document = port.parse(
        dedent('''
          type Hello {
            world: String
          }
        '''),
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'interfaces': null,
            'directives': null,
            'fields': [
              nodes.fieldNode(
                nodes.nameNode('world', nodes.loc(15, 20)),
                nodes.typeNode('String', nodes.loc(22, 28)),
                nodes.loc(15, 28),
              ),
            ],
            'loc': nodes.loc(0, 30),
          },
        ], nodes.loc(0, 30)),
      );
    });

    test('parses type with description string', () {
      final document = port.parse(
        dedent('''
          "Description"
          type Hello {
            world: String
          }
        '''),
      );

      expect(nodes.firstDefinition(document, 'description'), {
        'kind': 'StringValue',
        'value': 'Description',
        'block': false,
        'loc': nodes.loc(0, 13),
      });
    });

    test('Extension without anything throws', () {
      Map<String, Object?> unexpectedEnd(int column) => {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': column},
        ],
      };
      expect(port.syntaxError('extend scalar Hello'), unexpectedEnd(20));
      expect(port.syntaxError('extend type Hello'), unexpectedEnd(18));
      expect(port.syntaxError('extend interface Hello'), unexpectedEnd(23));
      expect(port.syntaxError('extend union Hello'), unexpectedEnd(19));
      expect(port.syntaxError('extend enum Hello'), unexpectedEnd(18));
      expect(port.syntaxError('extend input Hello'), unexpectedEnd(19));
    });
  });
}
```

- [ ] **Step 3: Run the worked examples**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/parser/parser_test.dart test/language/parser/parser_values_test.dart test/language/parser/schema_parser_definitions_test.dart test/language/parser/schema_parser_test.dart)
```

Expected: `parser_test.dart` `+3`, `parser_values_test.dart` `+2`, `schema_parser_test.dart` `+3`, `schema_parser_definitions_test.dart` `+2`, each `All tests passed!`

- [ ] **Step 4: Port every other test of `parser-test.ts`, `schema-parser-test.ts`**

Follow the procedure in Task 16 for every remaining `it` of both files. Put each test in the Dart file that its row in Step 5 names:

| File | Tests |
|---|---|
| `parser_test.dart` | `parser-test.ts` up to and including 'creates ast' |
| `parser_ast_test.dart` | the two 'creates ast from nameless query …' tests |
| `parser_values_test.dart` | the `parseValue`, `parseConstValue` and `parseType` groups |
| `parser_descriptions_test.dart` | the 'operation and variable definition descriptions' group |
| `schema_parser_test.dart` | `schema-parser-test.ts` from 'Simple type' to 'Extension without anything throws' |
| `schema_parser_extensions_test.dart` | the four 'Schema extension' tests |
| `schema_parser_types_test.dart` | 'Simple non-null type' to 'Simple interface inheriting multiple interfaces with leading ampersand' |
| `schema_parser_definitions_test.dart` | 'Single value enum' to the end |

- 'parse provides useful errors' and 'parse provides useful error when using source' are adapted. They compare the message, the location, `span.start` and the source name, without graphql-js's source excerpt (M2b).
- 'exposes the tokenCount' is adapted. It drains a `Lexer` over the same text and reads `Lexer.tokenCount`, because `Parser` does not expose the count.
- The 21 skipped rows need no Dart test: `noLocation`, the `Location` object and its tokens, fragment arguments (R1.14), and the `parseSchemaCoordinate` group (M2b).
- Use the closures and helpers of the worked examples; `SchemaNodes` serves every schema-parser file.

- [ ] **Step 5: Write the rows**

Append these rows to `packages/typed_graphql_conformance/mapping/language.csv`, after the rows that are already there. They are final, in graphql-js order, with one row per graphql-js test. The worked examples of Step 2 are among them.

```csv
parser-test.ts,Parser,parse provides useful errors,adapted,test/language/parser/parser_test.dart,"The printLocation excerpt of String(error) arrives in M2b: Dart checks message, position and location."
parser-test.ts,Parser,parse provides useful error when using source,adapted,test/language/parser/parser_test.dart,"The printLocation excerpt arrives in M2b: Dart checks message, location and source name."
parser-test.ts,Parser,limits by a maximum number of tokens,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,exposes the tokenCount,adapted,test/language/parser/parser_test.dart,The parser exposes no tokenCount: Lexer.tokenCount after reading the document is checked.
parser-test.ts,Parser,parses variable inline values,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses constant default values,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses variable definition directives,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,"does not accept fragments named ""on""",ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,"does not accept fragments spread of ""on""",ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,"does not allow ""true"", ""false"", or ""null"" as enum value",ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses multi-byte characters,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses kitchen sink,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,allows non-keywords anywhere a Name is allowed,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses anonymous mutation operations,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses anonymous subscription operations,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses named mutation operations,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,parses named subscription operations,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,creates ast,ported,test/language/parser/parser_test.dart,
parser-test.ts,Parser,creates ast from nameless query without variables,ported,test/language/parser/parser_ast_test.dart,
parser-test.ts,Parser,creates ast from nameless query with description,ported,test/language/parser/parser_ast_test.dart,
parser-test.ts,Parser,allows parsing without source location information,skipped,,Nodes always carry offsets; there is no noLocation option.
parser-test.ts,Parser,allows parsing fragment defined variables,skipped,,Experimental fragment arguments are out of scope (R1.14).
parser-test.ts,Parser,disallows parsing fragment defined variables without experimental flag,skipped,,Experimental fragment arguments are out of scope (R1.14).
parser-test.ts,Parser,allows parsing fragment spread arguments,skipped,,Experimental fragment arguments are out of scope (R1.14).
parser-test.ts,Parser,disallows parsing fragment spread arguments without experimental flag,skipped,,Experimental fragment arguments are out of scope (R1.14).
parser-test.ts,Parser,"contains location that can be Object.toStringified, JSON.stringified, or jsutils.inspected",skipped,,"Nodes hold start and end offsets only, no Location object."
parser-test.ts,Parser,contains references to source,skipped,,"Nodes hold start and end offsets only, no Location object."
parser-test.ts,Parser,contains references to start and end tokens,skipped,,"Nodes hold start and end offsets only, no tokens."
parser-test.ts,Parser > parseValue,parses null value,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseValue,parses list values,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseValue,parses block strings,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseValue,allows variables,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseValue,correct message for incomplete variable,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseValue,correct message for unexpected token,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseConstValue,parses values,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseConstValue,does not allow variables,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseConstValue,correct message for unexpected token,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseType,parses well known types,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseType,parses custom types,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseType,parses list types,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseType,parses non-null types,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseType,parses nested types,ported,test/language/parser/parser_values_test.dart,
parser-test.ts,Parser > parseSchemaCoordinate,parses Name,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,parses Name . Name,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,rejects Name . Name . Name,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,parses Name . Name ( Name : ),skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,rejects Name . Name ( Name : Name ),skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,parses @ Name,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,parses @ Name ( Name : ),skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,parses __Type,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,parses Type.__metafield,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,parses Type.__metafield(arg:),skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,rejects @ Name . Name,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > parseSchemaCoordinate,accepts a Source object,skipped,,Schema coordinates arrive in stage M2b.
parser-test.ts,Parser > operation and variable definition descriptions,parses operation with description and variable descriptions,ported,test/language/parser/parser_descriptions_test.dart,
parser-test.ts,Parser > operation and variable definition descriptions,descriptions on a short-hand query produce a sensible error,ported,test/language/parser/parser_descriptions_test.dart,
parser-test.ts,Parser > operation and variable definition descriptions,"parses variable definition with description, default value, and directives",ported,test/language/parser/parser_descriptions_test.dart,
parser-test.ts,Parser > operation and variable definition descriptions,parses fragment with variable description,skipped,,Experimental fragment arguments are out of scope (R1.14).
schema-parser-test.ts,Schema Parser,Simple type,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,parses type with description string,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,parses type with description multi-line string,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,parses schema with description string,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Description followed by something other than type system definition throws,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Simple extension,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Object extension without fields,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Interface extension without fields,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Object extension without fields followed by extension,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Extension without anything throws,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Interface extension without fields followed by extension,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Object extension do not include descriptions,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Interface extension do not include descriptions,ported,test/language/parser/schema_parser_test.dart,
schema-parser-test.ts,Schema Parser,Schema extension,ported,test/language/parser/schema_parser_extensions_test.dart,
schema-parser-test.ts,Schema Parser,Schema extension with only directives,ported,test/language/parser/schema_parser_extensions_test.dart,
schema-parser-test.ts,Schema Parser,Schema extension without anything throws,ported,test/language/parser/schema_parser_extensions_test.dart,
schema-parser-test.ts,Schema Parser,Schema extension with invalid operation type throws,ported,test/language/parser/schema_parser_extensions_test.dart,
schema-parser-test.ts,Schema Parser,Simple non-null type,ported,test/language/parser/schema_parser_types_test.dart,
schema-parser-test.ts,Schema Parser,Simple interface inheriting interface,ported,test/language/parser/schema_parser_types_test.dart,
schema-parser-test.ts,Schema Parser,Simple type inheriting interface,ported,test/language/parser/schema_parser_types_test.dart,
schema-parser-test.ts,Schema Parser,Simple type inheriting multiple interfaces,ported,test/language/parser/schema_parser_types_test.dart,
schema-parser-test.ts,Schema Parser,Simple interface inheriting multiple interfaces,ported,test/language/parser/schema_parser_types_test.dart,
schema-parser-test.ts,Schema Parser,Simple type inheriting multiple interfaces with leading ampersand,ported,test/language/parser/schema_parser_types_test.dart,
schema-parser-test.ts,Schema Parser,Simple interface inheriting multiple interfaces with leading ampersand,ported,test/language/parser/schema_parser_types_test.dart,
schema-parser-test.ts,Schema Parser,Single value enum,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Double value enum,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple interface,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple field with arg,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple field with arg with default value,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple field with list arg,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple field with two args,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple union,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Union with two types,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Union with two types and leading pipe,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Union fails with no types,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Union fails with leading double pipe,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Union fails with double pipe,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Union fails with trailing pipe,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Scalar,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple input object,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Simple input object with args should fail,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Directive definition,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Repeatable directive definition,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Directive with incorrect locations,ported,test/language/parser/schema_parser_definitions_test.dart,
schema-parser-test.ts,Schema Parser,Directive extension,adapted,test/language/parser/schema_parser_definitions_test.dart,Directive extensions are a working-draft feature: the parse sets ParserOptions.allowDirectiveExtensions.
schema-parser-test.ts,Schema Parser,parses kitchen sink schema,adapted,test/language/parser/schema_parser_definitions_test.dart,The kitchen sink uses working-draft directive extensions: the parse sets ParserOptions.allowDirectiveExtensions.
```

- [ ] **Step 6: Mark the files as ported**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, add `'parser-test.ts'` and `'schema-parser-test.ts'` to `portedFiles`, after the names already there:

```dart
const Set<String> portedFiles = {
  'lexer-test.ts',
  'blockString-test.ts',
  'parser-test.ts',
  'schema-parser-test.ts',
};
```

- [ ] **Step 7: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+143: All tests passed!`: 129 ported or adapted tests, 9 table checks, 3 support tests and 2 pubspec tests. Without `reference/` it is `+139` with 4 skipped.

- [ ] **Step 8: Update the changelog**

Replace `packages/typed_graphql_conformance/CHANGELOG.md` whole with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- Depends on `typed_graphql` only.
- `mapping/language.csv`, the conformance mapping table, and the test that
  checks it.
- Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`,
  `parser-test.ts`, `schema-parser-test.ts`.
```

- [ ] **Step 9: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 10: Commit**

```sh
git add packages/typed_graphql_conformance
git commit -q -m "test(typed_graphql_conformance): port the graphql-js parser and schema parser suites"
```

### Task 18: Port printer-test.ts, schema-printer-test.ts and printString-test.ts

The procedure is the one in Task 16. The worked example 'prints kitchen sink without altering ast' already checks the whole kitchen-sink SDL against graphql-js's printed text.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql_conformance/test/language/printer/print_string_test.dart`, `packages/typed_graphql_conformance/test/language/printer/printer_test.dart`, `packages/typed_graphql_conformance/test/language/printer/schema_printer_test.dart`
- Modify: `packages/typed_graphql_conformance/test/mapping_test.dart` (`portedFiles`)

**Interfaces:**
- Consumes: Tasks 16–17: the helpers and the procedure; Tasks 12–13: `Printer`.
- Produces:
  - no new helper. `printString` is a local closure, and a node class the library does not define (`_ForeignNode`, which overrides `rebuildFrom(Object? read)`) stands in for graphql-js's `{ random: 'Data' }`;
  - rows: 16 for `printer-test.ts` (8 ported, 2 adapted, 6 skipped), 3 for `schema-printer-test.ts` (1 ported, 2 adapted) and 10 for `printString-test.ts` (all ported).

- [ ] **Step 1: Write the worked examples**

Each file starts with the first tests of its suite; Step 4 adds the rest.

Create `packages/typed_graphql_conformance/test/language/printer/print_string_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/printString-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  // graphql-js's `printString` is what the printer writes for a string
  // value that is not a block string.
  String printString(String value) => const Printer().print(StringValue(value));

  group('printString', () {
    test('escapes quotes', () {
      expect(printString('"hello world"'), r'"\"hello world\""');
    });

    test('escapes well-known control chars', () {
      expect(printString('\b\f\n\r\t'), r'"\b\f\n\r\t"');
    });

    test('does not escape supplementary character', () {
      expect(printString('\u{1f600}'), '"\u{1f600}"');
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/language/printer/printer_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/printer-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/dedent.dart';
import '../../support/parser_port.dart';

void main() {
  const port = ParserPort();
  const printer = Printer();
  const dedent = Dedent();

  group('Printer: Query document', () {
    test('prints minimal ast', () {
      expect(printer.print(Field(null, const Name('foo'))), 'foo');
    });

    // Adapted: Dart's types admit no `{ random: 'Data' }`; the closest
    // input is a node class this library does not define.
    test('produces helpful error messages', () {
      expect(() => printer.print(_ForeignNode()), throwsArgumentError);
    });

    test('correctly prints non-query operations without name', () {
      final queryAstShorthanded = port.document('query { id, name }');
      expect(
        printer.print(queryAstShorthanded),
        dedent('''
          {
            id
            name
          }
        '''),
      );

      final mutationAst = port.document('mutation { id, name }');
      expect(
        printer.print(mutationAst),
        dedent('''
          mutation {
            id
            name
          }
        '''),
      );

      final queryAstWithArtifacts = port.document(
        r'query ($foo: TestType) @testDirective { id, name }',
      );
      expect(
        printer.print(queryAstWithArtifacts),
        dedent(r'''
          query ($foo: TestType) @testDirective {
            id
            name
          }
        '''),
      );

      final mutationAstWithArtifacts = port.document(
        r'mutation ($foo: TestType) @testDirective { id, name }',
      );
      expect(
        printer.print(mutationAstWithArtifacts),
        dedent(r'''
          mutation ($foo: TestType) @testDirective {
            id
            name
          }
        '''),
      );
    });

    test('puts arguments on multiple lines if line is long (> 80 chars)', () {
      final printed = printer.print(
        port.document(
          '{trip(wheelchair:false arriveBy:false includePlannedCancellations:true transitDistanceReluctance:2000){dateTime}}',
        ),
      );

      expect(
        printed,
        dedent('''
          {
            trip(
              wheelchair: false
              arriveBy: false
              includePlannedCancellations: true
              transitDistanceReluctance: 2000
            ) {
              dateTime
            }
          }
        '''),
      );
    });
  });
}

/// A node class this library does not define, standing in for graphql-js's
/// `{ random: 'Data' }`.
final class _ForeignNode extends Node {
  @override
  List<Node> get children => const [];

  // A wider parameter type than Node's: `ChildReader` is not public API,
  // and a node built outside the library never rebuilds.
  @override
  Node rebuildFrom(Object? read) => this;
}
```

Create `packages/typed_graphql_conformance/test/language/printer/schema_printer_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/schema-printer-test.ts;
// see mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/dedent.dart';
import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';

void main() {
  const printer = Printer();
  const dedent = Dedent();

  group('Printer: SDL document', () {
    test('prints minimal ast', () {
      expect(
        printer.print(ScalarTypeDefinition(const Name('foo'))),
        'scalar foo',
      );
    });

    // Adapted: the kitchen sink needs the working-draft directive
    // extensions; nodes are immutable, so the AST cannot be altered, and
    // `isEquivalentTo` stands for a deep equality without locations.
    test('prints kitchen sink without altering ast', () {
      const port = ParserPort(
        options: ParserOptions(allowDirectiveExtensions: true),
      );
      final ast = port.document(KitchenSink.sdl);

      final printed = printer.print(ast);
      final printedAst = port.document(printed);

      expect(printedAst.isEquivalentTo(ast), isTrue);

      expect(
        printed,
        dedent('''
          """This is a description of the schema as a whole."""
          schema {
            query: QueryType
            mutation: MutationType
          }

          """
          This is a description
          of the `Foo` type.
          """
          type Foo implements Bar & Baz & Two {
            "Description of the `one` field."
            one: Type
            """This is a description of the `two` field."""
            two(
              """This is a description of the `argument` argument."""
              argument: InputType!
            ): Type
            """This is a description of the `three` field."""
            three(argument: InputType, other: String): Int
            four(argument: String = "string"): String
            five(argument: [String] = ["string", "string"]): String
            six(argument: InputType = { key: "value" }): Type
            seven(argument: Int = null): Type
            eight(argument: OneOfInputType): Type
          }

          type AnnotatedObject @onObject(arg: "value") {
            annotatedField(arg: Type = "default" @onArgumentDefinition): Type @onField
          }

          type UndefinedType

          extend type Foo {
            seven(argument: [String]): Type
          }

          extend type Foo @onType

          interface Bar {
            one: Type
            four(argument: String = "string"): String
          }

          interface AnnotatedInterface @onInterface {
            annotatedField(arg: Type @onArgumentDefinition): Type @onField
          }

          interface UndefinedInterface

          extend interface Bar implements Two {
            two(argument: InputType!): Type
          }

          extend interface Bar @onInterface

          interface Baz implements Bar & Two {
            one: Type
            two(argument: InputType!): Type
            four(argument: String = "string"): String
          }

          union Feed = Story | Article | Advert

          union AnnotatedUnion @onUnion = A | B

          union AnnotatedUnionTwo @onUnion = A | B

          union UndefinedUnion

          extend union Feed = Photo | Video

          extend union Feed @onUnion

          scalar CustomScalar

          scalar AnnotatedScalar @onScalar

          extend scalar CustomScalar @onScalar

          enum Site {
            """This is a description of the `DESKTOP` value"""
            DESKTOP
            """This is a description of the `MOBILE` value"""
            MOBILE
            "This is a description of the `WEB` value"
            WEB
          }

          enum AnnotatedEnum @onEnum {
            ANNOTATED_VALUE @onEnumValue
            OTHER_VALUE
          }

          enum UndefinedEnum

          extend enum Site {
            VR
          }

          extend enum Site @onEnum

          input InputType {
            key: String!
            answer: Int = 42
          }

          input OneOfInputType @oneOf {
            string: String
            int: Int
          }

          input AnnotatedInput @onInputObject {
            annotatedField: Type @onInputFieldDefinition
          }

          input UndefinedInput

          extend input InputType {
            other: Float = 1.23e4 @onInputFieldDefinition
          }

          extend input InputType @onInputObject

          directive @onDirectiveDefinition on DIRECTIVE_DEFINITION

          """This is a description of the `@skip` directive"""
          directive @skip(
            """This is a description of the `if` argument"""
            if: Boolean! @onArgumentDefinition
          ) @onDirectiveDefinition on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          directive @include(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          directive @include2(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          directive @myRepeatableDir(name: String!) repeatable on OBJECT | INTERFACE

          extend directive @skip @onDirectiveDefinition

          extend schema @onSchema

          extend schema @onSchema {
            subscription: SubscriptionType
          }
        '''),
      );
    });
  });
}
```

- [ ] **Step 2: Run the worked examples**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/printer/print_string_test.dart test/language/printer/printer_test.dart test/language/printer/schema_printer_test.dart)
```

Expected: `printer_test.dart` `+4`, `schema_printer_test.dart` `+2`, `print_string_test.dart` `+3`, each `All tests passed!`

- [ ] **Step 3: Port every other test of `printer-test.ts`, `schema-printer-test.ts`, `printString-test.ts`**

Follow the procedure in Task 16 for every remaining `it` of the three files. Each suite stays in one Dart file.

- 'produces helpful error messages' is adapted in both printer files. It checks `throwsArgumentError` for a private `_ForeignNode`; `schema_printer_test.dart` declares its own.
- 'prints kitchen sink without altering ast' in `printer-test.ts` is adapted like the SDL one. Nodes are immutable, so the AST cannot be altered, and `isEquivalentTo` stands for the deep equality without locations. `KitchenSink.query` parses with the default options.
- The four fragment-argument tests (R1.14) and the two schema-coordinate tests (M2b) are skipped.
- In `printString-test.ts`, 'escapes all control chars' may build its input and its expectation in a loop over the code units 0x00–0x9F, instead of graphql-js's long literal. The expectation stays the same: `\uXXXX` with uppercase hex for 0x00–0x1F and 0x7F–0x9F, except the named escapes `\b \t \n \f \r \" \\`.

- [ ] **Step 4: Write the rows**

Append these rows to `packages/typed_graphql_conformance/mapping/language.csv`, after the rows that are already there. They are final, in graphql-js order, with one row per graphql-js test. The worked examples of Step 2 are among them.

```csv
printer-test.ts,Printer: Query document,prints minimal ast,ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,produces helpful error messages,adapted,test/language/printer/printer_test.dart,Dart's types admit no plain object: a node class the library does not define gives an ArgumentError.
printer-test.ts,Printer: Query document,correctly prints non-query operations without name,ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,prints query with variable directives,ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,keeps arguments on one line if line is short (<= 80 chars),ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,puts arguments on multiple lines if line is long (> 80 chars),ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,puts large object values on multiple lines if line is long (> 80 chars),ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,puts large list values on multiple lines if line is long (> 80 chars),ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,prints fragment with argument definition directives,skipped,,experimental fragment arguments are out of scope (R1.14)
printer-test.ts,Printer: Query document,correctly prints fragment defined arguments,skipped,,experimental fragment arguments are out of scope (R1.14)
printer-test.ts,Printer: Query document,prints fragment spread with arguments,skipped,,experimental fragment arguments are out of scope (R1.14)
printer-test.ts,Printer: Query document,prints fragment spread with multi-line arguments,skipped,,experimental fragment arguments are out of scope (R1.14)
printer-test.ts,Printer: Query document,prints fragment,ported,test/language/printer/printer_test.dart,
printer-test.ts,Printer: Query document,prints kitchen sink without altering ast,adapted,test/language/printer/printer_test.dart,Nodes are immutable so the AST cannot be altered; isEquivalentTo stands for the deep equality without locations.
printer-test.ts,Printer: Query document,prints schema coordinates,skipped,,schema coordinates arrive in stage M2b
printer-test.ts,Printer: Query document,throws syntax error for ignored tokens in schema coordinates,skipped,,schema coordinates arrive in stage M2b
schema-printer-test.ts,Printer: SDL document,prints minimal ast,ported,test/language/printer/schema_printer_test.dart,
schema-printer-test.ts,Printer: SDL document,produces helpful error messages,adapted,test/language/printer/schema_printer_test.dart,Dart's types admit no plain object: a node class the library does not define gives an ArgumentError.
schema-printer-test.ts,Printer: SDL document,prints kitchen sink without altering ast,adapted,test/language/printer/schema_printer_test.dart,The kitchen sink needs ParserOptions.allowDirectiveExtensions; nodes are immutable and isEquivalentTo stands for the deep equality without locations.
printString-test.ts,printString,prints a simple string,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,escapes quotes,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,does not escape single quote,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,escapes backslashes,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,escapes well-known control chars,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,escapes zero byte,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,does not escape space,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,does not escape non-ascii character,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,does not escape supplementary character,ported,test/language/printer/print_string_test.dart,
printString-test.ts,printString,escapes all control chars,ported,test/language/printer/print_string_test.dart,
```

- [ ] **Step 5: Mark the files as ported**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, add `'printer-test.ts'` and `'schema-printer-test.ts'` and `'printString-test.ts'` to `portedFiles`, after the names already there:

```dart
const Set<String> portedFiles = {
  'lexer-test.ts',
  'blockString-test.ts',
  'parser-test.ts',
  'schema-parser-test.ts',
  'printer-test.ts',
  'schema-printer-test.ts',
  'printString-test.ts',
};
```

- [ ] **Step 6: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+169: All tests passed!`: 152 ported or adapted tests, 12 table checks, 3 support tests and 2 pubspec tests. Without `reference/` it is `+162` with 7 skipped.

- [ ] **Step 7: Update the changelog**

Replace `packages/typed_graphql_conformance/CHANGELOG.md` whole with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- Depends on `typed_graphql` only.
- `mapping/language.csv`, the conformance mapping table, and the test that
  checks it.
- Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`,
  `parser-test.ts`, `schema-parser-test.ts`, `printer-test.ts`,
  `schema-printer-test.ts`, `printString-test.ts`.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_conformance
git commit -q -m "test(typed_graphql_conformance): port the graphql-js printer suites"
```

### Task 19: Documents, full verification and the handoff

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/superpowers/HANDOFF.md`, `packages/typed_graphql/README.md`, `packages/typed_graphql/lib/typed_graphql.dart`

**Interfaces:**
- Consumes: Tasks 1–18.
- Produces:
  - the status in `CLAUDE.md`, both READMEs and the barrel's library comment;
  - the "Learned in M2a" notes in `CLAUDE.md`;
  - the evidence that M2a is done, and a handoff that says so.

- [ ] **Step 1: Update the documents**

The core README gets a "Parsing and printing" section. Its example was run, and the output shown is what it printed.

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,8 +21,10 @@ server and the client. It is a Dart pub workspace of pure-Dart packages:
 Minimum SDK: Dart 3.13 (`sdk: ^3.13.0`) in every package and in generated
 code. No dependency on `package:gql` or its ecosystem.
 
-Status: under construction. M1 (foundations) delivers the workspace, the code
-rules, CI, the diagnostics model and the protocol data types.
+Status: under construction. M1 (foundations) delivered the workspace, the
+code rules, CI, the diagnostics model and the protocol data types. M2a
+(language core) delivers the syntax trees, the lexer, the parser, the
+printer and the ported graphql-js language suites.
 
 ## Documents
 
@@ -95,9 +97,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `BlockStringValue` and graphql-js's printing rules; lexer and printer share
   it. `Lexer(source, sink).advance()` never throws: bad text becomes one
   `error` token over the run and one diagnostic, with graphql-js's message
-  minus "Syntax Error: ". `maxTokens` is counted here (R1.6). Scanners (`*_scanner.dart`) share a
-  `SourceReader` (text, `describe`, `report`); `CharacterClass` holds the
-  character tests.
+  minus "Syntax Error: ". `maxTokens` is counted here (R1.6). Scanners
+  (`*_scanner.dart`) share a `SourceReader` (text, `describe`, `report`);
+  `CharacterClass` holds the character tests.
 - `parser/`: `Parser(options:)` is const and stateless; each call builds a
   `TokenCursor` (current token, one lookahead, graphql-js's `expect*`,
   `many`, `any`, `delimitedMany`, `nested` for `maxDepth`) and grammar
@@ -201,6 +203,17 @@ M1:
 - In tests, `expect` arguments have no context type: write full names, not
   dot shorthands.
 
+Learned in M2a:
+- An empty `case` in a `switch` statement falls through to the next case;
+  to skip an item, test it with `if (...) continue;` before the `switch`.
+- `prefer_interpolation_to_compose_strings` rejects `+` on strings; use
+  interpolation, or adjacent literals for a long text.
+- A multi-line literal drops a line break right after its opening quotes;
+  write `'\n'` in front when the text must start with one.
+- An overriding method may widen a parameter type: a node class outside the
+  library overrides `rebuildFrom(Object? read)` without the internal
+  `ChildReader`.
+
 **Dart style the lints do not check.** Acronyms longer than two letters are
 words (`Json`, `Sse`); doc comments start with a one-sentence summary and
 refer to identifiers in `[brackets]`; a boolean property starts with
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -58,8 +58,8 @@ void main() {
 ```
 
 > **Status: under construction.** Nothing is published to pub.dev yet, and
-> every API may change before 0.1.0. Stage M1 (foundations) is the current
-> one; the parser arrives in M2.
+> every API may change before 0.1.0. Stage M2 (language) is the current
+> one: the parser and the printer are in; visitors come next.
 
 ## Table of contents
 
@@ -100,13 +100,13 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 
 | Package | Role | Status |
 |---|---|---|
-| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics and protocol types (M1) |
+| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, parser and printer (M1, M2a) |
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
-| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | skeleton (M2) |
+| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language suites (M2a) |
 
 ## Install
 
@@ -129,8 +129,9 @@ input:
   says where the input is wrong (`$.errors[0].message: expected a string`).
 - `GraphQLRequest.decode`, `GraphQLError.decode` and `ResponsePayload.decode`
   read the GraphQL wire format; `toJson()` writes it.
-- `Source`, `SourceSpan`, `Diagnostic` and `DiagnosticSink` are the
-  diagnostics model the parser and validator will report through.
+- `Parser().parse(Source(text))` gives a `Document`, or every syntax error
+  as a `Diagnostic` with a code and a place; `Printer().print(node)` prints
+  it back the way graphql-js does.
 
 ## Documentation
 
````

Replace `packages/typed_graphql/README.md` whole with:

````markdown
# typed_graphql

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-core-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**GraphQL for Dart, written from scratch and fully typed: the language, the
type system, validation and the wire protocol, with diagnostics instead of
exceptions.** Pure Dart, depends only on `meta`, runs on the VM, AOT and the
web (dart2js and dart2wasm). Part of
[typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** This release has the diagnostics model, the
> protocol data types, and the language: syntax trees, the lexer, the parser
> and the printer. Visitors arrive later in M2, the type system in M3 and
> validation in M4 (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

## Contents

- [Install](#install)
- [Parsing and printing](#parsing-and-printing)
- [Reading the wire format](#reading-the-wire-format)
- [Diagnostics](#diagnostics)
- [License](#license)

## Install

Nothing is on pub.dev yet. To try it from the repository:

```yaml
dependencies:
  typed_graphql:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql
```

## Parsing and printing

`Parser` turns a `Source` into a `Document`, or a `ParseFailure` with every
syntax error it found: after an error it skips to the next definition or
selection and goes on. `Printer` prints any node the way graphql-js prints
it; `Printer(isMinified: true)` drops every character that does not matter.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  // Every syntax error in one pass, each with a stable code and a place.
  final broken = Source(
    'query { a(x: ) }\nfragment F on { b }',
    name: 'bad.graphql',
  );
  if (parser.parse(broken) case ParseFailure(:final diagnostics)) {
    diagnostics.forEach(print);
  }

  // A document prints back the way graphql-js prints it.
  final source = Source(
    r'query Hero($id:ID!){hero(id:$id){name ...on Droid{primaryFunction}}}',
  );
  if (parser.parse(source) case ParseSuccess(:final document)) {
    print(const Printer().print(document));
    print(const Printer(isMinified: true).print(document));
  }
}
```

It prints:

```text
bad.graphql:1:14: error GQL008: Unexpected ")".
bad.graphql:2:15: error GQL007: Expected Name, found "{".
query Hero($id: ID!) {
  hero(id: $id) {
    name
    ... on Droid {
      primaryFunction
    }
  }
}
query Hero($id:ID!){hero(id:$id){name ...on Droid{primaryFunction}}}
```

`ParserOptions` bound the work on untrusted text: `maxTokens` (15 000 by
default) and `maxDepth` (128). Working-draft syntax, such as
`extend directive`, is off unless `allowDirectiveExtensions` is set.

## Reading the wire format

Bad input never throws. `JsonReader` turns text into a `JsonValue`, a sealed
family you can switch over; the `decode` methods turn a `JsonValue` into
`GraphQLRequest`, `GraphQLError` or `ResponsePayload`. Each step gives a
`DecodeResult`: a `DecodeSuccess`, or a `DecodeFailure` that says where the
input is wrong.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader();

  // A request body from the wire: unknown keys are ignored.
  final request = switch (reader.parse('{"query": "{ hero { name } }"}')) {
    DecodeSuccess(:final value) => GraphQLRequest.decode(value),
    final DecodeFailure failure => failure,
  };
  print(request);

  // A failure says where the input is wrong.
  final response = switch (reader.parse('{"errors": [{"message": 7}]}')) {
    DecodeSuccess(:final value) => ResponsePayload.decode(value),
    final DecodeFailure failure => failure,
  };
  print(response);

  // Spans turn offsets into lines and columns.
  final source = Source('{\n  hero\n}', name: 'hero.graphql');
  print(SourceSpan(source, 4, 8));
}
```

It prints:

```text
DecodeSuccess(GraphQLRequest({"query":"{ hero { name } }"}))
$.errors[0].message: expected a string
hero.graphql:2:3
```

`JsonReader` rejects input nested deeper than `maxDepth` (512 by default)
before decoding it, and numbers too large to be finite. A `ResponsePayload`
is an `ExecutionResult` (it has `data`, maybe `null`) or a
`RequestErrorResult` (no `data`, at least one error).

## Diagnostics

The parser reports through this model, and the validator will:

- `Source` is a document and its name; `locationOf(offset)` gives a 1-based
  line and column, counted in UTF-16 code units.
- `SourceSpan` is a range of a `Source`.
- `Diagnostic` is one problem: a `DiagnosticCode` with a stable id
  (`GQL000`), a severity, a message, a span and related spans.
- `DiagnosticSink` collects diagnostics in order and stops at `maxErrors`
  errors (100 by default), reporting `GQL000` once.

## License

MIT — see [LICENSE](LICENSE).
````

Replace `packages/typed_graphql/lib/typed_graphql.dart` whole with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model, the protocol
/// data types, and the language (syntax trees, lexer, parser, printer).
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/language/ast/argument.dart';
export 'src/language/ast/definition.dart';
export 'src/language/ast/directive.dart';
export 'src/language/ast/document.dart';
export 'src/language/ast/enum_value_definition.dart';
export 'src/language/ast/executable_definition.dart';
export 'src/language/ast/field_definition.dart';
export 'src/language/ast/input_value_definition.dart';
export 'src/language/ast/name.dart';
export 'src/language/ast/node.dart';
export 'src/language/ast/object_field.dart';
export 'src/language/ast/operation_type.dart';
export 'src/language/ast/operation_type_definition.dart';
export 'src/language/ast/selection.dart';
export 'src/language/ast/selection_set.dart';
export 'src/language/ast/type_ref.dart';
export 'src/language/ast/type_system_definition.dart';
export 'src/language/ast/type_system_extension.dart';
export 'src/language/ast/value.dart';
export 'src/language/ast/variable_definition.dart';
export 'src/language/lexer/block_string.dart';
export 'src/language/lexer/lexer.dart';
export 'src/language/lexer/token.dart';
export 'src/language/lexer/token_kind.dart';
export 'src/language/parser/graphql_syntax_exception.dart';
export 'src/language/parser/parse_element_result.dart';
export 'src/language/parser/parse_result.dart';
export 'src/language/parser/parser.dart';
export 'src/language/parser/parser_options.dart';
export 'src/language/printer/printer.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

- [ ] **Step 2: Run every suite the way CI does**

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages test
dart analyze --fatal-infos
dart test
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
cd packages/typed_graphql
dart test --compiler exe
dart test -p chrome --compiler dart2js
dart test -p chrome --compiler dart2wasm
cd ../..
```

Expected:
- format and analyze are clean;
- the root suite gives `+34`, the core `+304` on the VM and as exe, and the five other skeleton packages `+2` each;
- the conformance package gives `+169` with `reference/` fetched (152 ported or adapted tests, 12 table checks, 3 support tests, 2 pubspec tests). Without `reference/` it gives `+162` and skips the 7 coverage checks;
- the core gives `+292` in Chrome with each compiler; the VM-only tests are not counted there. This includes the 100 000-level nesting test (Review Focus 1).

- [ ] **Step 3: Check that the language layer stays pure and in its place**

Run: `grep -rln "dart:io" packages/typed_graphql/lib || echo "no dart:io"`

Expected: `no dart:io` (R0.6).

Run: `grep -h -A3 '^dependencies:' packages/*/pubspec.yaml | grep -v '^dependencies:\|^--$\|^$' | sort -u`

Expected: only `meta: ^1.15.0`, workspace packages (`typed_graphql`, `typed_graphql_server`, `typed_graphql_codegen`) and a `dev_dependencies:` line: no `gql` (R0.4).

`layers_test.dart` already passed in Step 2, so `language/` imports only `diagnostics/` and itself.

- [ ] **Step 4: Record the result in the handoff**

In `docs/superpowers/HANDOFF.md`:
- set the line that starts with `Last updated:` to the one below;
- replace the table row that starts with `| M2 Language |` by the row below, whatever that row says now.

Leave everything else as it is.

```markdown
Last updated: 2026-10-14 (M2a implemented, final review pending). Read this
```

```markdown
| M2 Language | [spec](specs/2026-10-14-m2-language-design.md) | M2a: [plan](plans/2026-10-14-m2a-language-core.md) | M2a implemented on its branch, final review pending; then the M2b plan |
```

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add CLAUDE.md README.md docs/superpowers/HANDOFF.md packages/typed_graphql/README.md packages/typed_graphql/lib/typed_graphql.dart
git commit -q -m "docs: record the M2a language core"
```

## Requirement coverage

| Id | Requirement (verbatim from `docs/requirements.md`) | Where |
|---|---|---|
| R0.1 | The baseline is the GraphQL **September2025** edition; working-draft (`main`) additions are available behind options | Tasks 9–11 parse the September2025 grammar. Task 11 puts directive extensions behind `ParserOptions.allowDirectiveExtensions`, and Task 9 puts empty selection sets behind `allowEmptySelectionSets` |
| R0.2 | No `dynamic` and no `Map<String, dynamic>` in any public signature; arbitrary JSON is `JsonValue` / `JsonObject` | All tasks. The lints `avoid_dynamic_calls` and `no_dynamic_casts` and the root code-rules suite run in every green check; `strict-inference` and `strict-raw-types` arrive in Task 1 |
| R0.3 | Bad input (documents, schemas, variables, responses) never throws: results are sealed types carrying every diagnostic. Exceptions only for programmer errors and inside user resolvers | Tasks 6–7 (the lexer never throws), Tasks 8–9 (`ParseElementResult`, `ParseResult`; `SyntaxAbort` stays inside `Parser`), Task 14 (hostile input). Programmer errors: `ChildReader` throws `StateError` (Task 2), `Printer` throws `ArgumentError` for a foreign node (Task 12) |
| R0.4 | No dependency on `package:gql` or its ecosystem, and no bridge package | Task 19, Step 3 lists every dependency |
| R0.5 | `sdk: ^3.13.0` in every package and in generated code; stable Dart 3.13 features are used, no experiment flags | No pubspec changes its `sdk: ^3.13.0`; the code uses primary constructors, dot shorthands and patterns without experiment flags |
| R0.6 | The core package is pure Dart: no `dart:io`, no dependencies except `meta`; it compiles with dart2js and dart2wasm | `layers_test.dart` in every green check; Task 19, Steps 2–3 (Chrome with dart2js and dart2wasm, and the `dart:io` search) |
| R0.7 | Spec conformance is measured with ported graphql-js v17 suites and a coverage mapping table | Task 15 (the table and its check), Tasks 16–18 (seven suites, 182 rows) |
| R1.1 | Lexer: full-Unicode source, all token and ignored-token kinds, exact block-string algorithm, `\uXXXX` (with surrogate pairs) and `\u{...}` escapes with scalar-value validation | Task 5 (`BlockString`), Tasks 6–7 (`Lexer`, `EscapeReader`), Task 16 (`lexer-test.ts`, `blockString-test.ts`); Review Focus 2 and 4 |
| R1.2 | Lexer never throws; malformed input yields an error token and a diagnostic; comments are kept as trivia | Tasks 6–7 (`TokenKind.error`, `keepComments`) |
| R1.3 | Parser covers the whole September2025 executable and type-system grammar, including descriptions on executable definitions and every type-system extension | Tasks 8–11; Task 17 (`parser-test.ts`, `schema-parser-test.ts`, the kitchen sinks) |
| R1.4 | `ParserOptions` enables working-draft grammar (directive extensions, empty selection sets) and has an extension point for experimental productions | Task 8 (`ParserOptions`), Task 9 (`allowEmptySelectionSets`), Task 11 (`DefinitionGrammar`, `DirectiveExtensionGrammar`) |
| R1.5 | Error-resilient parsing: one pass reports every syntax error; `ParseSuccess` / `ParseFailure(partial)`; the partial document omits what failed, the AST has no error node variants | Task 9 (`Recovery`, `recovery_test.dart`), Task 14; Review Focus 5 |
| R1.6 | `maxTokens` and `maxDepth` limits | Task 7 (`maxTokens`), Task 8 (`maxDepth`), Task 14; Review Focus 1 |
| R1.7 | Every node has `start`/`end` offsets; `Source` computes line/column lazily | Task 2 (`Node.start`, `Node.end`), Tasks 8–11 (offsets checked in the parser tests), Task 17 (graphql-js `loc` values) |
| R1.8 | Sealed, immutable AST of `final` classes; `NonNullType` is a wrapper; numeric literals keep their raw lexeme; `isEquivalentTo` ignores positions | Tasks 2–4; Review Focus 3 |
| R1.10 | `Printer`: canonical and minified output; parse → print → parse is stable | Task 12 (canonical), Task 13 (minified, stability), Task 18 (the printer suites) |
| R1.12 | Stable `DiagnosticCode` catalog with ranges `GQL0xx`–`GQL5xx`, each code documented | Tasks 6–11 add `GQL001`–`GQL014` in id order, each with a doc comment |
| R10.2 | Size-limit ratchet and core layer-direction tests | Every green check; the allowlists stay empty |
| R10.3 | `typed_graphql_conformance` with ported graphql-js suites and a coverage mapping table | Tasks 15–18 |

Left for M2b: R1.9 (visitors), R1.11 (schema coordinates), R10.4 (parse-print fuzzing), and the rows of the eight graphql-js files named in deviation 1.

## Self-review

- **Spec coverage.** Every item of the M2a row of the M2 spec's section 1 has a task: the M1 carry-overs (Task 1), the AST (Tasks 2–4), the lexer (Tasks 5–7), the parser with recovery, limits and options (Tasks 8–11, 14), the printer (Tasks 12–13), and the conformance table with the seven suites (Tasks 15–18). Where the plan departs from the spec, "Spec deviations and findings" says so.
- **Verified code.** Every code block was applied, task by task, to a copy of `main` at `38a0c6e`, and every commit passed the green check. Each TDD task was seen failing before its implementation with the message quoted in its "see them fail" step, and passing after with the count quoted. The core language tests also passed with `--compiler exe`, and in Chrome with dart2js and dart2wasm.
- **Conformance.** All seven graphql-js files were ported in full against this library while the plan was written: 182 rows, `+169` with `reference/` fetched, and no expectation weakened. The rows in Tasks 16–18 are those rows. The worked examples are the first tests of each port.
- **Code rules.** The largest new `lib/` file has 266 lines (`type_system_parser.dart`), and the longest method has 34 lines (`DefinitionParser.definition`). No allowlist entry, no `// ignore:`, no top-level function besides `main`, and no `dynamic`.
- **Names and types.** The names in each task's "Interfaces" match the code in its steps, and later tasks use the same names.
- **No placeholders.** Steps that say "port every other test" are bounded by the final rows they must match and by the coverage test.

## Execution handoff

Two ways to run this plan:

1. **Subagent-driven (recommended).** Dispatch a fresh `implementer` subagent (model `sonnet`) for each task. After each task, a `reviewer` subagent checks it against the task. A final whole-branch review with model `opus` comes at the end. Use superpowers:subagent-driven-development. This keeps each context small, and Tasks 16–18 are long, mechanical ports that suit a fresh context each.
2. **Native.** Run the tasks in this session with superpowers:executing-plans, with a checkpoint after Tasks 4, 11, 14 and 18.

Work on a branch `m2a-language-core` in a worktree. Do not push, tag or publish without the user's yes. Executors append the trailers their session instructs.
