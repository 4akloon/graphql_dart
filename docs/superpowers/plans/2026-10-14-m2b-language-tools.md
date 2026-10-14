# M2b Language Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish M2's language layer and its conformance measurement:
- visitors (`AstVisitor`, `AstWalker`, `ParallelVisitor`) and the bottom-up `AstTransformer` (R1.9);
- schema coordinates: nodes, their own lexer, `Parser.parseSchemaCoordinate` and printing (R1.11);
- `SourceSpan.excerpt`, a port of graphql-js's `printLocation`;
- the remaining graphql-js language suites, so that every file of `src/language/__tests__` has its rows and the table check reads the whole directory (R0.7, R10.3);
- the two fuzz properties of spec §8 (R10.4).

**Architecture:** A new folder `packages/typed_graphql/lib/src/language/visitor/` holds `VisitAction`, `AstVisitor`, `AstWalker`, `ParallelVisitor` and `AstTransformer`. Walker and transformer drive any node through `Node.children` and `withChildren` with their own stack, never recursion. Schema coordinates get a sealed family in `ast/schema_coordinate.dart`, a `SchemaCoordinateLexer` beside the document `Lexer` (both implement the new `TokenSource`, which `TokenCursor` reads), and a `SchemaCoordinateParser` collaborator. `diagnostics/source_excerpt.dart` ports `printSourceLocation`. In `packages/typed_graphql_conformance`, the ported suites go under `test/language/`, the fuzzers under `test/fuzz/`, and `mapping/language.csv` grows from 182 to 233 rows.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, patterns, sealed classes, records), `package:test`, `package:meta`. graphql-js 17.0.2 (commit `ee5ce41`, fetched into `reference/` by `tool/fetch_reference.sh`) is the reference. Chrome runs dart2js and dart2wasm.

**Spec:** `docs/superpowers/specs/2026-10-14-m2-language-design.md` (the M2b row of section 1, sections 2, 6, 7, 8 and 9), section 2 of `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`, and `docs/requirements.md` (R0.3, R0.6, R0.7, R1.9, R1.10, R1.11, R10.2, R10.3, R10.4).

**Base:** `main` at `164f77c` (M2a merged). Work on a branch `m2b-language-tools` in a worktree.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, not even a private one; a helper in a test is a local closure inside `main` or a method of a class.
- The core stays pure Dart: no new dependency, and no `dart:io` in `lib/`. The language tests run on the VM, as exe, with dart2js and with dart2wasm (R0.6). A test that needs `dart:io` (the fuzzers read the environment, the table check reads files) starts with `@TestOn('vm')` and then `library;`.
- No new package dependency in this stage. The conformance package depends on `typed_graphql` only (spec §8).
- Bad input never throws (R0.3). A problem in a document or a coordinate is a `Diagnostic` with a code from `DiagnosticCode`; M2b adds no code. Only programmer errors throw, as `ArgumentError`, `RangeError` or `StateError`.
- Public API goes through the barrel `lib/typed_graphql.dart`. `SchemaCoordinateParser` and `SourceReader` stay out of it.
- Messages are graphql-js's text without the `Syntax Error: ` prefix, so the ported suites compare them unchanged.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- `CLAUDE.md` and the package `CHANGELOG.md` change in the task that changes what they describe; the steps give those changes.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message given in the task. Executors append the trailers their session instructs.
- Run every command from the repository root unless a step says otherwise. Use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are given as unified diffs against the tree the earlier tasks leave. Each was applied in that order while the plan was verified. If a hunk does not apply, the tree has drifted: stop and report it.

## Review Focus

These are the five failure modes most likely to hurt someone who walks, rewrites or reports on untrusted documents. Each one has tests that pin it, in the task named.

1. **Deep trees in the traversal tools (R1.9, R1.6).** A walk or a rewrite of a tree nested 100 000 levels deep, which a program can build without the parser's `maxDepth`, must finish without a stack overflow, on the VM and on the web. Pinned in:
   - Task 1: `walks a tree 100 000 levels deep without overflowing the stack`;
   - Task 3: `rewrites a tree 100 000 levels deep without overflowing`;
   - Task 13 runs both with dart2js and dart2wasm.
2. **Coordinate text that is almost right (R1.11, R0.3).** White space, a comment, a comma, a line break, document syntax or nothing at all must each give one diagnostic at the right place, never a silently trimmed coordinate; and a lone `.` in a document must stay an error. Pinned in:
   - Task 6: `white space is an invalid character, and lexing goes on`, `a line terminator, a comma and a comment are invalid too`, `document punctuators, digits and spreads are invalid`, `a lone surrogate is GQL002, as in a document`, `a single dot in a document is an unexpected character`;
   - Task 7: `ignored tokens around a coordinate are errors`, `document syntax is not a coordinate`, `empty text is a missing name`, `a third name is an error at the second dot`.
3. **Edits that cannot stand (spec §6).** Removing a required child must be a `StateError`, not a broken tree; a rewrite that changes nothing must keep the instance; the original tree must never change. Pinned in:
   - Task 3: `removing a required child is a StateError`, `keeps the instance of a tree where nothing changes`, `replaces a node and leaves the original tree as it was`, `null removes an optional child, such as an alias`;
   - Task 5: `a member coordinate needs both names`.
4. **Excerpts of awkward lines.** A minified document is one long line; a caret at its very end, a span on the first or last line, and a two-digit line number must print as graphql-js prints them, and never throw. Pinned in:
   - Task 9: `cuts a line longer than 120 units into 80-unit pieces`, `a caret after the last piece of a long line shows no piece after`, `leaves out the lines a document does not have`, `pads every prefix to the widest line number`, and the ported `printLocation-test.ts`.
5. **Hostile text through every entry point (R0.3, R1.6, spec §8).** Random and mutated text through `parse`, `parseValue` (both modes), `parseTypeRef` and `parseSchemaCoordinate` must never throw, must end, must report at most `maxErrors + 1` diagnostics, and every diagnostic must have an excerpt. Pinned in:
   - Task 12: `random text never throws and reports a bounded list`, `mutated documents never throw and report a bounded list`, `a long hostile text stays within the sink limit`.

## M2b design decisions

These were made while writing this plan; the spec leaves them open.

1. **`leave` returns nothing** (spec §6). graphql-js's `leave` can return `BREAK`, `false` or an edit, and its visitor functions receive `key`, `parent`, `path` and `ancestors`. Here a visitor only reads, through `enter(node)` and `leave(node)`; edits belong to `AstTransformer`. The graphql-js tests that need the rest are `skipped` (see "Spec deviations and findings", 1).
2. **The walk:** depth-first in `children` order. `skip` neither enters the children nor calls `leave` for the node, and `stop` calls nothing more, as graphql-js does for `false` and `BREAK` returned from `enter`.
3. **No recursion** in `AstWalker` and `AstTransformer`: each keeps a stack of frames. dart2js and dart2wasm have far smaller stacks than the VM, and a program can build a tree deeper than the parser's `maxDepth`.
4. **`ParallelVisitor` is an `AstVisitor`,** not a walker. It keeps, per visitor, the node it skipped and whether it stopped, as `visitInParallel` does; so it is stateful and each walk needs a new one.
5. **`AstTransformer` is bottom-up only.** `rewrite(node)` sees the node with its children already rewritten, and returns the node, a replacement or `null`. The parent is rebuilt with M2a's `withChildren`, so `ChildReader` stays internal (this closes M2a deviation 6): `null` is dropped from a list, clears an optional child, and is a `StateError` for a required one. Unchanged branches keep their instance.
6. **Schema coordinates are a sealed family** with graphql-js's field names (`name`, `memberName`, `fieldName`, `argumentName`). `Name` children keep their offsets, so a later resolver (M3) can point at the name that does not resolve.
7. **A second lexer, not a mode.** `SchemaCoordinateLexer` mirrors graphql-js's: names and `( ) . : @`, and no ignored tokens. Both lexers implement the new `TokenSource`, so `TokenCursor` and its `expect*` and `fail` serve both grammars. `TokenKind.dot` (described `"."`) is new; the document lexer never produces it, and a lone `.` there is still `GQL001` "Unexpected character". Other characters in a coordinate are graphql-js's "Invalid character" with `GQL001`, and `GQL002` for a lone surrogate as in a document; no new code.
8. **`ParserOptions` do not apply to a coordinate.** A coordinate has no nesting and no working-draft syntax, and its lexer counts no tokens (`isLimitReached` is always `false`).
9. **Printing:** a coordinate prints as written, in both forms, and skips `Minifier`, whose document lexer would reject the `.`. Meta-fields (`Type.__metafield`) and introspection types parse and print; spec §7's "have no coordinate" is a resolution rule for M3, and graphql-js parses them too.
10. **`SourceExcerpt`** ports graphql-js's `printSourceLocation`: the line before, the line with a caret, the line after, with padded line numbers, and lines over 120 units cut into 80-unit pieces. `SourceSpan.excerpt` gives it at the span's start. `Diagnostic.toString` does not change.
11. **The fuzzers are test code** in `test/fuzz/` of the conformance package: a fixed seed (`20261014`) and count in CI, `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` for more. The round-trip generators build only trees that graphql-js itself round-trips (Task 11 lists the rules); a check ties them to every node kind of `NodeSamples`, so a generator cannot quietly stop covering a kind.
12. **The table check reads the directory.** M2a checked the files listed in `portedFiles`; Task 12 removes the list, and the check fails for any graphql-js language test file, or test, without a row (spec §8). `CsvTable` now rejects a record wider than its header (Task 4), because an unquoted comma in a reason had cut the reason short without any test failing.

## Spec deviations and findings

Bring these to the user with the plan.

1. **Fourteen graphql-js visitor tests are skipped** because `leave` returns nothing and visitor functions get the node only (decision 1): `validates path argument`, `validates ancestors argument`, editing a node or the root on enter and leave, `ignores false returned on leave`, `visits edited node`, early exit while leaving (three tests), the two `visitInParallel` editing tests, the visitor key map, and the two fragment-argument tests (R1.14). The two editing tests whose result a bottom-up rewrite reproduces are `adapted` to `AstTransformer`.
2. **`Source` has no `locationOffset`.** The two `printLocation-test.ts` tests that use it are adapted (eight leading line breaks give the same line numbers); `source-test.ts` is skipped (`locationOffset` validation and `Symbol.toStringTag`), as are M2a's two lexer file-context tests.
3. **Three graphql-js files test JavaScript itself:** `kind-test.ts` (a TypeScript namespace), `diagnostics-test.ts` (Node.js `diagnostics_channel`) and the `toStringTag` tests. They are skipped with that reason. `predicates-test.ts` is adapted: the sealed families are the predicates.
4. **A grammar ambiguity, shared with graphql-js:** in a document, a `{` after a body-less type extension (`extend enum E @d`) opens that extension's body, so a shorthand query can only come first. The round-trip fuzzer found it; the generator follows the rule, and `CLAUDE.md` records it.
5. **`TokenKind` gains `dot`.** Code that switches over `TokenKind` exhaustively must handle it; nothing is published yet, so no changelog entry is marked breaking.
6. **M2a's deferred review minors** are not needed by any task here. Two are absorbed: the barrel's library comment (Task 13), and the CSV reader, which now rejects wide records (Task 4). Still open: `Node.children` of five node kinds returns a growable list although documented as read-only (walker and transformer only read it); `GraphqlJsSuite` reads single-quoted test names only (every current file passes the coverage check); `CsvTable` drops a quoted empty record at the end of the text.
7. **What could not be verified locally:** the CI matrix on exactly 3.13.0, macOS and Windows. Everything else in the green check and in Task 13 ran on Linux with Dart 3.13.1 and Chrome.

## File map

| Path | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/language/visitor/ast_visitor.dart` | Receives the nodes of a syntax tree as an `AstWalker` walks it (R1.9) | 1 |
| `packages/typed_graphql/lib/src/language/visitor/ast_walker.dart` | Walks a syntax tree depth-first through [Node.children] and calls an [AstVisitor] on the way down and on the way up | 1 |
| `packages/typed_graphql/lib/src/language/visitor/visit_action.dart` | What a walk does after `AstVisitor.enter` returns, as graphql-js's `visit` does with `undefined`, `false` and `BREAK` | 1 |
| `packages/typed_graphql/test/language/visitor/ast_walker_test.dart` | Tests | 1 |
| `packages/typed_graphql/test/language/visitor/visit_log.dart` | A visitor that writes each call to [entries], as `enter Field b` or `leave Name b`, after its [label] | 1 |
| `packages/typed_graphql/lib/src/language/visitor/parallel_visitor.dart` | Runs several visitors in one walk (R1.9), as graphql-js's `visitInParallel` does | 2 |
| `packages/typed_graphql/test/language/visitor/parallel_visitor_test.dart` | Tests | 2 |
| `packages/typed_graphql/lib/src/language/visitor/ast_transformer.dart` | Rebuilds a syntax tree bottom-up (R1.9) | 3 |
| `packages/typed_graphql/test/language/visitor/ast_transformer_test.dart` | Tests | 3 |
| `packages/typed_graphql_conformance/test/language/visitor/visitor_kitchen_sink_test.dart` | Tests | 4 |
| `packages/typed_graphql_conformance/test/language/visitor/visitor_test.dart` | Tests | 4 |
| `packages/typed_graphql_conformance/test/support/visit_recorder.dart` | The visitor of graphql-js's visitor suite | 4 |
| `packages/typed_graphql/lib/src/language/ast/schema_coordinate.dart` | A schema coordinate | 5 |
| `packages/typed_graphql/test/language/ast/schema_coordinate_test.dart` | Tests | 5 |
| `packages/typed_graphql/lib/src/language/lexer/schema_coordinate_lexer.dart` | Turns a schema coordinate into tokens | 6 |
| `packages/typed_graphql/lib/src/language/lexer/token_source.dart` | A stream of tokens the parser reads | 6 |
| `packages/typed_graphql/test/language/lexer/schema_coordinate_lexer_test.dart` | Tests | 6 |
| `packages/typed_graphql/lib/src/language/parser/schema_coordinate_parser.dart` | Parses the schema coordinate grammar (September2025 §2 "Schema Coordinates"), as graphql-js's `parseSchemaCoordinate` does | 7 |
| `packages/typed_graphql/test/language/parser/parse_schema_coordinate_test.dart` | Tests | 7 |
| `packages/typed_graphql/test/language/printer/print_schema_coordinate_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/language/parser/parser_schema_coordinate_test.dart` | Tests | 8 |
| `packages/typed_graphql_conformance/test/language/schema_coordinate_lexer_test.dart` | Tests | 8 |
| `packages/typed_graphql/lib/src/diagnostics/source_excerpt.dart` | Shows a location in a [Source] as graphql-js's `printSourceLocation` does, character for character | 9 |
| `packages/typed_graphql/test/diagnostics/source_excerpt_test.dart` | Tests | 9 |
| `packages/typed_graphql_conformance/test/language/print_location_test.dart` | Tests | 9 |
| `packages/typed_graphql_conformance/test/language/predicates_test.dart` | Tests | 10 |
| `packages/typed_graphql_conformance/test/support/node_samples.dart` | One parsed node of each graphql-js `Kind`, taken from the kitchen sinks, a few values and types they lack, and the five schema coordinates | 10 |
| `packages/typed_graphql_conformance/test/fuzz/fuzz_budget.dart` | How much a fuzzer runs (R10.4) | 11 |
| `packages/typed_graphql_conformance/test/fuzz/random_executable.dart` | Random operations and fragments for the round-trip fuzzer | 11 |
| `packages/typed_graphql_conformance/test/fuzz/random_parts.dart` | Random names, values, types and directives for the round-trip fuzzer | 11 |
| `packages/typed_graphql_conformance/test/fuzz/random_type_system.dart` | Random type-system definitions and extensions for the round-trip fuzzer, the working draft's directive extensions included | 11 |
| `packages/typed_graphql_conformance/test/fuzz/round_trip_fuzz_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/fuzz/hostile_text_fuzz_test.dart` | Tests | 12 |
| `packages/typed_graphql_conformance/test/language/block_string_fuzz_test.dart` | Tests | 12 |
| `CLAUDE.md` | Repository guide: the visitor folder, coordinates, excerpts, the M2b lessons, the status | 1, 2, 3, 6, 7, 9, 13 |
| `packages/typed_graphql/CHANGELOG.md` | Core changelog | 1, 2, 3, 5, 6, 7, 9 |
| `packages/typed_graphql/lib/typed_graphql.dart` | The barrel: the new public API | 1, 2, 3, 5, 6, 9, 13 |
| `packages/typed_graphql_conformance/CHANGELOG.md` | Conformance changelog | 4, 8, 9, 10, 11, 12 |
| `packages/typed_graphql_conformance/mapping/language.csv` | The mapping table: 182 rows to 233 | 4, 8, 9, 10, 12 |
| `packages/typed_graphql_conformance/test/support/csv_table.dart` | Rejects a record wider than the header | 4 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | `GQL001` also covers a character outside a coordinate | 6 |
| `packages/typed_graphql/lib/src/language/lexer/lexer.dart` | Implements `TokenSource`; names through `SourceReader.name` | 6 |
| `packages/typed_graphql/lib/src/language/lexer/source_reader.dart` | `name(start)`, shared by both lexers | 6 |
| `packages/typed_graphql/lib/src/language/lexer/token_kind.dart` | `TokenKind.dot` | 6 |
| `packages/typed_graphql/lib/src/language/parser/parser.dart` | `parseSchemaCoordinate`; `_complete` shared by the element entry points | 7 |
| `packages/typed_graphql/lib/src/language/parser/token_cursor.dart` | Reads any `TokenSource` | 7 |
| `packages/typed_graphql/lib/src/language/printer/printer.dart` | Prints coordinates | 7 |
| `packages/typed_graphql_conformance/test/support/ast_json.dart` | The five coordinate kinds | 8 |
| `packages/typed_graphql_conformance/test/support/lexer_port.dart` | Coordinate lexing helpers; the printed syntax error | 8, 9 |
| `packages/typed_graphql_conformance/test/support/parser_port.dart` | Coordinate parsing helpers | 8 |
| `packages/typed_graphql/lib/src/diagnostics/source_span.dart` | `excerpt` | 9 |
| `packages/typed_graphql_conformance/test/support/error_json.dart` | `printed`: graphql-js's `String(error)` | 9 |
| `packages/typed_graphql_conformance/README.md` | Conformance README: "Fuzzing", the coverage check | 11, 12, 13 |
| `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart` | `files`: every graphql-js language test file | 12 |
| `README.md` | Repository README: status and the package table | 13 |
| `docs/superpowers/HANDOFF.md` | Where the work stands | 13 |
| `packages/typed_graphql/README.md` | Core README: "Visiting and rewriting" | 13 |

## The green check

Every task ends with this check. "Green" means each command exits 0.

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages test
dart analyze --fatal-infos
dart test
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
```

With `reference/` fetched, the conformance suite also runs the coverage checks. Run `tool/fetch_reference.sh` once before Task 4.

---

### Task 1: Walk syntax trees with AstVisitor

R1.9 and spec §6: a visitor with no-op defaults and a walker that drives it through `Node.children`.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/visitor/ast_visitor.dart`, `packages/typed_graphql/lib/src/language/visitor/ast_walker.dart`, `packages/typed_graphql/lib/src/language/visitor/visit_action.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/visitor/ast_walker_test.dart`, `packages/typed_graphql/test/language/visitor/visit_log.dart`

**Interfaces:**
- Consumes: M2a: `Node` (`children`), the AST classes, `Parser`; the test helper `Parsed` in `test/language/parser/parsed.dart`.
- Produces:
  - `enum VisitAction { next, skip, stop }`;
  - `abstract class AstVisitor` with `const AstVisitor()`, `VisitAction enter(Node node)` (returns `VisitAction.next`) and `void leave(Node node)` (does nothing);
  - `final class AstWalker` with `const AstWalker()` and `void walk(Node root, AstVisitor visitor)`: depth-first in `children` order; `skip` neither enters the children nor leaves the node; `stop` ends the walk and leaves nothing;
  - test helper `VisitLog(List<String> entries, {String label = '', String? skipAt, String? stopAt})` in `test/language/visitor/visit_log.dart`, with `static String describe(Node node)`, such as `Field a`, `Name x` or `Document`.

- [ ] **Step 1: Write the failing tests**

`VisitLog` records every call as `enter Field b` / `leave Name b`; it can skip or stop at one described node. Task 2 reuses it.

Create `packages/typed_graphql/test/language/visitor/visit_log.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// A visitor that writes each call to [entries], as `enter Field b` or
/// `leave Name b`, after its [label]; it skips or stops at the node whose
/// description is [skipAt] or [stopAt].
final class VisitLog extends AstVisitor {
  /// Creates a log that writes to [entries].
  VisitLog(this.entries, {this.label = '', this.skipAt, this.stopAt});

  /// Where the calls are written, in call order.
  final List<String> entries;

  /// Written before each entry, such as `no-a `; empty by default.
  final String label;

  /// The description of the node [enter] skips.
  final String? skipAt;

  /// The description of the node [enter] stops at.
  final String? stopAt;

  @override
  VisitAction enter(Node node) {
    final description = describe(node);
    entries.add('${label}enter $description');
    if (description == stopAt) {
      return VisitAction.stop;
    }
    return description == skipAt ? VisitAction.skip : VisitAction.next;
  }

  @override
  void leave(Node node) => entries.add('${label}leave ${describe(node)}');

  /// [node] as an entry names it: its kind, and the name of a field or
  /// the value of a name or a number.
  static String describe(Node node) => switch (node) {
    Name(:final value) => 'Name $value',
    Field(:final name) => 'Field ${name.value}',
    IntValue(:final value) => 'IntValue $value',
    Document() => 'Document',
    OperationDefinition() => 'OperationDefinition',
    SelectionSet() => 'SelectionSet',
    Argument() => 'Argument',
    ListValue() => 'ListValue',
    _ => 'Node',
  };
}
```

Create `packages/typed_graphql/test/language/visitor/ast_walker_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';
import 'visit_log.dart';

void main() {
  const walker = AstWalker();

  List<String> walk(String text, {String? skipAt, String? stopAt}) {
    final entries = <String>[];
    walker.walk(
      Parsed(text).document,
      VisitLog(entries, skipAt: skipAt, stopAt: stopAt),
    );
    return entries;
  }

  test('enters and leaves every node depth-first in children order', () {
    expect(walk('{ a(x: 1) }'), [
      'enter Document',
      'enter OperationDefinition',
      'enter SelectionSet',
      'enter Field a',
      'enter Name a',
      'leave Name a',
      'enter Argument',
      'enter Name x',
      'leave Name x',
      'enter IntValue 1',
      'leave IntValue 1',
      'leave Argument',
      'leave Field a',
      'leave SelectionSet',
      'leave OperationDefinition',
      'leave Document',
    ]);
  });

  test('skip passes over the children and does not leave the node', () {
    expect(walk('{ a { x } b }', skipAt: 'Field a'), [
      'enter Document',
      'enter OperationDefinition',
      'enter SelectionSet',
      'enter Field a',
      'enter Field b',
      'enter Name b',
      'leave Name b',
      'leave Field b',
      'leave SelectionSet',
      'leave OperationDefinition',
      'leave Document',
    ]);
  });

  test('stop ends the walk without leaving any node', () {
    expect(walk('{ a { x } b }', stopAt: 'Name x'), [
      'enter Document',
      'enter OperationDefinition',
      'enter SelectionSet',
      'enter Field a',
      'enter Name a',
      'leave Name a',
      'enter SelectionSet',
      'enter Field x',
      'enter Name x',
    ]);
  });

  test('a visitor with the default methods walks without effect', () {
    expect(
      () => walker.walk(Parsed('{ a }').document, const _DefaultVisitor()),
      returnsNormally,
    );
  });

  test('stop on the root enters nothing else', () {
    expect(walk('{ a }', stopAt: 'Document'), ['enter Document']);
  });

  test('walks a tree 100 000 levels deep without overflowing the stack', () {
    Value value = const IntValue('1');
    for (var i = 0; i < 100000; i++) {
      value = ListValue([value]);
    }
    var entered = 0;
    walker.walk(value, _Counter(() => entered++));
    expect(entered, 100001);
  });
}

/// A visitor that keeps the default [enter] and [leave].
final class _DefaultVisitor extends AstVisitor {
  const _DefaultVisitor();
}

/// A visitor that calls [onEnter] for each node it enters.
final class _Counter extends AstVisitor {
  _Counter(this.onEnter);

  final void Function() onEnter;

  @override
  VisitAction enter(Node node) {
    onEnter();
    return VisitAction.next;
  }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/visitor/ast_walker_test.dart)
```

Expected: FAIL. The files do not compile: `Error: Type 'AstVisitor' not found.`, `Error: Method not found: 'AstWalker'.` and `Error: Type 'VisitAction' not found.`

- [ ] **Step 3: Write the implementation**

The walk keeps its own stack of frames, one per entered node, instead of recursing, so a deep tree cannot overflow the stack on the VM or on the web.

Create `packages/typed_graphql/lib/src/language/visitor/visit_action.dart`:

```dart
/// What a walk does after `AstVisitor.enter` returns, as graphql-js's
/// `visit` does with `undefined`, `false` and `BREAK`.
enum VisitAction {
  /// Visit the node's children, then leave the node.
  next,

  /// Pass over the node's children; the node is not left either.
  skip,

  /// End the walk: no other node is entered or left.
  stop,
}
```

Create `packages/typed_graphql/lib/src/language/visitor/ast_visitor.dart`:

```dart
import '../ast/node.dart';
import 'visit_action.dart';

/// Receives the nodes of a syntax tree as an `AstWalker` walks it (R1.9):
/// [enter] before a node's children, [leave] after them.
///
/// Both do nothing by default, so a visitor overrides only what it needs
/// and tells node kinds apart with a `switch` over the sealed families.
abstract class AstVisitor {
  /// Creates a visitor.
  const AstVisitor();

  /// Called before the children of [node]. [VisitAction.next] goes into
  /// them, [VisitAction.skip] passes over them without calling [leave] for
  /// [node], and [VisitAction.stop] ends the walk.
  VisitAction enter(Node node) => VisitAction.next;

  /// Called after the children of [node], when [enter] returned
  /// [VisitAction.next] for it.
  void leave(Node node) {}
}
```

Create `packages/typed_graphql/lib/src/language/visitor/ast_walker.dart`:

```dart
import '../ast/node.dart';
import 'ast_visitor.dart';
import 'visit_action.dart';

/// Walks a syntax tree depth-first through [Node.children] and calls an
/// [AstVisitor] on the way down and on the way up.
///
/// The walk keeps its own stack instead of recursing, so a tree built in
/// code or parsed without `maxDepth` cannot overflow the call stack.
final class AstWalker {
  /// Creates a walker; it keeps no state between walks.
  const AstWalker();

  /// Walks [root] and everything under it, in the order of
  /// [Node.children], as [visitor] directs.
  void walk(Node root, AstVisitor visitor) {
    final frames = <_Frame>[];
    var action = _enter(root, visitor, frames);
    while (action != VisitAction.stop && frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.hasNext) {
        action = _enter(frame.takeNext(), visitor, frames);
      } else {
        frames.removeLast();
        visitor.leave(frame.node);
      }
    }
  }

  VisitAction _enter(Node node, AstVisitor visitor, List<_Frame> frames) {
    final action = visitor.enter(node);
    if (action == VisitAction.next) {
      frames.add(_Frame(node));
    }
    return action;
  }
}

/// A node being walked and how many of its children were entered.
final class _Frame {
  _Frame(this.node) : _children = node.children;

  final Node node;
  final List<Node> _children;
  int _next = 0;

  bool get hasNext => _next < _children.length;

  Node takeNext() => _children[_next++];
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,6 +42,9 @@ export 'src/language/parser/parse_result.dart';
 export 'src/language/parser/parser.dart';
 export 'src/language/parser/parser_options.dart';
 export 'src/language/printer/printer.dart';
+export 'src/language/visitor/ast_visitor.dart';
+export 'src/language/visitor/ast_walker.dart';
+export 'src/language/visitor/visit_action.dart';
 export 'src/protocol/decode_result.dart';
 export 'src/protocol/graphql_error.dart';
 export 'src/protocol/graphql_request.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/visitor/ast_walker_test.dart)
```

Expected: `+6: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -47,3 +47,5 @@
 - Parser recovery no longer mistakes a directive named like a keyword
   (`@query`) for the start of a definition.
 - `NonNullType.withChildren` throws a `StateError` in release builds too.
+- `AstVisitor`, `VisitAction` and `AstWalker`: a depth-first walk of any
+  syntax tree with `enter` and `leave`, which can skip a subtree or stop.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -127,6 +127,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `Printer(isMinified: true)` passes the canonical text through `Minifier`
   (graphql-js's `stripIgnoredCharacters`: a space only between two
   non-punctuators or before `...`, block strings in their shortest form).
+- `visitor/`: `AstWalker().walk(root, visitor)` walks depth-first through
+  `children` with its own stack (no recursion), calling
+  `AstVisitor.enter` (returns `VisitAction.next`, `skip` or `stop`) and
+  `leave`; a skipped node is not left, a stop leaves nothing.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/visitor/ast_visitor.dart packages/typed_graphql/lib/src/language/visitor/ast_walker.dart packages/typed_graphql/lib/src/language/visitor/visit_action.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/visitor/ast_walker_test.dart packages/typed_graphql/test/language/visitor/visit_log.dart
git commit -q -m "feat(typed_graphql): walk syntax trees with AstVisitor"
```

### Task 2: Run visitors in parallel

R1.9: graphql-js's `visitInParallel` as an `AstVisitor`.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/visitor/parallel_visitor.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/visitor/parallel_visitor_test.dart`

**Interfaces:**
- Consumes: Task 1: `AstVisitor`, `VisitAction`, `AstWalker`, `VisitLog`.
- Produces:
  - `final class ParallelVisitor extends AstVisitor` with `ParallelVisitor(List<AstVisitor> visitors)` and `final List<AstVisitor> visitors` (unmodifiable). It keeps per-visitor state, so a walk needs a new one.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/visitor/parallel_visitor_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';
import 'visit_log.dart';

void main() {
  const walker = AstWalker();

  /// The entries of [logs] after one parallel walk of [text].
  List<String> walkInParallel(String text, List<VisitLog> logs) {
    walker.walk(Parsed(text).document, ParallelVisitor(logs));
    return logs.first.entries;
  }

  /// The entries of [log] after walking [text] with it alone.
  List<String> walkAlone(String text, VisitLog log) {
    walker.walk(Parsed(text).document, log);
    return log.entries;
  }

  test('one visitor sees what it sees alone, skips included', () {
    const text = '{ a { x } b }';
    expect(
      walkInParallel(text, [VisitLog([], skipAt: 'Field a')]),
      walkAlone(text, VisitLog([], skipAt: 'Field a')),
    );
  });

  test('visitors skip different subtrees, each called in turn', () {
    final entries = <String>[];
    walkInParallel('{ a { x } b { y } }', [
      VisitLog(entries, label: 'no-a ', skipAt: 'Field a'),
      VisitLog(entries, label: 'no-b ', skipAt: 'Field b'),
    ]);
    expect(entries.where((entry) => entry.contains('Name')), [
      'no-b enter Name a',
      'no-b leave Name a',
      'no-b enter Name x',
      'no-b leave Name x',
      'no-a enter Name b',
      'no-a leave Name b',
      'no-a enter Name y',
      'no-a leave Name y',
    ]);
    expect(entries.take(2), ['no-a enter Document', 'no-b enter Document']);
    expect(entries.last, 'no-b leave Document');
  });

  test('a stopped visitor is not called again while the others go on', () {
    final entries = <String>[];
    walkInParallel('{ a { y } b { x } }', [
      VisitLog(entries, label: 'break-a ', stopAt: 'Name a'),
      VisitLog(entries, label: 'break-b ', stopAt: 'Name b'),
    ]);
    expect(
      entries.where((entry) => entry.startsWith('break-a')).last,
      'break-a enter Name a',
    );
    expect(entries.sublist(entries.length - 3), [
      'break-b leave Field a',
      'break-b enter Field b',
      'break-b enter Name b',
    ]);
  });

  test('enter skips a node that every running visitor skips', () {
    final field = Parsed('{ a }').document.definitions.single;
    final parallel = ParallelVisitor([
      VisitLog([], skipAt: 'OperationDefinition'),
      VisitLog([], skipAt: 'OperationDefinition'),
    ]);
    expect(parallel.enter(field), VisitAction.skip);
  });

  test('a visitor that skipped a node runs again after it', () {
    final entries = <String>[];
    walkInParallel('{ a b }', [
      VisitLog(entries, skipAt: 'Field a'),
      VisitLog(<String>[], skipAt: 'Field a'),
    ]);
    expect(entries, contains('enter Name b'));
  });

  test('enter stops the walk once every visitor stopped', () {
    final document = Parsed('{ a }').document;
    final parallel = ParallelVisitor([
      VisitLog([], stopAt: 'Document'),
      VisitLog([], stopAt: 'OperationDefinition'),
    ]);
    expect(parallel.enter(document), VisitAction.next);
    expect(parallel.enter(document.definitions.single), VisitAction.stop);
  });

  test('an empty list stops at once', () {
    expect(
      ParallelVisitor(const []).enter(const Name('a')),
      VisitAction.stop,
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/visitor/parallel_visitor_test.dart)
```

Expected: FAIL. `Error: Method not found: 'ParallelVisitor'.`

- [ ] **Step 3: Write the implementation**

Each visitor has a slot: the node it skipped (it runs again once the walk leaves that node) and whether it stopped. `enter` returns `skip` only when no visitor is still running at the node, and `stop` only when every visitor stopped, as graphql-js's `visitInParallel` does.

Create `packages/typed_graphql/lib/src/language/visitor/parallel_visitor.dart`:

```dart
import '../ast/node.dart';
import 'ast_visitor.dart';
import 'visit_action.dart';

/// Runs several visitors in one walk (R1.9), as graphql-js's
/// `visitInParallel` does: each visitor is called exactly as if it walked
/// the tree alone.
///
/// A visitor that skips a node is not called again until the walk leaves
/// that node; a visitor that stops is not called again. The walk itself
/// passes over a node that every running visitor skips, and ends when
/// every visitor has stopped (at once for an empty list). It keeps that
/// state as it goes, so each walk needs a new one.
final class ParallelVisitor extends AstVisitor {
  /// Creates a visitor that runs [visitors], in order, at every node.
  ParallelVisitor(List<AstVisitor> visitors)
    : visitors = List.unmodifiable(visitors),
      _skippedAt = List.filled(visitors.length, null),
      _isStopped = List.filled(visitors.length, false);

  /// The visitors, in the order they are called at each node.
  final List<AstVisitor> visitors;

  /// For each visitor, the node whose children it skips; null while it
  /// runs.
  final List<Node?> _skippedAt;

  /// For each visitor, whether it stopped.
  final List<bool> _isStopped;

  @override
  VisitAction enter(Node node) {
    var isAnyRunning = false;
    for (var i = 0; i < visitors.length; i++) {
      if (_isStopped[i] || _skippedAt[i] != null) {
        continue;
      }
      switch (visitors[i].enter(node)) {
        case VisitAction.next:
          isAnyRunning = true;
        case VisitAction.skip:
          _skippedAt[i] = node;
        case VisitAction.stop:
          _isStopped[i] = true;
      }
    }
    if (_isStopped.every((isStopped) => isStopped)) {
      return VisitAction.stop;
    }
    return isAnyRunning ? VisitAction.next : _skipAll(node);
  }

  @override
  void leave(Node node) {
    for (var i = 0; i < visitors.length; i++) {
      if (_isStopped[i]) {
        continue;
      }
      if (_skippedAt[i] == null) {
        visitors[i].leave(node);
      } else if (identical(_skippedAt[i], node)) {
        _skippedAt[i] = null;
      }
    }
  }

  /// The walk will not leave [node], so the visitors that skipped it run
  /// again after it.
  VisitAction _skipAll(Node node) {
    for (var i = 0; i < visitors.length; i++) {
      if (identical(_skippedAt[i], node)) {
        _skippedAt[i] = null;
      }
    }
    return VisitAction.skip;
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -44,6 +44,7 @@ export 'src/language/parser/parser_options.dart';
 export 'src/language/printer/printer.dart';
 export 'src/language/visitor/ast_visitor.dart';
 export 'src/language/visitor/ast_walker.dart';
+export 'src/language/visitor/parallel_visitor.dart';
 export 'src/language/visitor/visit_action.dart';
 export 'src/protocol/decode_result.dart';
 export 'src/protocol/graphql_error.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/visitor/parallel_visitor_test.dart)
```

Expected: `+7: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -49,3 +49,5 @@
 - `NonNullType.withChildren` throws a `StateError` in release builds too.
 - `AstVisitor`, `VisitAction` and `AstWalker`: a depth-first walk of any
   syntax tree with `enter` and `leave`, which can skip a subtree or stop.
+- `ParallelVisitor`: several visitors in one walk, each called as if it
+  walked alone.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -131,6 +131,8 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `children` with its own stack (no recursion), calling
   `AstVisitor.enter` (returns `VisitAction.next`, `skip` or `stop`) and
   `leave`; a skipped node is not left, a stop leaves nothing.
+  `ParallelVisitor` keeps a skip or stop state per visitor, as graphql-js's
+  `visitInParallel`; it is stateful, so use one per walk.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/visitor/parallel_visitor.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/visitor/parallel_visitor_test.dart
git commit -q -m "feat(typed_graphql): run visitors in parallel"
```

### Task 3: Rewrite syntax trees with AstTransformer

R1.9 and spec §6: a bottom-up rewrite that keeps unchanged branches.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/visitor/ast_transformer.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/visitor/ast_transformer_test.dart`

**Interfaces:**
- Consumes: M2a: `Node.withChildren` (keeps the instance when nothing changed; `StateError` from the internal `ChildReader` on a missing required child).
- Produces:
  - `abstract class AstTransformer` with `const AstTransformer()`, `Node? rewrite(Node node)` (returns `node`) and `Node? transform(Node root)`: the rewritten tree, the same instance when nothing changed, or `null` when the root is removed.

- [ ] **Step 1: Write the failing tests**

The tests use `Parsed` from `test/language/parser/parsed.dart` (M2a). `_AddTypename` is the code-generation case of spec §6.

Create `packages/typed_graphql/test/language/visitor/ast_transformer_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const printer = Printer(isMinified: true);

  String print(Node? node) => node == null ? 'removed' : printer.print(node);

  test('keeps the instance of a tree where nothing changes', () {
    final document = Parsed('{ a { b } c(x: [1, 2]) }').document;
    expect(_Rewrite((node) => node).transform(document), same(document));
  });

  SelectionSet selectionSetOf(Node? node) => switch (node) {
    Document(definitions: [OperationDefinition(:final selectionSet)]) =>
      selectionSet,
    _ => fail('expected a document with one operation, got $node'),
  };

  test('replaces a node and leaves the original tree as it was', () {
    final document = Parsed('{ a b { x } }').document;
    final rewritten = _Rewrite(
      (node) => node is Name && node.value == 'x' ? const Name('y') : node,
    ).transform(document);
    expect(print(rewritten), '{a b{y}}');
    expect(print(document), '{a b{x}}');
  });

  test('rebuilds the changed branch and keeps the unchanged one', () {
    final document = Parsed('{ a b { x } }').document;
    final rewritten = _Rewrite(
      (node) => node is Name && node.value == 'x' ? const Name('y') : node,
    ).transform(document);
    final [fieldA, fieldB] = selectionSetOf(document).selections;
    final [newFieldA, newFieldB] = selectionSetOf(rewritten).selections;
    expect(newFieldA, same(fieldA));
    expect(newFieldB, isNot(same(fieldB)));
  });

  test('null removes a node from its list', () {
    final document = Parsed('{ a, b, c { a, b, c } }').document;
    final rewritten = _Rewrite(
      (node) => node is Field && node.name.value == 'b' ? null : node,
    ).transform(document);
    expect(print(rewritten), '{a c{a c}}');
  });

  test('null removes an optional child, such as an alias', () {
    final document = Parsed('{ b: a }').document;
    final rewritten = _Rewrite(
      (node) => node is Name && node.value == 'b' ? null : node,
    ).transform(document);
    expect(print(rewritten), '{a}');
  });

  test('removing a required child is a StateError', () {
    final document = Parsed('{ a(x: 1) }').document;
    final transformer = _Rewrite((node) => node is IntValue ? null : node);
    expect(() => transformer.transform(document), throwsStateError);
  });

  test('returns null when the root is removed', () {
    expect(_Rewrite((node) => null).transform(const Name('a')), isNull);
  });

  test('rewrite sees the children already rewritten', () {
    final seen = <String>[];
    _Rewrite((node) {
      if (node is Field) {
        seen.add(print(node));
      }
      return node is Name ? Name(node.value.toUpperCase()) : node;
    }).transform(Parsed('{ a { b } }').document);
    expect(seen, ['B', 'A{B}']);
  });

  test('adds __typename to every selection set, as code generation does', () {
    final document = Parsed('{ a { b } ... on T { c } }').document;
    expect(
      print(const _AddTypename().transform(document)),
      '{a{b __typename}...on T{c __typename}__typename}',
    );
  });

  test('rewrites a tree 100 000 levels deep without overflowing', () {
    Value value = const IntValue('1');
    for (var i = 0; i < 100000; i++) {
      value = ListValue([value]);
    }
    final rewritten = _Rewrite(
      (node) => node is IntValue ? const IntValue('2') : node,
    ).transform(value);
    var inner = rewritten;
    while (inner is ListValue) {
      inner = inner.values.single;
    }
    expect(
      inner,
      isA<IntValue>().having((literal) => literal.value, 'value', '2'),
    );
  });
}

/// A transformer that rewrites with [replace].
final class _Rewrite extends AstTransformer {
  _Rewrite(this.replace);

  final Node? Function(Node node) replace;

  @override
  Node? rewrite(Node node) => replace(node);
}

/// Adds a `__typename` field to each selection set that lacks one.
final class _AddTypename extends AstTransformer {
  const _AddTypename();

  @override
  Node? rewrite(Node node) {
    if (node case SelectionSet(:final selections)
        when !selections.any(_isTypename)) {
      return SelectionSet([
        ...selections,
        Field(null, const Name('__typename')),
      ]);
    }
    return node;
  }

  static bool _isTypename(Selection selection) =>
      selection is Field &&
      selection.alias == null &&
      selection.name.value == '__typename';
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/visitor/ast_transformer_test.dart)
```

Expected: FAIL. `Error: Type 'AstTransformer' not found.` and `Error: The method 'transform' isn't defined for the type '_Rewrite'.`

- [ ] **Step 3: Write the implementation**

Bottom-up and iterative: a frame collects the rewritten children of its node; when it is done, the node is rebuilt with `withChildren` (the same instance when nothing changed) and passed to `rewrite`. A `null` child is left out of the list, so `withChildren` drops it from a list, clears an optional child, and throws `StateError` for a required one.

Create `packages/typed_graphql/lib/src/language/visitor/ast_transformer.dart`:

```dart
import '../ast/node.dart';

/// Rebuilds a syntax tree bottom-up (R1.9): [rewrite] sees each node after
/// its children were rewritten and returns what takes its place.
///
/// Returning the node keeps it, another node replaces it, and null removes
/// it from its parent's children. The parent is rebuilt with
/// [Node.withChildren], so the parent decides what it accepts: removing a
/// child it requires, such as the value of an argument, is a [StateError].
/// A branch where nothing changed keeps its instance, so `identical`
/// tells whether a transform changed anything.
///
/// Like `AstWalker`, it keeps its own stack instead of recursing.
abstract class AstTransformer {
  /// Creates a transformer.
  const AstTransformer();

  /// What takes the place of [node], whose children are already
  /// rewritten: [node] itself to keep it, another node, or null to remove
  /// it. Keeps every node by default.
  Node? rewrite(Node node) => node;

  /// [root] rewritten bottom-up; null when [rewrite] removed [root] itself.
  Node? transform(Node root) {
    final frames = [_Frame(root)];
    Node? rewritten;
    while (frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.hasNext) {
        frames.add(_Frame(frame.takeNext()));
        continue;
      }
      frames.removeLast();
      rewritten = rewrite(frame.rebuild());
      if (rewritten != null && frames.isNotEmpty) {
        frames.last.add(rewritten);
      }
    }
    return rewritten;
  }
}

/// A node being rebuilt: the children still to rewrite and the rewritten
/// ones so far.
final class _Frame {
  _Frame(this.node) : _children = node.children;

  final Node node;
  final List<Node> _children;
  final List<Node> _rewritten = [];
  int _next = 0;

  bool get hasNext => _next < _children.length;

  Node takeNext() => _children[_next++];

  void add(Node child) => _rewritten.add(child);

  /// [node] with the rewritten children; [node] itself when each one is
  /// identical to the child it replaces.
  Node rebuild() => node.withChildren(_rewritten);
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,6 +42,7 @@ export 'src/language/parser/parse_result.dart';
 export 'src/language/parser/parser.dart';
 export 'src/language/parser/parser_options.dart';
 export 'src/language/printer/printer.dart';
+export 'src/language/visitor/ast_transformer.dart';
 export 'src/language/visitor/ast_visitor.dart';
 export 'src/language/visitor/ast_walker.dart';
 export 'src/language/visitor/parallel_visitor.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/visitor/ast_transformer_test.dart)
```

Expected: `+10: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -51,3 +51,5 @@
   syntax tree with `enter` and `leave`, which can skip a subtree or stop.
 - `ParallelVisitor`: several visitors in one walk, each called as if it
   walked alone.
+- `AstTransformer`: rebuilds a syntax tree bottom-up; `rewrite` keeps,
+  replaces or removes a node, and unchanged branches keep their instance.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -133,6 +133,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `leave`; a skipped node is not left, a stop leaves nothing.
   `ParallelVisitor` keeps a skip or stop state per visitor, as graphql-js's
   `visitInParallel`; it is stateful, so use one per walk.
+  `AstTransformer.transform` rewrites bottom-up, also without recursion:
+  `rewrite(node)` sees rewritten children and returns the node, a
+  replacement or null (removed); the parent is rebuilt with
+  `withChildren`, so removing a required child is a `StateError`.
 
 **Protocol** (`protocol/`).
 - `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/visitor/ast_transformer.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/visitor/ast_transformer_test.dart
git commit -q -m "feat(typed_graphql): rewrite syntax trees with AstTransformer"
```

### Task 4: Port the graphql-js visitor suite

**How a graphql-js test is ported.** This applies to Tasks 4, 8, 9, 10 and 12, and is M2a's procedure (its Task 16) unchanged.

1. **Source.** `reference/graphql-js/src/language/__tests__/<file>`: graphql-js 17.0.2, commit `ee5ce41`, fetched by `tool/fetch_reference.sh`. Every `it` of each file gets a row, in file order.
2. **Names.** A Dart file starts with `// Ported from graphql-js src/language/__tests__/<file>; see` and `// mapping/language.csv.` Each `describe` becomes a `group` and each `it` a `test` with the same name. The table check searches the named file for `group('<segment>'` and `test('<name>'`.
3. **Status.** `ported`: the expectation is transcribed unchanged. `adapted`: a deliberate design difference changes it; the Dart test has a `// Adapted: <why>` comment and the row gives the reason. `skipped`: no Dart test, `dart_file` is empty, and the row gives the reason.
4. **Rows.** Columns `graphql_js_file,group,test,status,dart_file,reason`; `group` is the `describe` path joined by ` > `. A field that holds a comma or a quote is quoted, and a quote inside it is doubled (RFC 4180). The rows in the tasks are final.
5. **A failing ported expectation is a porting mistake first.** Every file was ported against this library while the plan was verified, and every expectation passed unchanged. Never weaken one; if the library really differs, stop and report it.
6. **Code rules.** Test code follows them too: no top-level function but `main`, at most 500 lines per file, full names (not dot shorthands) in `expect` arguments.

The coverage check (`rows cover every test of <file>`) runs only where `reference/` is fetched, which CI does not do: run it locally.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql_conformance/test/language/visitor/visitor_kitchen_sink_test.dart`, `packages/typed_graphql_conformance/test/language/visitor/visitor_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/csv_table.dart`, `packages/typed_graphql_conformance/test/support/visit_recorder.dart`, `packages/typed_graphql_conformance/test/support_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3: `AstWalker`, `AstVisitor`, `VisitAction`, `ParallelVisitor`, `AstTransformer`; M2a's port helpers `ParserPort`, `AstJson`, `KitchenSink`, `CsvTable`.
- Produces:
  - `CsvTable.parse` throws `FormatException` for a record with more fields than the header;
  - test helper `class VisitRecorder extends AstVisitor` (not final, so tests extend it) with `VisitRecorder(List<List<Object?>> visited, {String? label, VisitAction Function(Node node)? decide})` and `List<Object?> entry(String event, Node node)`;
  - 25 rows for `visitor-test.ts`.

- [ ] **Step 1: Write the failing test for the table reader**

An unquoted comma in a reason makes a seventh field, which `CsvTable` used to drop without a word, cutting the reason short; one row of this task had that mistake while the plan was written. The reader now rejects such a record.

In `packages/typed_graphql_conformance/test/support_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -19,6 +19,10 @@ void main() {
         {'a': 'x', 'b': ''},
       ]);
     });
+
+    test('rejects a record with more fields than the header', () {
+      expect(() => CsvTable.parse('a,b\nx,y,z'), throwsFormatException);
+    });
   });
 
   group('GraphqlJsSuite', () {
```

- [ ] **Step 2: Run the test and see it fail**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/support_test.dart)
```

Expected: FAIL in `rejects a record with more fields than the header`: `Expected: throws <Instance of 'FormatException'>`, `Which: returned <Instance of 'CsvTable'>`; the reader dropped the third field.

- [ ] **Step 3: Make the table reader strict**

In `packages/typed_graphql_conformance/test/support/csv_table.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,13 +1,22 @@
 /// A CSV text with a header row, read as RFC 4180: a quoted field may
 /// hold commas, line breaks and doubled quotes; `\r\n` ends a record too.
 final class CsvTable {
-  /// Reads [text]; the first record is the header.
+  /// Reads [text]; the first record is the header, and no record has more
+  /// fields than it (an unquoted comma would add one).
   factory CsvTable.parse(String text) {
     final records = _records(text);
     if (records.isEmpty) {
       throw const FormatException('A CSV table needs a header row.');
     }
     final [header, ...body] = records;
+    for (final (index, record) in body.indexed) {
+      if (record.length > header.length) {
+        throw FormatException(
+          'Record ${index + 2} has ${record.length} fields; '
+          'the header has ${header.length}.',
+        );
+      }
+    }
     return CsvTable._(header, [
       for (final record in body)
         {
```

- [ ] **Step 4: Run the test and see it pass**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/support_test.dart)
```

Expected: `+4: All tests passed!`

- [ ] **Step 5: Write the port helper**

`VisitRecorder` is graphql-js's recording visitor: `[label?, event, kind, value]` per call, with the kind and the value from `AstJson`.

Create `packages/typed_graphql_conformance/test/support/visit_recorder.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'ast_json.dart';

/// The visitor of graphql-js's visitor suite: it records each call in
/// [visited] as `[label?, 'enter' or 'leave', kind, getValue(node)]`, with
/// graphql-js's `Kind` and `null` for `undefined`, and [enter] returns
/// what [decide] says.
class VisitRecorder extends AstVisitor {
  /// Creates a recorder that writes to [visited].
  VisitRecorder(this.visited, {this.label, this.decide});

  /// The calls, in order.
  final List<List<Object?>> visited;

  /// Written first in each entry, such as `'no-a'`; left out when null.
  final String? label;

  /// What [enter] returns for a node; [VisitAction.next] when null.
  final VisitAction Function(Node node)? decide;

  @override
  VisitAction enter(Node node) {
    visited.add(entry('enter', node));
    return decide?.call(node) ?? VisitAction.next;
  }

  @override
  void leave(Node node) => visited.add(entry('leave', node));

  /// One entry for [event] at [node].
  List<Object?> entry(String event, Node node) =>
      switch (const AstJson().of(node)) {
        final Map<String, Object?> json => [
          ?label,
          event,
          json['kind'],
          json['value'],
        ],
        _ => throw ArgumentError.value(node, 'node', 'has no AST JSON'),
      };
}
```

- [ ] **Step 6: Write the ported tests**

The visitor-editing tests of graphql-js become `AstTransformer` tests (`adapted`). The `visitInParallel` group lives in `visitor_test.dart`, and the kitchen-sink walk, with its long expected list, in its own file.

Create `packages/typed_graphql_conformance/test/language/visitor/visitor_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/visitor-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/parser_port.dart';
import '../../support/visit_recorder.dart';

void main() {
  const port = ParserPort();
  const walker = AstWalker();

  bool isField(Node node, String name) =>
      node is Field && node.name.value == name;

  bool isName(Node node, String value) => node is Name && node.value == value;

  group('Visitor', () {
    test('handles empty visitor', () {
      final ast = port.document('{ a }');
      expect(() => walker.walk(ast, const _EmptyVisitor()), returnsNormally);
    });

    // Adapted: AstTransformer edits a tree, bottom-up; removing a node
    // there gives the tree graphql-js gets from removing it on enter.
    test('allows for editing on enter', () {
      final ast = port.document('{ a, b, c { a, b, c } }');
      final editedAst = _Remove(
        (node) => isField(node, 'b'),
      ).transform(ast);

      expect(
        ast.isEquivalentTo(port.document('{ a, b, c { a, b, c } }')),
        isTrue,
      );
      expect(
        editedAst?.isEquivalentTo(port.document('{ a,    c { a,    c } }')),
        isTrue,
      );
    });

    // Adapted: AstTransformer edits a tree, bottom-up, which is graphql-js's
    // editing on leave.
    test('allows for editing on leave', () {
      final ast = port.document('{ a, b, c { a, b, c } }');
      final editedAst = _Remove(
        (node) => isField(node, 'b'),
      ).transform(ast);

      expect(
        ast.isEquivalentTo(port.document('{ a, b, c { a, b, c } }')),
        isTrue,
      );
      expect(
        editedAst?.isEquivalentTo(port.document('{ a,    c { a,    c } }')),
        isTrue,
      );
    });

    test('allows skipping a sub-tree', () {
      final visited = <List<Object?>>[];

      final ast = port.document('{ a, b { x }, c }');
      walker.walk(
        ast,
        VisitRecorder(
          visited,
          decide: (node) =>
              isField(node, 'b') ? VisitAction.skip : VisitAction.next,
        ),
      );

      expect(visited, [
        ['enter', 'Document', null],
        ['enter', 'OperationDefinition', null],
        ['enter', 'SelectionSet', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'a'],
        ['leave', 'Name', 'a'],
        ['leave', 'Field', null],
        ['enter', 'Field', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'c'],
        ['leave', 'Name', 'c'],
        ['leave', 'Field', null],
        ['leave', 'SelectionSet', null],
        ['leave', 'OperationDefinition', null],
        ['leave', 'Document', null],
      ]);
    });

    test('allows early exit while visiting', () {
      final visited = <List<Object?>>[];

      final ast = port.document('{ a, b { x }, c }');
      walker.walk(
        ast,
        VisitRecorder(
          visited,
          decide: (node) =>
              isName(node, 'x') ? VisitAction.stop : VisitAction.next,
        ),
      );

      expect(visited, [
        ['enter', 'Document', null],
        ['enter', 'OperationDefinition', null],
        ['enter', 'SelectionSet', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'a'],
        ['leave', 'Name', 'a'],
        ['leave', 'Field', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'b'],
        ['leave', 'Name', 'b'],
        ['enter', 'SelectionSet', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'x'],
      ]);
    });

    // Adapted: a visitor tells kinds apart with a switch in enter and
    // leave instead of graphql-js's per-kind functions.
    test('allows a named functions visitor API', () {
      final visited = <List<Object?>>[];

      final ast = port.document('{ a, b { x }, c }');
      walker.walk(ast, _NamesAndSelectionSets(visited));

      expect(visited, [
        ['enter', 'SelectionSet', null],
        ['enter', 'Name', 'a'],
        ['enter', 'Name', 'b'],
        ['enter', 'SelectionSet', null],
        ['enter', 'Name', 'x'],
        ['leave', 'SelectionSet', null],
        ['enter', 'Name', 'c'],
        ['leave', 'SelectionSet', null],
      ]);
    });

    group('visitInParallel', () {
      // Note: nearly identical to the above test of the same test but
      // using visitInParallel.
      test('allows skipping a sub-tree', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a, b { x }, c }');
        walker.walk(
          ast,
          ParallelVisitor([
            VisitRecorder(
              visited,
              decide: (node) =>
                  isField(node, 'b') ? VisitAction.skip : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['enter', 'Document', null],
          ['enter', 'OperationDefinition', null],
          ['enter', 'SelectionSet', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'a'],
          ['leave', 'Name', 'a'],
          ['leave', 'Field', null],
          ['enter', 'Field', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'c'],
          ['leave', 'Name', 'c'],
          ['leave', 'Field', null],
          ['leave', 'SelectionSet', null],
          ['leave', 'OperationDefinition', null],
          ['leave', 'Document', null],
        ]);
      });

      test('allows skipping different sub-trees', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a { x }, b { y} }');
        walker.walk(
          ast,
          ParallelVisitor([
            VisitRecorder(
              visited,
              label: 'no-a',
              decide: (node) =>
                  isField(node, 'a') ? VisitAction.skip : VisitAction.next,
            ),
            VisitRecorder(
              visited,
              label: 'no-b',
              decide: (node) =>
                  isField(node, 'b') ? VisitAction.skip : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['no-a', 'enter', 'Document', null],
          ['no-b', 'enter', 'Document', null],
          ['no-a', 'enter', 'OperationDefinition', null],
          ['no-b', 'enter', 'OperationDefinition', null],
          ['no-a', 'enter', 'SelectionSet', null],
          ['no-b', 'enter', 'SelectionSet', null],
          ['no-a', 'enter', 'Field', null],
          ['no-b', 'enter', 'Field', null],
          ['no-b', 'enter', 'Name', 'a'],
          ['no-b', 'leave', 'Name', 'a'],
          ['no-b', 'enter', 'SelectionSet', null],
          ['no-b', 'enter', 'Field', null],
          ['no-b', 'enter', 'Name', 'x'],
          ['no-b', 'leave', 'Name', 'x'],
          ['no-b', 'leave', 'Field', null],
          ['no-b', 'leave', 'SelectionSet', null],
          ['no-b', 'leave', 'Field', null],
          ['no-a', 'enter', 'Field', null],
          ['no-b', 'enter', 'Field', null],
          ['no-a', 'enter', 'Name', 'b'],
          ['no-a', 'leave', 'Name', 'b'],
          ['no-a', 'enter', 'SelectionSet', null],
          ['no-a', 'enter', 'Field', null],
          ['no-a', 'enter', 'Name', 'y'],
          ['no-a', 'leave', 'Name', 'y'],
          ['no-a', 'leave', 'Field', null],
          ['no-a', 'leave', 'SelectionSet', null],
          ['no-a', 'leave', 'Field', null],
          ['no-a', 'leave', 'SelectionSet', null],
          ['no-b', 'leave', 'SelectionSet', null],
          ['no-a', 'leave', 'OperationDefinition', null],
          ['no-b', 'leave', 'OperationDefinition', null],
          ['no-a', 'leave', 'Document', null],
          ['no-b', 'leave', 'Document', null],
        ]);
      });

      // Note: nearly identical to the above test of the same test but
      // using visitInParallel.
      test('allows early exit while visiting', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a, b { x }, c }');
        walker.walk(
          ast,
          ParallelVisitor([
            VisitRecorder(
              visited,
              decide: (node) =>
                  isName(node, 'x') ? VisitAction.stop : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['enter', 'Document', null],
          ['enter', 'OperationDefinition', null],
          ['enter', 'SelectionSet', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'a'],
          ['leave', 'Name', 'a'],
          ['leave', 'Field', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'b'],
          ['leave', 'Name', 'b'],
          ['enter', 'SelectionSet', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'x'],
        ]);
      });

      test('allows early exit from different points', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a { y }, b { x } }');
        walker.walk(
          ast,
          ParallelVisitor([
            _NeverLeaves(
              visited,
              label: 'break-a',
              decide: (node) =>
                  isName(node, 'a') ? VisitAction.stop : VisitAction.next,
            ),
            VisitRecorder(
              visited,
              label: 'break-b',
              decide: (node) =>
                  isName(node, 'b') ? VisitAction.stop : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['break-a', 'enter', 'Document', null],
          ['break-b', 'enter', 'Document', null],
          ['break-a', 'enter', 'OperationDefinition', null],
          ['break-b', 'enter', 'OperationDefinition', null],
          ['break-a', 'enter', 'SelectionSet', null],
          ['break-b', 'enter', 'SelectionSet', null],
          ['break-a', 'enter', 'Field', null],
          ['break-b', 'enter', 'Field', null],
          ['break-a', 'enter', 'Name', 'a'],
          ['break-b', 'enter', 'Name', 'a'],
          ['break-b', 'leave', 'Name', 'a'],
          ['break-b', 'enter', 'SelectionSet', null],
          ['break-b', 'enter', 'Field', null],
          ['break-b', 'enter', 'Name', 'y'],
          ['break-b', 'leave', 'Name', 'y'],
          ['break-b', 'leave', 'Field', null],
          ['break-b', 'leave', 'SelectionSet', null],
          ['break-b', 'leave', 'Field', null],
          ['break-b', 'enter', 'Field', null],
          ['break-b', 'enter', 'Name', 'b'],
        ]);
      });
    });
  });
}

/// A visitor that keeps the default methods: graphql-js's `{}`.
final class _EmptyVisitor extends AstVisitor {
  const _EmptyVisitor();
}

/// Removes every node that [matches].
final class _Remove extends AstTransformer {
  _Remove(this.matches);

  final bool Function(Node node) matches;

  @override
  Node? rewrite(Node node) => matches(node) ? null : node;
}

/// graphql-js's `{ Name(node) {...}, SelectionSet: { enter, leave } }`.
final class _NamesAndSelectionSets extends VisitRecorder {
  _NamesAndSelectionSets(super.visited);

  @override
  VisitAction enter(Node node) {
    if (node is Name || node is SelectionSet) {
      visited.add(entry('enter', node));
    }
    return VisitAction.next;
  }

  @override
  void leave(Node node) {
    if (node is SelectionSet) {
      visited.add(entry('leave', node));
    }
  }
}

/// A recorder whose `leave` must not be called.
final class _NeverLeaves extends VisitRecorder {
  _NeverLeaves(super.visited, {super.label, super.decide});

  @override
  void leave(Node node) => fail('Should not be called');
}
```

Create `packages/typed_graphql_conformance/test/language/visitor/visitor_kitchen_sink_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/visitor-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';
import '../../support/visit_recorder.dart';

void main() {
  group('Visitor', () {
    // Adapted: enter and leave receive the node only, so each entry keeps
    // the event and the kind; graphql-js also records the key and the
    // parent's kind.
    test('properly visits the kitchen sink query', () {
      final ast = const ParserPort().document(KitchenSink.query);
      final visited = <List<Object?>>[];

      const AstWalker().walk(ast, VisitRecorder(visited));

      expect(
        [for (final entry in visited) entry.take(2).toList()],
        [
          ['enter', 'Document'],
          ['enter', 'OperationDefinition'],
          ['enter', 'StringValue'],
          ['leave', 'StringValue'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'VariableDefinition'],
          ['enter', 'StringValue'],
          ['leave', 'StringValue'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['enter', 'NamedType'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'NamedType'],
          ['leave', 'VariableDefinition'],
          ['enter', 'VariableDefinition'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['enter', 'NamedType'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'NamedType'],
          ['enter', 'EnumValue'],
          ['leave', 'EnumValue'],
          ['leave', 'VariableDefinition'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'ListValue'],
          ['enter', 'IntValue'],
          ['leave', 'IntValue'],
          ['enter', 'IntValue'],
          ['leave', 'IntValue'],
          ['leave', 'ListValue'],
          ['leave', 'Argument'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['enter', 'InlineFragment'],
          ['enter', 'NamedType'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'NamedType'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'IntValue'],
          ['leave', 'IntValue'],
          ['leave', 'Argument'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['leave', 'Argument'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['leave', 'Argument'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['enter', 'FragmentSpread'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['leave', 'FragmentSpread'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'InlineFragment'],
          ['enter', 'InlineFragment'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['leave', 'Argument'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'InlineFragment'],
          ['enter', 'InlineFragment'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'InlineFragment'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'OperationDefinition'],
          ['enter', 'OperationDefinition'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'IntValue'],
          ['leave', 'IntValue'],
          ['leave', 'Argument'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'OperationDefinition'],
          ['enter', 'OperationDefinition'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'VariableDefinition'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['enter', 'NamedType'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'NamedType'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['leave', 'VariableDefinition'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['leave', 'Argument'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'OperationDefinition'],
          ['enter', 'FragmentDefinition'],
          ['enter', 'StringValue'],
          ['leave', 'StringValue'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'NamedType'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'NamedType'],
          ['enter', 'Directive'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Directive'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['leave', 'Argument'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Variable'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Variable'],
          ['leave', 'Argument'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'ObjectValue'],
          ['enter', 'ObjectField'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'StringValue'],
          ['leave', 'StringValue'],
          ['leave', 'ObjectField'],
          ['enter', 'ObjectField'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'StringValue'],
          ['leave', 'StringValue'],
          ['leave', 'ObjectField'],
          ['leave', 'ObjectValue'],
          ['leave', 'Argument'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'FragmentDefinition'],
          ['enter', 'OperationDefinition'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'BooleanValue'],
          ['leave', 'BooleanValue'],
          ['leave', 'Argument'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'BooleanValue'],
          ['leave', 'BooleanValue'],
          ['leave', 'Argument'],
          ['enter', 'Argument'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['enter', 'NullValue'],
          ['leave', 'NullValue'],
          ['leave', 'Argument'],
          ['leave', 'Field'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'OperationDefinition'],
          ['enter', 'OperationDefinition'],
          ['enter', 'SelectionSet'],
          ['enter', 'Field'],
          ['enter', 'Name'],
          ['leave', 'Name'],
          ['leave', 'Field'],
          ['leave', 'SelectionSet'],
          ['leave', 'OperationDefinition'],
          ['leave', 'Document'],
        ],
      );
    });
  });
}
```

- [ ] **Step 7: Run the ported tests**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/visitor/visitor_test.dart test/language/visitor/visitor_kitchen_sink_test.dart)
```

Expected: `visitor_test.dart` `+10`, `visitor_kitchen_sink_test.dart` `+1`, each `All tests passed!`

- [ ] **Step 8: Mark the file as ported and see the coverage check fail**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -18,6 +18,7 @@ const Set<String> portedFiles = {
   'printer-test.ts',
   'schema-printer-test.ts',
   'printString-test.ts',
+  'visitor-test.ts',
 };
 
 void main() {
```

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of visitor-test.ts`: `Actual: Set:[]`, followed by the missing `(group, test)` pairs. This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 9: Write the rows**

Twenty-five rows: 7 ported, 4 adapted, 14 skipped. Most of the skipped tests need a `leave` that returns an action or an edit, or the `key`, `parent`, `path` and `ancestors` arguments; spec §6 gives `leave` neither (see "Spec deviations and findings", 1).

In `packages/typed_graphql_conformance/mapping/language.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -181,3 +181,28 @@ printString-test.ts,printString,does not escape space,ported,test/language/print
 printString-test.ts,printString,does not escape non-ascii character,ported,test/language/printer/print_string_test.dart,
 printString-test.ts,printString,does not escape supplementary character,ported,test/language/printer/print_string_test.dart,
 printString-test.ts,printString,escapes all control chars,ported,test/language/printer/print_string_test.dart,
+visitor-test.ts,Visitor,handles empty visitor,ported,test/language/visitor/visitor_test.dart,
+visitor-test.ts,Visitor,validates path argument,skipped,,"AstVisitor.enter and leave take the node only: no key, parent or path."
+visitor-test.ts,Visitor,validates ancestors argument,skipped,,AstVisitor.enter and leave take the node only: no ancestors.
+visitor-test.ts,Visitor,allows editing a node both on enter and on leave,skipped,,A visitor only reads; AstTransformer edits bottom-up and has no enter-side edit.
+visitor-test.ts,Visitor,allows editing the root node on enter and on leave,skipped,,A visitor only reads; AstTransformer edits bottom-up and has no enter-side edit.
+visitor-test.ts,Visitor,allows for editing on enter,adapted,test/language/visitor/visitor_test.dart,AstTransformer removes the node bottom-up; the edited tree is the same.
+visitor-test.ts,Visitor,allows for editing on leave,adapted,test/language/visitor/visitor_test.dart,AstTransformer removes the node bottom-up; the edited tree is the same.
+visitor-test.ts,Visitor,ignores false returned on leave,skipped,,AstVisitor.leave returns nothing (spec §6).
+visitor-test.ts,Visitor,visits edited node,skipped,,A visitor only reads; AstTransformer has no enter-side edit to visit.
+visitor-test.ts,Visitor,allows skipping a sub-tree,ported,test/language/visitor/visitor_test.dart,
+visitor-test.ts,Visitor,allows early exit while visiting,ported,test/language/visitor/visitor_test.dart,
+visitor-test.ts,Visitor,allows early exit while leaving,skipped,,AstVisitor.leave returns nothing (spec §6): a walk stops only from enter.
+visitor-test.ts,Visitor,allows a named functions visitor API,adapted,test/language/visitor/visitor_test.dart,A switch on the node in enter and leave replaces graphql-js's per-kind functions.
+visitor-test.ts,Visitor,visits only the specified `Kind` in visitorKeyMap,skipped,,Node.children is fixed: there is no visitor key map.
+visitor-test.ts,Visitor,visits arguments defined on fragments,skipped,,Fragment arguments (R1.14) are not implemented.
+visitor-test.ts,Visitor,visits arguments on fragment spreads,skipped,,Fragment arguments (R1.14) are not implemented.
+visitor-test.ts,Visitor,properly visits the kitchen sink query,adapted,test/language/visitor/visitor_kitchen_sink_test.dart,"Checks event and kind in order; enter and leave take no key or parent, so those columns are dropped."
+visitor-test.ts,Visitor > visitInParallel,allows skipping a sub-tree,ported,test/language/visitor/visitor_test.dart,
+visitor-test.ts,Visitor > visitInParallel,allows skipping different sub-trees,ported,test/language/visitor/visitor_test.dart,
+visitor-test.ts,Visitor > visitInParallel,allows early exit while visiting,ported,test/language/visitor/visitor_test.dart,
+visitor-test.ts,Visitor > visitInParallel,allows early exit from different points,ported,test/language/visitor/visitor_test.dart,
+visitor-test.ts,Visitor > visitInParallel,allows early exit while leaving,skipped,,AstVisitor.leave returns nothing (spec §6): a walk stops only from enter.
+visitor-test.ts,Visitor > visitInParallel,allows early exit from leaving different points,skipped,,AstVisitor.leave returns nothing (spec §6): a walk stops only from enter.
+visitor-test.ts,Visitor > visitInParallel,allows for editing on enter,skipped,,ParallelVisitor only reads; AstTransformer does the editing.
+visitor-test.ts,Visitor > visitInParallel,allows for editing on leave,skipped,,ParallelVisitor only reads; AstTransformer does the editing.
```

- [ ] **Step 10: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+182: All tests passed!`

- [ ] **Step 11: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,4 +8,4 @@
   checks it.
 - Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`,
   `parser-test.ts`, `schema-parser-test.ts`, `printer-test.ts`,
-  `schema-printer-test.ts`, `printString-test.ts`.
+  `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`.
```

- [ ] **Step 12: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 13: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/language.csv packages/typed_graphql_conformance/test/language/visitor/visitor_kitchen_sink_test.dart packages/typed_graphql_conformance/test/language/visitor/visitor_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/csv_table.dart packages/typed_graphql_conformance/test/support/visit_recorder.dart packages/typed_graphql_conformance/test/support_test.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js visitor suite"
```

### Task 5: Schema coordinate nodes

R1.11 and spec §7: the sealed `SchemaCoordinate` family.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/ast/schema_coordinate.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/ast/schema_coordinate_test.dart`

**Interfaces:**
- Consumes: M2a: `Node`, `Name`, the internal `ChildReader` (`one()`), the test helper `RebuildCheck`.
- Produces:
  - `sealed class const SchemaCoordinate(final Name name, {start, end}) extends Node`;
  - `TypeCoordinate(Name name)`, `MemberCoordinate(Name name, Name memberName)`, `ArgumentCoordinate(Name name, Name fieldName, Name argumentName)`, `DirectiveCoordinate(Name name)`, `DirectiveArgumentCoordinate(Name name, Name argumentName)`, each `const` with `{start, end}`, `children` in text order.

- [ ] **Step 1: Write the failing tests**

`RebuildCheck` is M2a's helper in `test/language/ast/rebuild_check.dart`.

Create `packages/typed_graphql/test/language/ast/schema_coordinate_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const type = Name('Query', start: 0, end: 5);
  const field = Name('hero', start: 6, end: 10);
  const argument = Name('episode', start: 11, end: 18);

  test('children are the names in text order', () {
    expect(const TypeCoordinate(type).children, [same(type)]);
    expect(const MemberCoordinate(type, field).children, [
      same(type),
      same(field),
    ]);
    expect(const ArgumentCoordinate(type, field, argument).children, [
      same(type),
      same(field),
      same(argument),
    ]);
    expect(const DirectiveCoordinate(type).children, [same(type)]);
    expect(const DirectiveArgumentCoordinate(type, argument).children, [
      same(type),
      same(argument),
    ]);
  });

  test('withChildren rebuilds every kind of coordinate', () {
    const coordinates = <SchemaCoordinate>[
      TypeCoordinate(type, start: 0, end: 5),
      MemberCoordinate(type, field, start: 0, end: 10),
      ArgumentCoordinate(type, field, argument, start: 0, end: 20),
      DirectiveCoordinate(type, start: 0, end: 6),
      DirectiveArgumentCoordinate(type, argument, start: 0, end: 16),
    ];
    coordinates.forEach(check.expectRebuilds);
  });

  test('a type and a directive with the same name are not equivalent', () {
    expect(
      const TypeCoordinate(type)
          .isEquivalentTo(const DirectiveCoordinate(type)),
      isFalse,
    );
  });

  test('a member coordinate needs both names', () {
    expect(
      () => const MemberCoordinate(type, field).withChildren(const [type]),
      throwsStateError,
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/schema_coordinate_test.dart)
```

Expected: FAIL. `Error: Couldn't find constructor 'TypeCoordinate'.` and `Error: 'SchemaCoordinate' isn't a type.`

- [ ] **Step 3: Write the implementation**

One sealed family in one library, with graphql-js's field names. The library has 126 lines.

Create `packages/typed_graphql/lib/src/language/ast/schema_coordinate.dart`:

```dart
import 'child_reader.dart';
import 'name.dart';
import 'node.dart';

/// A schema coordinate: the text that names one element of a schema, such
/// as `Query.hero(episode:)` (September2025 §2 "Schema Coordinates").
///
/// The field names follow graphql-js's nodes. A coordinate is parsed with
/// `Parser.parseSchemaCoordinate`; resolving it against a schema is not the
/// parser's work.
sealed class const SchemaCoordinate(
  /// The type or, after `@`, the directive the coordinate starts from.
  final Name name, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a coordinate spanning `start` to `end`.
  this;
}

/// A type, `Name`.
final class const TypeCoordinate(
  super.name, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a type coordinate.
  this;

  @override
  List<Node> get children => [name];

  @override
  TypeCoordinate rebuildFrom(ChildReader read) =>
      TypeCoordinate(read.one(), start: start, end: end);
}

/// A field, input field or enum value of a type, `Name.Name`.
final class const MemberCoordinate(
  super.name,

  /// The name of the field, input field or enum value.
  final Name memberName, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a member coordinate.
  this;

  @override
  List<Node> get children => [name, memberName];

  @override
  MemberCoordinate rebuildFrom(ChildReader read) =>
      MemberCoordinate(read.one(), read.one(), start: start, end: end);
}

/// An argument of a field, `Name.Name(Name:)`.
final class const ArgumentCoordinate(
  super.name,

  /// The name of the field.
  final Name fieldName,

  /// The name of the argument.
  final Name argumentName, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates an argument coordinate.
  this;

  @override
  List<Node> get children => [name, fieldName, argumentName];

  @override
  ArgumentCoordinate rebuildFrom(ChildReader read) => ArgumentCoordinate(
    read.one(),
    read.one(),
    read.one(),
    start: start,
    end: end,
  );
}

/// A directive, `@Name`.
final class const DirectiveCoordinate(
  super.name, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a directive coordinate.
  this;

  @override
  List<Node> get children => [name];

  @override
  DirectiveCoordinate rebuildFrom(ChildReader read) =>
      DirectiveCoordinate(read.one(), start: start, end: end);
}

/// An argument of a directive, `@Name(Name:)`.
final class const DirectiveArgumentCoordinate(
  super.name,

  /// The name of the argument.
  final Name argumentName, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a directive argument coordinate.
  this;

  @override
  List<Node> get children => [name, argumentName];

  @override
  DirectiveArgumentCoordinate rebuildFrom(ChildReader read) =>
      DirectiveArgumentCoordinate(
        read.one(),
        read.one(),
        start: start,
        end: end,
      );
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -25,6 +25,7 @@ export 'src/language/ast/node.dart';
 export 'src/language/ast/object_field.dart';
 export 'src/language/ast/operation_type.dart';
 export 'src/language/ast/operation_type_definition.dart';
+export 'src/language/ast/schema_coordinate.dart';
 export 'src/language/ast/selection.dart';
 export 'src/language/ast/selection_set.dart';
 export 'src/language/ast/type_ref.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/ast/schema_coordinate_test.dart)
```

Expected: `+4: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -53,3 +53,6 @@
   walked alone.
 - `AstTransformer`: rebuilds a syntax tree bottom-up; `rewrite` keeps,
   replaces or removes a node, and unchanged branches keep their instance.
+- Schema coordinate nodes: the `SchemaCoordinate` family
+  (`TypeCoordinate`, `MemberCoordinate`, `ArgumentCoordinate`,
+  `DirectiveCoordinate`, `DirectiveArgumentCoordinate`).
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/ast/schema_coordinate.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/ast/schema_coordinate_test.dart
git commit -q -m "feat(typed_graphql): add schema coordinate nodes"
```

### Task 6: Lex schema coordinates

Spec §7: a coordinate has its own tiny lexer, with no ignored tokens.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/lexer/schema_coordinate_lexer.dart`, `packages/typed_graphql/lib/src/language/lexer/token_source.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/language/lexer/lexer.dart`, `packages/typed_graphql/lib/src/language/lexer/source_reader.dart`, `packages/typed_graphql/lib/src/language/lexer/token_kind.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/lexer/lexer_test.dart`, `packages/typed_graphql/test/language/lexer/schema_coordinate_lexer_test.dart`, `packages/typed_graphql/test/language/lexer/token_test.dart`

**Interfaces:**
- Consumes: M2a: `Lexer`, `SourceReader` (`unitAt`, `slice`, `describe`, `report`), `CharacterClass`, `Token`, `TokenKind`, `DiagnosticCode`.
- Produces:
  - `TokenKind.dot`, described as `"."`, which the document lexer never produces;
  - `abstract interface class TokenSource { Source get source; bool get isLimitReached; Token advance(); }`, which `Lexer` implements;
  - `final class SchemaCoordinateLexer implements TokenSource` with `SchemaCoordinateLexer(Source source, DiagnosticSink sink)`; `isLimitReached` is always `false`;
  - internal `Token SourceReader.name(int start)`.

- [ ] **Step 1: Write the failing tests**

The document lexer must keep rejecting a lone `.`; the coordinate lexer rejects every ignored token, since a coordinate allows none (September2025 §2 "Schema Coordinates").

In `packages/typed_graphql/test/language/lexer/token_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,7 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 void main() {
   group('TokenKind', () {
-    test('punctuators are the fourteen kinds from "!" to "}"', () {
+    test('punctuators are the fifteen kinds from "!" to "}"', () {
       final punctuators = [
         for (final kind in TokenKind.values)
           if (kind.isPunctuator) kind.description,
@@ -14,6 +14,7 @@ void main() {
         '"&"',
         '"("',
         '")"',
+        '"."',
         '"..."',
         '":"',
         '"="',
```

In `packages/typed_graphql/test/language/lexer/lexer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -24,14 +24,14 @@ void main() {
   });
 
   group('punctuators and names', () {
-    test('lexes every punctuator', () {
+    test('lexes every punctuator but the coordinate dot', () {
       final kinds = [
         for (final token in Lexed(r'! $ & ( ) ... : = @ [ ] { | }').tokens)
           token.kind,
       ];
       expect(kinds, [
         for (final kind in TokenKind.values)
-          if (kind.isPunctuator) kind,
+          if (kind.isPunctuator && kind != TokenKind.dot) kind,
       ]);
     });
 
@@ -109,6 +109,12 @@ void main() {
       expect(Lexed("'a'").errors.first, contains('did you mean to use a'));
     });
 
+    test('a single dot in a document is an unexpected character', () {
+      final lexed = Lexed('a.b');
+      expect(lexed.errors, ['1:2 GQL001 Unexpected character: ".".']);
+      expect(lexed.described, ['name 0:1 a', 'error 1:2', 'name 2:3 b']);
+    });
+
     test('names a control character and a supplementary character', () {
       expect(Lexed('\u0007').errors, [
         '1:1 GQL001 Unexpected character: U+0007.',
```

Create `packages/typed_graphql/test/language/lexer/schema_coordinate_lexer_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  /// Each token of [text] before the end as `kind start:end value`, then
  /// each diagnostic as `line:column id message`.
  List<String> lex(String text) {
    final sink = DiagnosticSink();
    final lexer = SchemaCoordinateLexer(Source(text), sink);
    return [
      for (
        var token = lexer.advance();
        token.kind != TokenKind.eof;
        token = lexer.advance()
      )
        '${token.kind.name} ${token.start}:${token.end}'
            '${token.value == null ? '' : ' ${token.value}'}',
      for (final diagnostic in sink.diagnostics)
        '${diagnostic.span?.location} ${diagnostic.code.id} '
            '${diagnostic.message}',
    ];
  }

  test('lexes names and the five coordinate punctuators', () {
    expect(lex('@a.b(c:)'), [
      'at 0:1',
      'name 1:2 a',
      'dot 2:3',
      'name 3:4 b',
      'parenLeft 4:5',
      'name 5:6 c',
      'colon 6:7',
      'parenRight 7:8',
    ]);
  });

  test('a name runs over letters, digits and underscores', () {
    expect(lex('__Type_2.f'), ['name 0:8 __Type_2', 'dot 8:9', 'name 9:10 f']);
  });

  test('white space is an invalid character, and lexing goes on', () {
    expect(lex('Foo .bar'), [
      'name 0:3 Foo',
      'error 3:4',
      'dot 4:5',
      'name 5:8 bar',
      '1:4 GQL001 Invalid character: " ".',
    ]);
  });

  test('a line terminator, a comma and a comment are invalid too', () {
    expect(lex('\na,#'), [
      'error 0:1',
      'name 1:2 a',
      'error 2:3',
      'error 3:4',
      '1:1 GQL001 Invalid character: U+000A.',
      '2:2 GQL001 Invalid character: ",".',
      '2:3 GQL001 Invalid character: "#".',
    ]);
  });

  test('document punctuators, digits and spreads are invalid', () {
    expect(lex(r'{1$...').where((line) => line.contains('GQL')), [
      '1:1 GQL001 Invalid character: "{".',
      '1:2 GQL001 Invalid character: "1".',
      r'1:3 GQL001 Invalid character: "$".',
    ]);
  });

  test('a supplementary character is one error token', () {
    expect(lex('a\u{1F600}'), [
      'name 0:1 a',
      'error 1:3',
      '1:2 GQL001 Invalid character: U+1F600.',
    ]);
  });

  test('a lone surrogate is GQL002, as in a document', () {
    expect(lex('\uDEAD'), [
      'error 0:1',
      '1:1 GQL002 Invalid character: U+DEAD.',
    ]);
  });

  test('the end is returned again on every later call', () {
    final lexer = SchemaCoordinateLexer(Source('a'), DiagnosticSink());
    lexer.advance();
    expect(lexer.advance().kind, TokenKind.eof);
    expect(lexer.advance().kind, TokenKind.eof);
    expect(lexer.isLimitReached, isFalse);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/token_test.dart test/language/lexer/lexer_test.dart test/language/lexer/schema_coordinate_lexer_test.dart)
```

Expected: FAIL. `lexer_test.dart`: `Error: Member not found: 'dot'.`; `schema_coordinate_lexer_test.dart`: `Error: Method not found: 'SchemaCoordinateLexer'.`; `token_test.dart`: `punctuators are the fifteen kinds from "!" to "}"` fails on its list.

- [ ] **Step 3: Share the name scanner and add the token source**

`SourceReader.name` takes over `Lexer._name`, so both lexers scan names the same way. `TokenSource` is what the parser's cursor will read in Task 7.

In `packages/typed_graphql/lib/src/language/lexer/token_kind.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,9 @@ enum TokenKind(
   /// `)`.
   parenRight('")"'),
 
+  /// `.`, which only a schema coordinate has.
+  dot('"."'),
+
   /// `...`.
   spread('"..."'),
 
```

In `packages/typed_graphql/lib/src/language/lexer/source_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,7 @@ import '../../diagnostics/diagnostic_sink.dart';
 import '../../diagnostics/source.dart';
 import '../../diagnostics/source_span.dart';
 import 'character_class.dart';
+import 'token.dart';
 
 /// What the scanners of one lexer share: the text, its characters and the
 /// sink errors go to.
@@ -43,6 +44,16 @@ final class SourceReader {
     return isPair ? 2 : 0;
   }
 
+  /// The name that starts at [start], whose first character is a name
+  /// start.
+  Token name(int start) {
+    var end = start + 1;
+    while (_classes.isNameContinue(unitAt(end))) {
+      end++;
+    }
+    return Token(.name, start, end, value: slice(start, end));
+  }
+
   /// The character at [offset] as messages show it, as graphql-js's
   /// `printCodePointAt` does: `"a"`, `'"'`, `U+0007`, `U+1F600` or
   /// `<EOF>`.
```

Create `packages/typed_graphql/lib/src/language/lexer/token_source.dart`:

```dart
import '../../diagnostics/source.dart';
import 'token.dart';
import 'token_kind.dart';

/// A stream of tokens the parser reads: `Lexer` for documents,
/// `SchemaCoordinateLexer` for schema coordinates (graphql-js's
/// `LexerInterface`).
abstract interface class TokenSource {
  /// The document being read.
  Source get source;

  /// Whether a token limit stopped the reading before the end.
  bool get isLimitReached;

  /// The next token; [TokenKind.eof] at the end, and again on every later
  /// call. Text that is no token is one [TokenKind.error] token, reported
  /// to the sink.
  Token advance();
}
```

In `packages/typed_graphql/lib/src/language/lexer/lexer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,6 +8,7 @@ import 'source_reader.dart';
 import 'string_scanner.dart';
 import 'token.dart';
 import 'token_kind.dart';
+import 'token_source.dart';
 
 /// Turns a [Source] into tokens, one per [advance] (spec §2.1).
 ///
@@ -19,7 +20,7 @@ import 'token_kind.dart';
 /// With [maxTokens], the token after the limit is replaced by one
 /// [DiagnosticCode.tokenLimitExceeded] error, [isLimitReached] becomes
 /// true and every later call returns [TokenKind.eof] (R1.6).
-final class Lexer {
+final class Lexer implements TokenSource {
   /// Creates a lexer of [source] that reports into [sink].
   Lexer(
     Source source,
@@ -56,7 +57,7 @@ final class Lexer {
   int _tokenCount = 0;
   bool _isLimitReached = false;
 
-  /// The document being read.
+  @override
   Source get source => _reader.source;
 
   /// The tokens scanned so far, comments and the end not counted; includes
@@ -65,6 +66,7 @@ final class Lexer {
 
   /// Whether [maxTokens] was exceeded, so the document was not read to
   /// its end.
+  @override
   bool get isLimitReached => _isLimitReached;
 
   static const CharacterClass _classes = CharacterClass();
@@ -85,8 +87,7 @@ final class Lexer {
     0x7d: .braceRight,
   };
 
-  /// The next token; [TokenKind.eof] at the end, and again on every later
-  /// call.
+  @override
   Token advance() {
     if (_isLimitReached) {
       return Token(.eof, _position, _position);
@@ -151,19 +152,11 @@ final class Lexer {
       0x22 when _reader.slice(at, at + 3) == '"""' => _blockStrings.scan(at),
       0x22 => _strings.scan(at),
       _ when _classes.isDigit(unit) || unit == 0x2d => _numbers.scan(at),
-      _ when _classes.isNameStart(unit) => _name(at),
+      _ when _classes.isNameStart(unit) => _reader.name(at),
       _ => _unexpected(at),
     };
   }
 
-  Token _name(int start) {
-    var end = start + 1;
-    while (_classes.isNameContinue(_reader.unitAt(end))) {
-      end++;
-    }
-    return Token(.name, start, end, value: _reader.slice(start, end));
-  }
-
   /// A comment runs to a line terminator or to a character that is not
   /// a source character, which the next token reports.
   Token _comment(int start) {
```

- [ ] **Step 4: Write the coordinate lexer**

graphql-js's `SchemaCoordinateLexer`: punctuators `( ) . : @`, names, and an error token with "Invalid character" for anything else. A lone surrogate is `GQL002` as in a document; everything else is `GQL001`, whose catalog entry now says so. No new code.

Create `packages/typed_graphql/lib/src/language/lexer/schema_coordinate_lexer.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import 'character_class.dart';
import 'source_reader.dart';
import 'token.dart';
import 'token_kind.dart';
import 'token_source.dart';

/// Turns a schema coordinate into tokens: names, `.`, `(`, `)`, `:` and
/// `@` (September2025 §2 "Schema Coordinates").
///
/// A coordinate has no ignored tokens, so white space, line terminators,
/// commas and comments are invalid characters here. Like `Lexer`, it never
/// throws: an invalid character becomes one [TokenKind.error] token and
/// one diagnostic with graphql-js's message, `Invalid character: " ".`
final class SchemaCoordinateLexer implements TokenSource {
  /// Creates a lexer of [source] that reports into [sink].
  SchemaCoordinateLexer(Source source, DiagnosticSink sink)
    : _reader = SourceReader(source, sink);

  final SourceReader _reader;
  int _position = 0;

  static const CharacterClass _classes = CharacterClass();

  static const Map<int, TokenKind> _punctuators = {
    0x28: .parenLeft,
    0x29: .parenRight,
    0x2e: .dot,
    0x3a: .colon,
    0x40: .at,
  };

  @override
  Source get source => _reader.source;

  /// Always false: a coordinate has no token limit.
  @override
  bool get isLimitReached => false;

  @override
  Token advance() {
    final token = _scan(_position);
    _position = token.end;
    return token;
  }

  Token _scan(int at) {
    final unit = _reader.unitAt(at);
    if (_punctuators[unit] case final kind?) {
      return Token(kind, at, at + 1);
    }
    if (unit < 0) {
      return Token(.eof, at, at);
    }
    return _classes.isNameStart(unit) ? _reader.name(at) : _invalid(at);
  }

  /// A lone surrogate is [DiagnosticCode.invalidCharacter], as in a
  /// document; any other character [DiagnosticCode.unexpectedCharacter].
  Token _invalid(int at) {
    final width = _reader.characterWidthAt(at);
    final end = at + (width == 0 ? 1 : width);
    final message = 'Invalid character: ${_reader.describe(at)}.';
    final DiagnosticCode code = width == 0
        ? .invalidCharacter
        : .unexpectedCharacter;
    _reader.report(code, message, at, end);
    return Token(.error, at, end);
  }
}
```

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -27,7 +27,8 @@ enum DiagnosticCode(
   diagnosticLimitReached('GQL000'),
 
   /// `GQL001`: a character that starts no token, such as `~`, a single
-  /// quote or `..`.
+  /// quote or `..`. In a schema coordinate, any character but a name, `.`,
+  /// `(`, `)`, `:` and `@`, white space included.
   unexpectedCharacter('GQL001'),
 
   /// `GQL002`: a code unit that is not part of a Unicode scalar value: a
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -35,8 +35,10 @@ export 'src/language/ast/value.dart';
 export 'src/language/ast/variable_definition.dart';
 export 'src/language/lexer/block_string.dart';
 export 'src/language/lexer/lexer.dart';
+export 'src/language/lexer/schema_coordinate_lexer.dart';
 export 'src/language/lexer/token.dart';
 export 'src/language/lexer/token_kind.dart';
+export 'src/language/lexer/token_source.dart';
 export 'src/language/parser/graphql_syntax_exception.dart';
 export 'src/language/parser/parse_element_result.dart';
 export 'src/language/parser/parse_result.dart';
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/lexer/token_test.dart test/language/lexer/lexer_test.dart test/language/lexer/schema_coordinate_lexer_test.dart)
```

Expected: `token_test.dart` `+4`, `lexer_test.dart` `+20`, `schema_coordinate_lexer_test.dart` `+8`, each `All tests passed!`

- [ ] **Step 6: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -56,3 +56,6 @@
 - Schema coordinate nodes: the `SchemaCoordinate` family
   (`TypeCoordinate`, `MemberCoordinate`, `ArgumentCoordinate`,
   `DirectiveCoordinate`, `DirectiveArgumentCoordinate`).
+- `SchemaCoordinateLexer` and `TokenKind.dot`: the tokens of a schema
+  coordinate, with `GQL001` for any character a coordinate cannot hold;
+  `Lexer` and `SchemaCoordinateLexer` implement `TokenSource`.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -99,7 +99,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `error` token over the run and one diagnostic, with graphql-js's message
   minus "Syntax Error: ". `maxTokens` is counted here (R1.6). Scanners
   (`*_scanner.dart`) share a `SourceReader` (text, `describe`, `report`);
-  `CharacterClass` holds the character tests.
+  `CharacterClass` holds the character tests. `SchemaCoordinateLexer`
+  lexes a schema coordinate: names, `.`, `(`, `)`, `:`, `@` and no
+  ignored tokens; any other character is a `GQL001` (`GQL002` for a lone
+  surrogate) "Invalid character". `TokenKind.dot` exists for it only. Both
+  lexers implement `TokenSource`, which the parser reads.
 - `parser/`: `Parser(options:)` is const and stateless; each call builds a
   `TokenCursor` (current token, one lookahead, graphql-js's `expect*`,
   `many`, `any`, `delimitedMany`, `nested` for `maxDepth`) and grammar
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/language/lexer/lexer.dart packages/typed_graphql/lib/src/language/lexer/schema_coordinate_lexer.dart packages/typed_graphql/lib/src/language/lexer/source_reader.dart packages/typed_graphql/lib/src/language/lexer/token_kind.dart packages/typed_graphql/lib/src/language/lexer/token_source.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/lexer/lexer_test.dart packages/typed_graphql/test/language/lexer/schema_coordinate_lexer_test.dart packages/typed_graphql/test/language/lexer/token_test.dart
git commit -q -m "feat(typed_graphql): lex schema coordinates"
```

### Task 7: Parse and print schema coordinates

R1.11 and spec §2, §7: `Parser.parseSchemaCoordinate` and coordinates in `Printer`.

**Files:**
- Create: `packages/typed_graphql/lib/src/language/parser/schema_coordinate_parser.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/language/parser/parser.dart`, `packages/typed_graphql/lib/src/language/parser/token_cursor.dart`, `packages/typed_graphql/lib/src/language/printer/printer.dart`
- Test: `packages/typed_graphql/test/language/parser/parse_schema_coordinate_test.dart`, `packages/typed_graphql/test/language/printer/print_schema_coordinate_test.dart`

**Interfaces:**
- Consumes: Task 5: the coordinate nodes; Task 6: `TokenSource`, `SchemaCoordinateLexer`, `TokenKind.dot`; M2a: `TokenCursor`, `SyntaxAbort`, `ParseElementResult`, `Printer`.
- Produces:
  - `ParseElementResult<SchemaCoordinate> Parser.parseSchemaCoordinate(Source source)`;
  - `TokenCursor.lexer` is a `TokenSource`;
  - internal `SchemaCoordinateParser(TokenCursor cursor)` with `SchemaCoordinate coordinate()`;
  - `Printer.print` prints a coordinate as written, minified or not.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/parser/parse_schema_coordinate_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  SchemaCoordinate coordinateOf(String text) =>
      switch (parser.parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  /// Each diagnostic of parsing [text] as `line:column id message`; the
  /// test expects a failure.
  List<String> errorsOf(String text) =>
      switch (parser.parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess() => fail('expected syntax errors'),
        ParseElementFailure(:final diagnostics) => [
          for (final diagnostic in diagnostics)
            '${diagnostic.span?.location} ${diagnostic.code.id} '
                '${diagnostic.message}',
        ],
      };

  test('parses each of the five forms into its node', () {
    expect(
      coordinateOf('Query'),
      isA<TypeCoordinate>().having((node) => node.name.value, 'name', 'Query'),
    );
    expect(
      coordinateOf('Query.hero'),
      isA<MemberCoordinate>().having(
        (node) => node.memberName.value,
        'memberName',
        'hero',
      ),
    );
    expect(
      coordinateOf('Query.hero(episode:)'),
      isA<ArgumentCoordinate>()
          .having((node) => node.fieldName.value, 'fieldName', 'hero')
          .having((node) => node.argumentName.value, 'argument', 'episode'),
    );
    expect(
      coordinateOf('@deprecated'),
      isA<DirectiveCoordinate>().having(
        (node) => node.name.value,
        'name',
        'deprecated',
      ),
    );
    expect(
      coordinateOf('@deprecated(reason:)'),
      isA<DirectiveArgumentCoordinate>().having(
        (node) => node.argumentName.value,
        'argumentName',
        'reason',
      ),
    );
  });

  test('a coordinate spans the whole text, its names their own', () {
    final coordinate = coordinateOf('@a(b:)');
    expect((coordinate.start, coordinate.end), (0, 6));
    expect((coordinate.name.start, coordinate.name.end), (1, 2));
  });

  test('a third name is an error at the second dot', () {
    expect(errorsOf('MyType.field.deep'), [
      '1:13 GQL007 Expected <EOF>, found ".".',
    ]);
  });

  test('a directive has no member', () {
    expect(errorsOf('@myDirective.field'), [
      '1:13 GQL007 Expected <EOF>, found ".".',
    ]);
  });

  test('a type has no argument', () {
    expect(errorsOf('MyType(arg:)'), [
      '1:7 GQL007 Expected <EOF>, found "(".',
    ]);
  });

  test('an argument coordinate holds no value', () {
    expect(errorsOf('MyType.field(arg: value)'), [
      '1:18 GQL001 Invalid character: " ".',
    ]);
    expect(errorsOf('MyType.field(arg:value)'), [
      '1:18 GQL007 Expected ")", found Name "value".',
    ]);
  });

  test('ignored tokens around a coordinate are errors', () {
    expect(errorsOf(' Query'), ['1:1 GQL001 Invalid character: " ".']);
    expect(errorsOf('Query\n'), ['1:6 GQL001 Invalid character: U+000A.']);
  });

  test('empty text is a missing name', () {
    expect(errorsOf(''), ['1:1 GQL007 Expected Name, found <EOF>.']);
  });

  test('document syntax is not a coordinate', () {
    expect(errorsOf('{ a }'), ['1:1 GQL001 Invalid character: "{".']);
  });
}
```

Create `packages/typed_graphql/test/language/printer/print_schema_coordinate_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();
  const texts = [
    'Query',
    'Query.hero',
    'Query.hero(episode:)',
    '@deprecated',
    '@deprecated(reason:)',
  ];

  SchemaCoordinate coordinateOf(String text) =>
      switch (parser.parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  test('prints each form as it is written', () {
    for (final text in texts) {
      expect(const Printer().print(coordinateOf(text)), text);
    }
  });

  test('the minified form of a coordinate is the canonical one', () {
    for (final text in texts) {
      expect(const Printer(isMinified: true).print(coordinateOf(text)), text);
    }
  });

  test('prints a coordinate built in code', () {
    const coordinate = ArgumentCoordinate(Name('T'), Name('f'), Name('a'));
    expect(const Printer().print(coordinate), 'T.f(a:)');
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_schema_coordinate_test.dart test/language/printer/print_schema_coordinate_test.dart)
```

Expected: FAIL. `Error: The method 'parseSchemaCoordinate' isn't defined for the type 'Parser'.`

- [ ] **Step 3: Write the coordinate grammar**

The cursor now reads any `TokenSource`. `SchemaCoordinateParser` reads `@`? Name, then `.` Name, then `(` Name `:` `)`, and a record `switch` picks the node; a directive with a member or a type with an argument fails at the token graphql-js names.

In `packages/typed_graphql/lib/src/language/parser/token_cursor.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,9 +3,9 @@ import '../../diagnostics/diagnostic_code.dart';
 import '../../diagnostics/diagnostic_sink.dart';
 import '../../diagnostics/source_span.dart';
 import '../ast/name.dart';
-import '../lexer/lexer.dart';
 import '../lexer/token.dart';
 import '../lexer/token_kind.dart';
+import '../lexer/token_source.dart';
 import 'syntax_abort.dart';
 
 /// The parser's view of the token stream: the current token, one token of
@@ -20,8 +20,8 @@ final class TokenCursor {
   TokenCursor(this.lexer, this.sink, {this.maxDepth})
     : _token = lexer.advance();
 
-  /// The token source.
-  final Lexer lexer;
+  /// The token source: a document's or a schema coordinate's lexer.
+  final TokenSource lexer;
 
   /// Where syntax errors go.
   final DiagnosticSink sink;
```

Create `packages/typed_graphql/lib/src/language/parser/schema_coordinate_parser.dart`:

```dart
import '../ast/name.dart';
import '../ast/schema_coordinate.dart';
import 'token_cursor.dart';

/// Parses the schema coordinate grammar (September2025 §2 "Schema
/// Coordinates"), as graphql-js's `parseSchemaCoordinate` does.
final class SchemaCoordinateParser {
  /// Creates a parser reading from [cursor], which must read a
  /// `SchemaCoordinateLexer`.
  SchemaCoordinateParser(this.cursor);

  /// The token stream.
  final TokenCursor cursor;

  /// `SchemaCoordinate`: `Name`, `Name.Name`, `Name.Name(Name:)`, `@Name`
  /// or `@Name(Name:)`.
  SchemaCoordinate coordinate() {
    final start = cursor.token.start;
    final isDirective = cursor.expectOptional(.at);
    final name = cursor.name();
    final memberName = !isDirective && cursor.expectOptional(.dot)
        ? cursor.name()
        : null;
    final hasArgument =
        (isDirective || memberName != null) && cursor.peek(.parenLeft);
    final argumentName = hasArgument ? _argumentName() : null;
    final end = cursor.lastEnd;
    return switch ((isDirective, memberName, argumentName)) {
      (true, _, final argument?) => DirectiveArgumentCoordinate(
        name,
        argument,
        start: start,
        end: end,
      ),
      (true, _, null) => DirectiveCoordinate(name, start: start, end: end),
      (false, final member?, final argument?) => ArgumentCoordinate(
        name,
        member,
        argument,
        start: start,
        end: end,
      ),
      (false, final member?, null) => MemberCoordinate(
        name,
        member,
        start: start,
        end: end,
      ),
      (false, null, _) => TypeCoordinate(name, start: start, end: end),
    };
  }

  /// `(Name:)`.
  Name _argumentName() {
    cursor.expect(.parenLeft);
    final name = cursor.name();
    cursor.expect(.colon);
    cursor.expect(.parenRight);
    return name;
  }
}
```

- [ ] **Step 4: Add the entry point**

`parseValue`, `parseTypeRef` and `parseSchemaCoordinate` now share `_complete`: read the element, expect `<EOF>`, and turn a `SyntaxAbort` into a failure. `ParserOptions` do not apply to a coordinate.

In `packages/typed_graphql/lib/src/language/parser/parser.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,9 +3,11 @@ import '../../diagnostics/source.dart';
 import '../ast/definition.dart';
 import '../ast/document.dart';
 import '../ast/node.dart';
+import '../ast/schema_coordinate.dart';
 import '../ast/type_ref.dart';
 import '../ast/value.dart';
 import '../lexer/lexer.dart';
+import '../lexer/schema_coordinate_lexer.dart';
 import 'definition_parser.dart';
 import 'directive_extension_grammar.dart';
 import 'directive_parser.dart';
@@ -15,6 +17,7 @@ import 'parse_element_result.dart';
 import 'parse_result.dart';
 import 'parser_options.dart';
 import 'recovery.dart';
+import 'schema_coordinate_parser.dart';
 import 'selection_parser.dart';
 import 'syntax_abort.dart';
 import 'token_cursor.dart';
@@ -66,6 +69,15 @@ final class Parser {
   ParseElementResult<TypeRef> parseTypeRef(Source source) =>
       _element(source, (cursor) => ValueParser(cursor).typeRef());
 
+  /// Parses [source] as a schema coordinate, such as `Query.hero(id:)`,
+  /// which holds no ignored tokens. [options] do not apply: a coordinate
+  /// has no limits and no working-draft syntax.
+  ParseElementResult<SchemaCoordinate> parseSchemaCoordinate(Source source) {
+    final sink = DiagnosticSink();
+    final cursor = TokenCursor(SchemaCoordinateLexer(source, sink), sink);
+    return _complete(cursor, SchemaCoordinateParser(cursor).coordinate);
+  }
+
   TokenCursor _cursor(Source source, DiagnosticSink sink) => TokenCursor(
     Lexer(source, sink, maxTokens: options.maxTokens),
     sink,
@@ -111,8 +123,18 @@ final class Parser {
   ) {
     final sink = DiagnosticSink();
     final cursor = _cursor(source, sink);
+    return _complete(cursor, () => parse(cursor));
+  }
+
+  /// The element [parse] reads from [cursor], which must then be at the
+  /// end; a failure when the cursor's sink has an error.
+  ParseElementResult<T> _complete<T extends Node>(
+    TokenCursor cursor,
+    T Function() parse,
+  ) {
+    final sink = cursor.sink;
     try {
-      final element = parse(cursor);
+      final element = parse();
       cursor.expect(.eof);
       if (!sink.hasErrors) {
         return ParseElementSuccess(element, sink.diagnostics);
```

- [ ] **Step 5: Print coordinates**

A coordinate prints as it is written, in both forms. It skips `Minifier`, whose document lexer would reject the `.`.

In `packages/typed_graphql/lib/src/language/printer/printer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,6 +10,7 @@ import '../ast/name.dart';
 import '../ast/node.dart';
 import '../ast/object_field.dart';
 import '../ast/operation_type_definition.dart';
+import '../ast/schema_coordinate.dart';
 import '../ast/selection.dart';
 import '../ast/selection_set.dart';
 import '../ast/type_ref.dart';
@@ -52,7 +53,12 @@ final class Printer {
   /// subclass this library does not define.
   String print(Node node) {
     final canonical = _canonical(node);
-    return isMinified ? const Minifier().minify(canonical) : canonical;
+    // A coordinate has no ignored characters, and the document lexer of
+    // the minifier would reject its `.`.
+    final isDocumentText = node is! SchemaCoordinate;
+    return isMinified && isDocumentText
+        ? const Minifier().minify(canonical)
+        : canonical;
   }
 
   String _canonical(Node node) => switch (node) {
@@ -71,9 +77,27 @@ final class Printer {
     InputValueDefinition() => _members.inputValue(node),
     EnumValueDefinition() => _members.enumValue(node),
     OperationTypeDefinition() => _members.operationType(node),
+    SchemaCoordinate() => _coordinate(node),
     _ => throw ArgumentError.value(node, 'node', 'is not a GraphQL node'),
   };
 
+  /// graphql-js's `print` of a coordinate, with no space anywhere.
+  static String _coordinate(SchemaCoordinate coordinate) =>
+      switch (coordinate) {
+        TypeCoordinate(:final name) => name.value,
+        MemberCoordinate(:final name, :final memberName) =>
+          '${name.value}.${memberName.value}',
+        ArgumentCoordinate(
+          :final name,
+          :final fieldName,
+          :final argumentName,
+        ) =>
+          '${name.value}.${fieldName.value}(${argumentName.value}:)',
+        DirectiveCoordinate(:final name) => '@${name.value}',
+        DirectiveArgumentCoordinate(:final name, :final argumentName) =>
+          '@${name.value}(${argumentName.value}:)',
+      };
+
   String _definition(Definition definition) => switch (definition) {
     ExecutableDefinition() => _executable.definition(definition),
     TypeSystemDefinition() => _typeSystem.definition(definition),
```

- [ ] **Step 6: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/language/parser/parse_schema_coordinate_test.dart test/language/printer/print_schema_coordinate_test.dart)
```

Expected: `parse_schema_coordinate_test.dart` `+9`, `print_schema_coordinate_test.dart` `+3`, each `All tests passed!`

- [ ] **Step 7: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -59,3 +59,6 @@
 - `SchemaCoordinateLexer` and `TokenKind.dot`: the tokens of a schema
   coordinate, with `GQL001` for any character a coordinate cannot hold;
   `Lexer` and `SchemaCoordinateLexer` implement `TokenSource`.
+- `Parser.parseSchemaCoordinate`: a schema coordinate such as
+  `Query.hero(episode:)` as a `ParseElementResult<SchemaCoordinate>`.
+- `Printer` prints schema coordinates, the same in both forms.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -122,6 +122,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   grammar before the base ones. `DirectiveExtensionGrammar` is always
   registered; with `allowDirectiveExtensions` off, it and the directive
   definition's draft parts report `GQL014` instead of a generic error.
+  `Parser.parseSchemaCoordinate` runs `SchemaCoordinateParser` over a
+  cursor on a `SchemaCoordinateLexer` (the cursor reads any
+  `TokenSource`); `ParserOptions` do not apply to it.
 - `printer/`: `Printer` prints any node as graphql-js's `print` does, to
   the character (80-column wrapping included), through collaborators:
   `ValuePrinter` (values, types, arguments, directives), `ExecutablePrinter`,
@@ -131,6 +134,8 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `Printer(isMinified: true)` passes the canonical text through `Minifier`
   (graphql-js's `stripIgnoredCharacters`: a space only between two
   non-punctuators or before `...`, block strings in their shortest form).
+  A `SchemaCoordinate` prints the same in both forms and never goes
+  through `Minifier`, whose document lexer would reject its `.`.
 - `visitor/`: `AstWalker().walk(root, visitor)` walks depth-first through
   `children` with its own stack (no recursion), calling
   `AstVisitor.enter` (returns `VisitAction.next`, `skip` or `stop`) and
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/language/parser/parser.dart packages/typed_graphql/lib/src/language/parser/schema_coordinate_parser.dart packages/typed_graphql/lib/src/language/parser/token_cursor.dart packages/typed_graphql/lib/src/language/printer/printer.dart packages/typed_graphql/test/language/parser/parse_schema_coordinate_test.dart packages/typed_graphql/test/language/printer/print_schema_coordinate_test.dart
git commit -q -m "feat(typed_graphql): parse and print schema coordinates"
```

### Task 8: Port the graphql-js schema coordinate suites

The coordinate tests of `parser-test.ts` and `printer-test.ts`, and `schemaCoordinateLexer-test.ts`.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql_conformance/test/language/parser/parser_schema_coordinate_test.dart`, `packages/typed_graphql_conformance/test/language/printer/printer_test.dart`, `packages/typed_graphql_conformance/test/language/schema_coordinate_lexer_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/ast_json.dart`, `packages/typed_graphql_conformance/test/support/lexer_port.dart`, `packages/typed_graphql_conformance/test/support/parser_port.dart`

**Interfaces:**
- Consumes: Tasks 5–7; M2a's `AstJson`, `LexerPort`, `ParserPort`, `ErrorJson`.
- Produces:
  - `AstJson` writes the five coordinate kinds;
  - `ParserPort.parseSchemaCoordinate(String text)` and `ParserPort.coordinateSyntaxError(String text)`;
  - `LexerPort.coordinateLexOne(String text)` and `LexerPort.coordinateSyntaxError(String text, {int count = 2})`;
  - rows: `parser-test.ts` and `printer-test.ts` flipped, 4 for `schemaCoordinateLexer-test.ts`.

- [ ] **Step 1: Write the port helpers**

`AstJson` writes the five coordinate kinds as graphql-js's `toJSONDeep`; the ports get graphql-js's coordinate helpers.

In `packages/typed_graphql_conformance/test/support/ast_json.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -35,6 +35,7 @@ final class AstJson {
     Selection() ||
     VariableDefinition() => _executable(node),
     TypeSystemExtension() => _extension(node),
+    SchemaCoordinate() => _coordinate(node),
     _ => _typeSystem(node),
   };
 
@@ -55,6 +56,31 @@ final class AstJson {
   List<Object?>? _optional(List<Node> nodes) =>
       nodes.isEmpty ? null : _all(nodes);
 
+  Map<String, Object?> _coordinate(SchemaCoordinate node) => switch (node) {
+    TypeCoordinate(:final name) => _node(node, 'TypeCoordinate', {
+      'name': of(name),
+    }),
+    MemberCoordinate(:final name, :final memberName) => _node(
+      node,
+      'MemberCoordinate',
+      {'name': of(name), 'memberName': of(memberName)},
+    ),
+    ArgumentCoordinate(:final name, :final fieldName, :final argumentName) =>
+      _node(node, 'ArgumentCoordinate', {
+        'name': of(name),
+        'fieldName': of(fieldName),
+        'argumentName': of(argumentName),
+      }),
+    DirectiveCoordinate(:final name) => _node(node, 'DirectiveCoordinate', {
+      'name': of(name),
+    }),
+    DirectiveArgumentCoordinate(:final name, :final argumentName) => _node(
+      node,
+      'DirectiveArgumentCoordinate',
+      {'name': of(name), 'argumentName': of(argumentName)},
+    ),
+  };
+
   Map<String, Object?> _value(Value value) => switch (value) {
     Variable(:final name) => _node(value, 'Variable', {'name': of(name)}),
     IntValue(value: final lexeme) => _node(value, 'IntValue', {
```

In `packages/typed_graphql_conformance/test/support/lexer_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -58,6 +58,24 @@ final class LexerPort {
     return const ErrorJson().of(sink.diagnostics.first);
   }
 
+  /// The first token of [text] from a [SchemaCoordinateLexer].
+  Map<String, Object?> coordinateLexOne(String text) {
+    final source = Source(text);
+    final lexer = SchemaCoordinateLexer(source, DiagnosticSink());
+    return _json(source, lexer.advance());
+  }
+
+  /// The first diagnostic of reading [count] tokens of [text] with a
+  /// [SchemaCoordinateLexer], which graphql-js throws.
+  Map<String, Object?> coordinateSyntaxError(String text, {int count = 2}) {
+    final sink = DiagnosticSink();
+    final lexer = SchemaCoordinateLexer(Source(text), sink);
+    for (var i = 0; i < count; i++) {
+      lexer.advance();
+    }
+    return const ErrorJson().of(sink.diagnostics.first);
+  }
+
   /// [kind] as graphql-js's `TokenKind` value, such as `Name` or `{`.
   String kindOf(TokenKind kind) => kind.isPunctuator
       ? kind.description.replaceAll('"', '')
```

In `packages/typed_graphql_conformance/test/support/parser_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -41,6 +41,15 @@ final class ParserPort {
   Object? parseType(String text) =>
       const AstJson().of(_element(_parser.parseTypeRef(Source(text))));
 
+  /// `toJSONDeep(parseSchemaCoordinate(text))`.
+  Object? parseSchemaCoordinate(String text) => const AstJson().of(
+    _element(_parser.parseSchemaCoordinate(Source(text))),
+  );
+
+  /// The first diagnostic of `parseSchemaCoordinate(text)`.
+  Map<String, Object?> coordinateSyntaxError(String text) =>
+      _firstError(_parser.parseSchemaCoordinate(Source(text)).diagnostics);
+
   /// The first diagnostic of `parseValue(text)`.
   Map<String, Object?> valueSyntaxError(String text) =>
       _firstError(_parser.parseValue(Source(text)).diagnostics);
```

- [ ] **Step 2: Write the ported tests**

The `parseSchemaCoordinate` tests of `parser-test.ts` and the coordinate tests of `printer-test.ts` were `skipped` in M2a ("schema coordinates arrive in M2b"); they are ported now.

Create `packages/typed_graphql_conformance/test/language/schema_coordinate_lexer_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/schemaCoordinateLexer-test.ts;
// see mapping/language.csv.
import 'package:test/test.dart';

import '../support/contain.dart';
import '../support/lexer_port.dart';

void main() {
  const port = LexerPort();
  const contain = Contain();

  group('SchemaCoordinateLexer', () {
    test('tracks a schema coordinate', () {
      expect(
        port.coordinateLexOne('Name.field'),
        contain({'kind': 'Name', 'start': 0, 'end': 4, 'value': 'Name'}),
      );
    });

    test('forbids ignored tokens', () {
      expect(port.coordinateSyntaxError('\nName.field', count: 1), {
        'message': 'Syntax Error: Invalid character: U+000A.',
        'locations': [
          {'line': 1, 'column': 1},
        ],
      });
    });

    test('lex reports a useful syntax errors', () {
      expect(port.coordinateSyntaxError('Foo .bar'), {
        'message': 'Syntax Error: Invalid character: " ".',
        'locations': [
          {'line': 1, 'column': 4},
        ],
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/language/parser/parser_schema_coordinate_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/parser_port.dart';

void main() {
  const port = ParserPort();

  Map<String, Object?> name(String value, int start, int end) => {
    'kind': 'Name',
    'loc': {'start': start, 'end': end},
    'value': value,
  };

  Map<String, Object?> error(String message, int column) => {
    'message': message,
    'locations': [
      {'line': 1, 'column': column},
    ],
  };

  group('Parser', () {
    group('parseSchemaCoordinate', () {
      test('parses Name', () {
        expect(port.parseSchemaCoordinate('MyType'), {
          'kind': 'TypeCoordinate',
          'loc': {'start': 0, 'end': 6},
          'name': name('MyType', 0, 6),
        });
      });

      test('parses Name . Name', () {
        expect(port.parseSchemaCoordinate('MyType.field'), {
          'kind': 'MemberCoordinate',
          'loc': {'start': 0, 'end': 12},
          'name': name('MyType', 0, 6),
          'memberName': name('field', 7, 12),
        });
      });

      test('rejects Name . Name . Name', () {
        expect(
          port.coordinateSyntaxError('MyType.field.deep'),
          error('Syntax Error: Expected <EOF>, found ".".', 13),
        );
      });

      test('parses Name . Name ( Name : )', () {
        expect(port.parseSchemaCoordinate('MyType.field(arg:)'), {
          'kind': 'ArgumentCoordinate',
          'loc': {'start': 0, 'end': 18},
          'name': name('MyType', 0, 6),
          'fieldName': name('field', 7, 12),
          'argumentName': name('arg', 13, 16),
        });
      });

      test('rejects Name . Name ( Name : Name )', () {
        expect(
          port.coordinateSyntaxError('MyType.field(arg: value)'),
          error('Syntax Error: Invalid character: " ".', 18),
        );
      });

      test('parses @ Name', () {
        expect(port.parseSchemaCoordinate('@myDirective'), {
          'kind': 'DirectiveCoordinate',
          'loc': {'start': 0, 'end': 12},
          'name': name('myDirective', 1, 12),
        });
      });

      test('parses @ Name ( Name : )', () {
        expect(port.parseSchemaCoordinate('@myDirective(arg:)'), {
          'kind': 'DirectiveArgumentCoordinate',
          'loc': {'start': 0, 'end': 18},
          'name': name('myDirective', 1, 12),
          'argumentName': name('arg', 13, 16),
        });
      });

      test('parses __Type', () {
        expect(port.parseSchemaCoordinate('__Type'), {
          'kind': 'TypeCoordinate',
          'loc': {'start': 0, 'end': 6},
          'name': name('__Type', 0, 6),
        });
      });

      test('parses Type.__metafield', () {
        expect(port.parseSchemaCoordinate('Type.__metafield'), {
          'kind': 'MemberCoordinate',
          'loc': {'start': 0, 'end': 16},
          'name': name('Type', 0, 4),
          'memberName': name('__metafield', 5, 16),
        });
      });

      test('parses Type.__metafield(arg:)', () {
        expect(port.parseSchemaCoordinate('Type.__metafield(arg:)'), {
          'kind': 'ArgumentCoordinate',
          'loc': {'start': 0, 'end': 22},
          'name': name('Type', 0, 4),
          'fieldName': name('__metafield', 5, 16),
          'argumentName': name('arg', 17, 20),
        });
      });

      test('rejects @ Name . Name', () {
        expect(
          port.coordinateSyntaxError('@myDirective.field'),
          error('Syntax Error: Expected <EOF>, found ".".', 13),
        );
      });
    });
  });
}
```

In `packages/typed_graphql_conformance/test/language/printer/printer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -293,6 +293,42 @@ void main() {
         '''),
       );
     });
+
+    test('prints schema coordinates', () {
+      String printCoordinate(String text) =>
+          switch (const Parser().parseSchemaCoordinate(Source(text))) {
+            ParseElementSuccess(:final value) => printer.print(value),
+            ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
+          };
+      expect(printCoordinate('Name'), 'Name');
+      expect(printCoordinate('Name.field'), 'Name.field');
+      expect(printCoordinate('Name.field(arg:)'), 'Name.field(arg:)');
+      expect(printCoordinate('@name'), '@name');
+      expect(printCoordinate('@name(arg:)'), '@name(arg:)');
+      expect(printCoordinate('__Type'), '__Type');
+      expect(printCoordinate('Type.__metafield'), 'Type.__metafield');
+      expect(
+        printCoordinate('Type.__metafield(arg:)'),
+        'Type.__metafield(arg:)',
+      );
+    });
+
+    // Adapted: parsing reports the error as a diagnostic instead of
+    // throwing, so there is nothing to print; the messages are the same.
+    test('throws syntax error for ignored tokens in schema coordinates', () {
+      expect(
+        port.coordinateSyntaxError('# foo\nName')['message'],
+        startsWith('Syntax Error: Invalid character: "#"'),
+      );
+      expect(
+        port.coordinateSyntaxError('\nName')['message'],
+        'Syntax Error: Invalid character: U+000A.',
+      );
+      expect(
+        port.coordinateSyntaxError('Name .field')['message'],
+        startsWith('Syntax Error: Invalid character: " "'),
+      );
+    });
   });
 }
 
```

- [ ] **Step 3: Run the ported tests**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/schema_coordinate_lexer_test.dart test/language/parser/parser_schema_coordinate_test.dart test/language/printer/printer_test.dart)
```

Expected: `schema_coordinate_lexer_test.dart` `+3`, `parser_schema_coordinate_test.dart` `+11`, `printer_test.dart` `+12`, each `All tests passed!`

- [ ] **Step 4: Mark the file as ported and see the coverage check fail**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -19,6 +19,7 @@ const Set<String> portedFiles = {
   'schema-printer-test.ts',
   'printString-test.ts',
   'visitor-test.ts',
+  'schemaCoordinateLexer-test.ts',
 };
 
 void main() {
```

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of schemaCoordinateLexer-test.ts`: `Actual: Set:[]`, followed by the missing `(group, test)` pairs. This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 5: Write the rows**

The parser and printer rows flip from `skipped` to `ported` or `adapted`; `accepts a Source object` stays skipped. `schemaCoordinateLexer-test.ts` gets 4 rows (3 ported, 1 skipped).

In `packages/typed_graphql_conformance/mapping/language.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -90,18 +90,18 @@ parser-test.ts,Parser > parseType,parses custom types,ported,test/language/parse
 parser-test.ts,Parser > parseType,parses list types,ported,test/language/parser/parser_values_test.dart,
 parser-test.ts,Parser > parseType,parses non-null types,ported,test/language/parser/parser_values_test.dart,
 parser-test.ts,Parser > parseType,parses nested types,ported,test/language/parser/parser_values_test.dart,
-parser-test.ts,Parser > parseSchemaCoordinate,parses Name,skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,parses Name . Name,skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,rejects Name . Name . Name,skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,parses Name . Name ( Name : ),skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,rejects Name . Name ( Name : Name ),skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,parses @ Name,skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,parses @ Name ( Name : ),skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,parses __Type,skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,parses Type.__metafield,skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,parses Type.__metafield(arg:),skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,rejects @ Name . Name,skipped,,Schema coordinates arrive in stage M2b.
-parser-test.ts,Parser > parseSchemaCoordinate,accepts a Source object,skipped,,Schema coordinates arrive in stage M2b.
+parser-test.ts,Parser > parseSchemaCoordinate,parses Name,ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,parses Name . Name,ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,rejects Name . Name . Name,ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,parses Name . Name ( Name : ),ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,rejects Name . Name ( Name : Name ),ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,parses @ Name,ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,parses @ Name ( Name : ),ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,parses __Type,ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,parses Type.__metafield,ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,parses Type.__metafield(arg:),ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,rejects @ Name . Name,ported,test/language/parser/parser_schema_coordinate_test.dart,
+parser-test.ts,Parser > parseSchemaCoordinate,accepts a Source object,skipped,,Dart entry points take a Source only: there is no string form to compare with.
 parser-test.ts,Parser > operation and variable definition descriptions,parses operation with description and variable descriptions,ported,test/language/parser/parser_descriptions_test.dart,
 parser-test.ts,Parser > operation and variable definition descriptions,descriptions on a short-hand query produce a sensible error,ported,test/language/parser/parser_descriptions_test.dart,
 parser-test.ts,Parser > operation and variable definition descriptions,"parses variable definition with description, default value, and directives",ported,test/language/parser/parser_descriptions_test.dart,
@@ -166,8 +166,8 @@ printer-test.ts,Printer: Query document,prints fragment spread with arguments,sk
 printer-test.ts,Printer: Query document,prints fragment spread with multi-line arguments,skipped,,experimental fragment arguments are out of scope (R1.14)
 printer-test.ts,Printer: Query document,prints fragment,ported,test/language/printer/printer_test.dart,
 printer-test.ts,Printer: Query document,prints kitchen sink without altering ast,adapted,test/language/printer/printer_test.dart,Nodes are immutable so the AST cannot be altered; isEquivalentTo stands for the deep equality without locations.
-printer-test.ts,Printer: Query document,prints schema coordinates,skipped,,schema coordinates arrive in stage M2b
-printer-test.ts,Printer: Query document,throws syntax error for ignored tokens in schema coordinates,skipped,,schema coordinates arrive in stage M2b
+printer-test.ts,Printer: Query document,prints schema coordinates,ported,test/language/printer/printer_test.dart,
+printer-test.ts,Printer: Query document,throws syntax error for ignored tokens in schema coordinates,adapted,test/language/printer/printer_test.dart,Parsing reports the error as a diagnostic instead of throwing; the messages are the same.
 schema-printer-test.ts,Printer: SDL document,prints minimal ast,ported,test/language/printer/schema_printer_test.dart,
 schema-printer-test.ts,Printer: SDL document,produces helpful error messages,adapted,test/language/printer/schema_printer_test.dart,Dart's types admit no plain object: a node class the library does not define gives an ArgumentError.
 schema-printer-test.ts,Printer: SDL document,prints kitchen sink without altering ast,adapted,test/language/printer/schema_printer_test.dart,The kitchen sink needs ParserOptions.allowDirectiveExtensions; nodes are immutable and isEquivalentTo stands for the deep equality without locations.
@@ -206,3 +206,7 @@ visitor-test.ts,Visitor > visitInParallel,allows early exit while leaving,skippe
 visitor-test.ts,Visitor > visitInParallel,allows early exit from leaving different points,skipped,,AstVisitor.leave returns nothing (spec §6): a walk stops only from enter.
 visitor-test.ts,Visitor > visitInParallel,allows for editing on enter,skipped,,ParallelVisitor only reads; AstTransformer does the editing.
 visitor-test.ts,Visitor > visitInParallel,allows for editing on leave,skipped,,ParallelVisitor only reads; AstTransformer does the editing.
+schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,can be stringified,skipped,,Symbol.toStringTag is JavaScript only.
+schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,tracks a schema coordinate,ported,test/language/schema_coordinate_lexer_test.dart,
+schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,forbids ignored tokens,ported,test/language/schema_coordinate_lexer_test.dart,
+schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,lex reports a useful syntax errors,ported,test/language/schema_coordinate_lexer_test.dart,
```

- [ ] **Step 6: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+199: All tests passed!`

- [ ] **Step 7: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,4 +8,5 @@
   checks it.
 - Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`,
   `parser-test.ts`, `schema-parser-test.ts`, `printer-test.ts`,
-  `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`.
+  `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`,
+  `schemaCoordinateLexer-test.ts`.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/language.csv packages/typed_graphql_conformance/test/language/parser/parser_schema_coordinate_test.dart packages/typed_graphql_conformance/test/language/printer/printer_test.dart packages/typed_graphql_conformance/test/language/schema_coordinate_lexer_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/ast_json.dart packages/typed_graphql_conformance/test/support/lexer_port.dart packages/typed_graphql_conformance/test/support/parser_port.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js schema coordinate suites"
```

### Task 9: Source excerpts as graphql-js printLocation

Spec §1 names the `printLocation` port: a diagnostic's place shown in its lines, as graphql-js prints an error.

**Files:**
- Create: `packages/typed_graphql/lib/src/diagnostics/source_excerpt.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/source_span.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql/test/diagnostics/source_excerpt_test.dart`, `packages/typed_graphql_conformance/test/language/lexer_test.dart`, `packages/typed_graphql_conformance/test/language/parser/parser_test.dart`, `packages/typed_graphql_conformance/test/language/print_location_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/error_json.dart`, `packages/typed_graphql_conformance/test/support/lexer_port.dart`

**Interfaces:**
- Consumes: M1: `Source`, `SourceLocation`, `SourceSpan` (`location`); M2a: `ErrorJson`, `LexerPort`.
- Produces:
  - `final class SourceExcerpt` with `const SourceExcerpt()` and `String of(Source source, SourceLocation location)`;
  - `String get SourceSpan.excerpt`: the excerpt at the span's start;
  - test helpers `ErrorJson.printed(Diagnostic)` and `LexerPort.printedSyntaxError(String text)`;
  - rows: 3 for `printLocation-test.ts`, 2 for `source-test.ts`, 3 flipped in `lexer-test.ts` and `parser-test.ts`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/diagnostics/source_excerpt_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const excerpt = SourceExcerpt();

  test('shows the line before, the line with a caret and the line after', () {
    expect(
      excerpt.of(Source('\n\n ~\n'), const SourceLocation(3, 2)),
      'GraphQL request:3:2\n'
      '2 |\n'
      '3 |  ~\n'
      '  |  ^\n'
      '4 |',
    );
  });

  test('leaves out the lines a document does not have', () {
    expect(
      excerpt.of(Source('{', name: 'a.graphql'), const SourceLocation(1, 2)),
      'a.graphql:1:2\n'
      '1 | {\n'
      '  |  ^',
    );
  });

  test('pads every prefix to the widest line number', () {
    expect(
      excerpt.of(Source('${'\n' * 8}*\n'), const SourceLocation(9, 1)),
      'GraphQL request:9:1\n'
      ' 8 |\n'
      ' 9 | *\n'
      '   | ^\n'
      '10 |',
    );
  });

  test('cuts a line longer than 120 units into 80-unit pieces', () {
    final line = '${'a' * 80}${'b' * 80}${'c' * 10}';
    expect(
      excerpt.of(Source(line), const SourceLocation(1, 85)),
      'GraphQL request:1:85\n'
      '1 | ${'a' * 80}\n'
      '  | ${'b' * 80}\n'
      '  |     ^\n'
      '  | ${'c' * 10}',
    );
  });

  test('a caret after the last piece of a long line shows no piece after', () {
    final line = 'a' * 160;
    expect(
      excerpt.of(Source(line), const SourceLocation(1, 161)),
      'GraphQL request:1:161\n'
      '1 | ${'a' * 80}\n'
      '  | ${'a' * 80}\n'
      '  | ^',
    );
  });

  test('a span shows its start', () {
    final source = Source('{ a }\n{');
    final span = SourceSpan(source, 7, 7);
    expect(span.excerpt, excerpt.of(source, const SourceLocation(2, 2)));
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/diagnostics/source_excerpt_test.dart)
```

Expected: FAIL. `Error: Method not found: 'SourceExcerpt'.` and `Error: The getter 'excerpt' isn't defined for the type 'SourceSpan'.`

- [ ] **Step 3: Write the implementation**

A port of graphql-js's `printLocation` / `printSourceLocation` without `locationOffset`, which `Source` does not have. A line longer than 120 units is cut into 80-unit pieces around the caret; the piece after the caret is taken with `skip(1).take(…)`, so a caret on the last piece shows none rather than throwing a `RangeError`.

Create `packages/typed_graphql/lib/src/diagnostics/source_excerpt.dart`:

```dart
import 'dart:math';

import 'source.dart';
import 'source_location.dart';

/// Shows a location in a [Source] as graphql-js's `printSourceLocation`
/// does, character for character: `name:line:column`, the line before,
/// the line with a caret under the column, and the line after.
///
/// A line longer than 120 code units, as in a minified document, is shown
/// in 80-unit pieces up to the one after the caret.
final class SourceExcerpt {
  /// Creates the formatter; it keeps no state.
  const SourceExcerpt();

  static final RegExp _lineTerminator = RegExp('\r\n|[\n\r]');

  /// [location] in [source], which must be a location of [source].
  String of(Source source, SourceLocation location) {
    final SourceLocation(:line, :column) = location;
    final lines = source.body.split(_lineTerminator);
    final text = lines[line - 1];
    final header = '${source.name}:$line:$column\n';
    if (text.length > 120) {
      return header + _minified(line, column, text);
    }
    return header +
        _prefixed([
          ('${line - 1} |', line > 1 ? lines[line - 2] : null),
          ('$line |', text),
          ('|', '^'.padLeft(column)),
          ('${line + 1} |', line < lines.length ? lines[line] : null),
        ]);
  }

  /// The long [text] of line [line] cut into 80-unit pieces.
  String _minified(int line, int column, String text) {
    final pieces = [
      for (var start = 0; start < text.length; start += 80)
        text.substring(start, min(start + 80, text.length)),
    ];
    final caretPiece = column ~/ 80;
    return _prefixed([
      ('$line |', pieces.first),
      for (final piece in pieces.skip(1).take(caretPiece)) ('|', piece),
      ('|', '^'.padLeft(column % 80)),
      ('|', caretPiece + 1 < pieces.length ? pieces[caretPiece + 1] : null),
    ]);
  }

  /// The rows whose text exists, each prefix padded to the widest; an
  /// empty text leaves the prefix alone on its row.
  String _prefixed(List<(String, String?)> rows) {
    final present = [
      for (final row in rows)
        if (row case (final prefix, final String text)) (prefix, text),
    ];
    final width = present.map((row) => row.$1.length).reduce(max);
    return [
      for (final (prefix, text) in present)
        prefix.padLeft(width) + (text.isEmpty ? '' : ' $text'),
    ].join('\n');
  }
}
```

In `packages/typed_graphql/lib/src/diagnostics/source_span.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:meta/meta.dart';
 
 import 'source.dart';
+import 'source_excerpt.dart';
 import 'source_location.dart';
 
 /// A range of a [Source]: from [start] up to, not including, [end], both
@@ -29,6 +30,10 @@ final class const SourceSpan(
   /// The text the span covers.
   String get text => source.body.substring(start, end);
 
+  /// [start] shown in its lines with a caret, as graphql-js's
+  /// `printLocation`; see [SourceExcerpt].
+  String get excerpt => const SourceExcerpt().of(source, location);
+
   @override
   bool operator ==(Object other) =>
       other is SourceSpan &&
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,6 +10,7 @@ export 'src/diagnostics/diagnostic_code.dart';
 export 'src/diagnostics/diagnostic_severity.dart';
 export 'src/diagnostics/diagnostic_sink.dart';
 export 'src/diagnostics/source.dart';
+export 'src/diagnostics/source_excerpt.dart';
 export 'src/diagnostics/source_location.dart';
 export 'src/diagnostics/source_span.dart';
 export 'src/language/ast/argument.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/diagnostics/source_excerpt_test.dart)
```

Expected: `+6: All tests passed!`

- [ ] **Step 5: Write the port helpers**

`ErrorJson.printed` is graphql-js's `String(error)`: the message, a blank line and the excerpt.

In `packages/typed_graphql_conformance/test/support/error_json.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,16 @@ final class ErrorJson {
   /// Creates the converter; it keeps no state.
   const ErrorJson();
 
+  /// `String(error)`: the message, then the excerpt of its location, as
+  /// graphql-js's `GraphQLError.toString` prints a syntax error.
+  String printed(Diagnostic diagnostic) {
+    final message = 'Syntax Error: ${diagnostic.message}';
+    return switch (diagnostic.span) {
+      final span? => '$message\n\n${span.excerpt}',
+      null => message,
+    };
+  }
+
   /// `{message: 'Syntax Error: ...', locations: [{line, column}]}`.
   Map<String, Object?> of(Diagnostic diagnostic) {
     final location = diagnostic.span?.location;
```

In `packages/typed_graphql_conformance/test/support/lexer_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -76,6 +76,14 @@ final class LexerPort {
     return const ErrorJson().of(sink.diagnostics.first);
   }
 
+  /// `String(error)` for the first diagnostic of lexing one token of
+  /// [text].
+  String printedSyntaxError(String text) {
+    final sink = DiagnosticSink();
+    Lexer(Source(text), sink).advance();
+    return const ErrorJson().printed(sink.diagnostics.first);
+  }
+
   /// [kind] as graphql-js's `TokenKind` value, such as `Name` or `{`.
   String kindOf(TokenKind kind) => kind.isPunctuator
       ? kind.description.replaceAll('"', '')
```

- [ ] **Step 6: Port the excerpt tests**

Three tests that M2a adapted to compare messages only now compare the whole printed error. `printLocation-test.ts` is ported; its two `locationOffset` tests are adapted with eight leading line breaks, which puts the error on the same line number.

In `packages/typed_graphql_conformance/test/language/lexer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,11 +3,13 @@
 import 'package:test/test.dart';
 
 import '../support/contain.dart';
+import '../support/dedent.dart';
 import '../support/lexer_port.dart';
 
 void main() {
   const port = LexerPort();
   const contain = Contain();
+  const dedent = Dedent();
 
   void expectSyntaxError(String text, String message, int line, int column) {
     expect(port.syntaxError(text), {
@@ -61,13 +63,18 @@ void main() {
       expectSyntaxError('.', 'Syntax Error: Unexpected character: ".".', 1, 1);
     });
 
-    // Adapted: the printLocation source excerpt arrives in M2b, so only the message and the location are compared.
     test('errors respect whitespace', () {
-      expectSyntaxError(
-        '\n\n ~\n',
-        'Syntax Error: Unexpected character: "~".',
-        3,
-        2,
+      expect(
+        port.printedSyntaxError(['', '', ' ~', ''].join('\n')),
+        dedent('''
+          Syntax Error: Unexpected character: "~".
+
+          GraphQL request:3:2
+          2 |
+          3 |  ~
+            |  ^
+          4 |
+        '''),
       );
     });
 
```

In `packages/typed_graphql_conformance/test/language/parser/parser_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -24,8 +24,6 @@ void main() {
   }
 
   group('Parser', () {
-    // Adapted: String(error) adds a printLocation excerpt, which arrives in
-    // M2b; Dart checks the message, the position and the location.
     test('parse provides useful errors', () {
       final failure = const Parser().parse(Source('{')).diagnostics.first;
 
@@ -35,6 +33,17 @@ void main() {
       );
       expect(failure.span?.start, 1);
 
+      expect(
+        const ErrorJson().printed(failure),
+        dedent('''
+          Syntax Error: Expected Name, found <EOF>.
+
+          GraphQL request:1:2
+          1 | {
+            |  ^
+        '''),
+      );
+
       expect(
         port.syntaxError('''
 
@@ -61,17 +70,20 @@ void main() {
       );
     });
 
-    // Adapted: the printLocation excerpt arrives in M2b; Dart checks the
-    // message, the location and the source name.
     test('parse provides useful error when using source', () {
       final source = Source('query', name: 'MyQuery.graphql');
       final failure = const Parser().parse(source).diagnostics.first;
 
       expect(
-        const ErrorJson().of(failure),
-        error('Syntax Error: Expected "{", found <EOF>.', 1, 6),
+        const ErrorJson().printed(failure),
+        dedent('''
+          Syntax Error: Expected "{", found <EOF>.
+
+          MyQuery.graphql:1:6
+          1 | query
+            |      ^
+        '''),
       );
-      expect(failure.span?.source.name, 'MyQuery.graphql');
     });
 
     test('limits by a maximum number of tokens', () {
```

Create `packages/typed_graphql_conformance/test/language/print_location_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/printLocation-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';

void main() {
  const dedent = Dedent();
  const excerpt = SourceExcerpt();

  group('printSourceLocation', () {
    test('prints minified documents', () {
      final minifiedSource = Source(
        r'query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String){someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD...on THIRD_ERROR_HERE}}}',
      );

      String locationOf(String marker) => excerpt.of(
        minifiedSource,
        SourceLocation(1, minifiedSource.body.indexOf(marker) + 1),
      );

      expect(
        locationOf('FIRST_ERROR_HERE'),
        dedent(r'''
      GraphQL request:1:53
      1 | query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String)
        |                                                     ^
        | {someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD.
    '''),
      );

      expect(
        locationOf('SECOND_ERROR_HERE'),
        dedent(r'''
      GraphQL request:1:114
      1 | query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String)
        | {someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD.
        |                                  ^
        | ..on THIRD_ERROR_HERE}}}
    '''),
      );

      expect(
        locationOf('THIRD_ERROR_HERE'),
        dedent(r'''
      GraphQL request:1:166
      1 | query SomeMinifiedQueryWithErrorInside($foo:String!=FIRST_ERROR_HERE$bar:String)
        | {someField(foo:$foo bar:$bar baz:SECOND_ERROR_HERE){fieldA fieldB{fieldC fieldD.
        | ..on THIRD_ERROR_HERE}}}
        |      ^
    '''),
      );
    });

    // Adapted: Source has no locationOffset; eight line breaks put the `*`
    // on line 9, so the excerpt also shows the empty line 8.
    test('prints single digit line number with no padding', () {
      final result = excerpt.of(
        Source('${'\n' * 8}*', name: 'Test'),
        const SourceLocation(9, 1),
      );

      expect(
        result,
        dedent('''
          Test:9:1
          8 |
          9 | *
            | ^
        '''),
      );
    });

    // Adapted: Source has no locationOffset; eight line breaks put the `*`
    // on line 9, so the excerpt also shows the empty line 8.
    test('prints line numbers with correct padding', () {
      final result = excerpt.of(
        Source('${'\n' * 8}*\n', name: 'Test'),
        const SourceLocation(9, 1),
      );

      expect(
        result,
        dedent('''
          Test:9:1
           8 |
           9 | *
             | ^
          10 |
        '''),
      );
    });
  });
}
```

- [ ] **Step 7: Run the ported tests**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/lexer_test.dart test/language/parser/parser_test.dart test/language/print_location_test.dart)
```

Expected: `lexer_test.dart` `+16`, `parser_test.dart` `+18`, `print_location_test.dart` `+3`, each `All tests passed!`

- [ ] **Step 8: Mark the files as ported and see the coverage check fail**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,8 @@ const Set<String> portedFiles = {
   'printString-test.ts',
   'visitor-test.ts',
   'schemaCoordinateLexer-test.ts',
+  'printLocation-test.ts',
+  'source-test.ts',
 };
 
 void main() {
```

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of printLocation-test.ts`, `rows cover every test of source-test.ts`: `Actual: Set:[]`, followed by the missing `(group, test)` pairs. This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 9: Write the rows**

In `packages/typed_graphql_conformance/mapping/language.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,7 +5,7 @@ lexer-test.ts,Lexer,records line and column,ported,test/language/lexer_test.dart
 lexer-test.ts,Lexer,"can be Object.toStringified, JSON.stringified, or jsutils.inspected",skipped,,Dart tokens have no JS inspect/JSON protocol.
 lexer-test.ts,Lexer,skips whitespace and comments,ported,test/language/lexer_test.dart,
 lexer-test.ts,Lexer,reports unexpected characters,ported,test/language/lexer_test.dart,
-lexer-test.ts,Lexer,errors respect whitespace,adapted,test/language/lexer_test.dart,The printLocation source excerpt arrives in M2b: only message and location 3:2 are checked.
+lexer-test.ts,Lexer,errors respect whitespace,ported,test/language/lexer_test.dart,
 lexer-test.ts,Lexer,updates line numbers in error for file context,skipped,,Source has no locationOffset.
 lexer-test.ts,Lexer,updates column numbers in error for file context,skipped,,Source has no locationOffset.
 lexer-test.ts,Lexer,lexes strings,ported,test/language/lexer_strings_test.dart,
@@ -48,8 +48,8 @@ blockString-test.ts,printBlockString,correctly prints single-line with leading s
 blockString-test.ts,printBlockString,correctly prints single-line with trailing backslash,ported,test/language/block_string_test.dart,
 blockString-test.ts,printBlockString,correctly prints multi-line with internal indent,ported,test/language/block_string_test.dart,
 blockString-test.ts,printBlockString,correctly prints string with a first line indentation,ported,test/language/block_string_test.dart,
-parser-test.ts,Parser,parse provides useful errors,adapted,test/language/parser/parser_test.dart,"The printLocation excerpt of String(error) arrives in M2b: Dart checks message, position and location."
-parser-test.ts,Parser,parse provides useful error when using source,adapted,test/language/parser/parser_test.dart,"The printLocation excerpt arrives in M2b: Dart checks message, location and source name."
+parser-test.ts,Parser,parse provides useful errors,ported,test/language/parser/parser_test.dart,
+parser-test.ts,Parser,parse provides useful error when using source,ported,test/language/parser/parser_test.dart,
 parser-test.ts,Parser,limits by a maximum number of tokens,ported,test/language/parser/parser_test.dart,
 parser-test.ts,Parser,exposes the tokenCount,adapted,test/language/parser/parser_test.dart,The parser exposes no tokenCount: Lexer.tokenCount after reading the document is checked.
 parser-test.ts,Parser,parses variable inline values,ported,test/language/parser/parser_test.dart,
@@ -210,3 +210,8 @@ schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,can be stringified,skipped,,
 schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,tracks a schema coordinate,ported,test/language/schema_coordinate_lexer_test.dart,
 schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,forbids ignored tokens,ported,test/language/schema_coordinate_lexer_test.dart,
 schemaCoordinateLexer-test.ts,SchemaCoordinateLexer,lex reports a useful syntax errors,ported,test/language/schema_coordinate_lexer_test.dart,
+printLocation-test.ts,printSourceLocation,prints minified documents,ported,test/language/print_location_test.dart,
+printLocation-test.ts,printSourceLocation,prints single digit line number with no padding,adapted,test/language/print_location_test.dart,"Source has no locationOffset: eight line breaks put the error on line 9, so the excerpt also shows line 8."
+printLocation-test.ts,printSourceLocation,prints line numbers with correct padding,adapted,test/language/print_location_test.dart,"Source has no locationOffset: eight line breaks put the error on line 9, so the excerpt also shows line 8."
+source-test.ts,Source,can be Object.toStringified,skipped,,Symbol.toStringTag is JavaScript only.
+source-test.ts,Source,rejects invalid locationOffset,skipped,,Source has no locationOffset.
```

- [ ] **Step 10: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+204: All tests passed!`

- [ ] **Step 11: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -62,3 +62,5 @@
 - `Parser.parseSchemaCoordinate`: a schema coordinate such as
   `Query.hero(episode:)` as a `ParseElementResult<SchemaCoordinate>`.
 - `Printer` prints schema coordinates, the same in both forms.
+- `SourceExcerpt` and `SourceSpan.excerpt`: a location shown in its lines
+  with a caret, as graphql-js's `printLocation` prints it.
```

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,4 +9,4 @@
 - Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`,
   `parser-test.ts`, `schema-parser-test.ts`, `printer-test.ts`,
   `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`,
-  `schemaCoordinateLexer-test.ts`.
+  `schemaCoordinateLexer-test.ts`, `printLocation-test.ts`, `source-test.ts`.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -72,7 +72,8 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   1-based `SourceLocation` (column in UTF-16 code units). The table of line
   starts is built on the first call. `\r\n`, `\n` and `\r` end a line.
 - `SourceSpan(source, start, end)` is a range of offsets; a diagnostic points
-  at one.
+  at one. `SourceSpan.excerpt` (`SourceExcerpt`) shows its start in its
+  lines with a caret, as graphql-js's `printSourceLocation`.
 - `DiagnosticCode` is the catalog: one enum value per problem, id `GQLnxx`,
   a doc comment that says when it is reported. Ids are public API: never
   renumber, reuse or remove one. Ranges: `GQL0xx` syntax, `GQL1xx` type
```

- [ ] **Step 12: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 13: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/source_excerpt.dart packages/typed_graphql/lib/src/diagnostics/source_span.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/diagnostics/source_excerpt_test.dart packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/language.csv packages/typed_graphql_conformance/test/language/lexer_test.dart packages/typed_graphql_conformance/test/language/parser/parser_test.dart packages/typed_graphql_conformance/test/language/print_location_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/error_json.dart packages/typed_graphql_conformance/test/support/lexer_port.dart
git commit -q -m "feat(typed_graphql): show source excerpts as graphql-js printLocation"
```

### Task 10: Port the graphql-js predicates suite and map kind and diagnostics

The last three graphql-js files that need no new library code.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql_conformance/test/language/predicates_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/node_samples.dart`

**Interfaces:**
- Consumes: Task 1: `AstVisitor`, `AstWalker`; Task 7: `parseSchemaCoordinate`; M2a: `KitchenSink`, `AstJson`.
- Produces:
  - test helper `NodeSamples` with `const NodeSamples()`, `Map<String, Node> byKind()` (graphql-js kind to the first node of that kind, sorted) and `Set<String> kindsIn(Node root)`;
  - rows: 11 for `predicates-test.ts`, 2 for `kind-test.ts`, 3 for `diagnostics-test.ts`.

- [ ] **Step 1: Write the port helper**

`NodeSamples.byKind` collects the first node of each graphql-js kind from the kitchen sinks and a few extra texts, with an `AstVisitor`. Task 11 checks its generators against the same kinds.

Create `packages/typed_graphql_conformance/test/support/node_samples.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'ast_json.dart';
import 'kitchen_sink.dart';

/// One parsed node of each graphql-js `Kind`, taken from the kitchen
/// sinks, a few values and types they lack, and the five schema
/// coordinates: what graphql-js's `filterNodes` builds from `{ kind }`.
final class NodeSamples {
  /// Creates the samples' builder; it keeps no state.
  const NodeSamples();

  static const Parser _parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true),
  );

  /// The first node of each kind, by graphql-js kind name, in kind order.
  Map<String, Node> byKind() {
    final found = <String, Node>{};
    final collector = _FirstOfEachKind(found);
    const walker = AstWalker();
    for (final text in [KitchenSink.query, KitchenSink.sdl]) {
      walker.walk(_document(text), collector);
    }
    walker.walk(_element(_parser.parseValue(Source('1.5'))), collector);
    walker.walk(_element(_parser.parseTypeRef(Source('[T!]'))), collector);
    for (final text in ['T', 'T.f', 'T.f(a:)', '@d', '@d(a:)']) {
      final coordinate = _parser.parseSchemaCoordinate(Source(text));
      walker.walk(_element(coordinate), collector);
    }
    final entries = found.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return Map.fromEntries(entries);
  }

  Document _document(String text) => switch (_parser.parse(Source(text))) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  T _element<T extends Node>(ParseElementResult<T> result) => switch (result) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };
}

/// Records the first node of each kind it enters.
final class _FirstOfEachKind extends AstVisitor {
  _FirstOfEachKind(this.found);

  final Map<String, Node> found;

  @override
  VisitAction enter(Node node) {
    if (const AstJson().of(node) case {'kind': final String kind}) {
      found.putIfAbsent(kind, () => node);
    }
    return VisitAction.next;
  }
}
```

- [ ] **Step 2: Write the ported tests**

graphql-js calls each predicate on `{ kind }` for every `Kind`; here each sealed family is tested with `is` on one parsed node of every kind, so every row is `adapted`.

Create `packages/typed_graphql_conformance/test/language/predicates_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/predicates-test.ts; see
// mapping/language.csv.
//
// Adapted throughout: graphql-js's predicates are Dart's sealed families,
// so `filterNodes` tests one parsed node of each kind with `is`.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/node_samples.dart';

void main() {
  final samples = const NodeSamples().byKind();

  List<String> filterNodes(bool Function(Node node) predicate) => [
    for (final MapEntry(key: kind, value: node) in samples.entries)
      if (predicate(node)) kind,
  ];

  group('AST node predicates', () {
    test('has a sample of every kind but FragmentArgument', () {
      expect(samples, hasLength(49));
    });

    test('isDefinitionNode', () {
      expect(filterNodes((node) => node is Definition), [
        'DirectiveDefinition',
        'DirectiveExtension',
        'EnumTypeDefinition',
        'EnumTypeExtension',
        'FragmentDefinition',
        'InputObjectTypeDefinition',
        'InputObjectTypeExtension',
        'InterfaceTypeDefinition',
        'InterfaceTypeExtension',
        'ObjectTypeDefinition',
        'ObjectTypeExtension',
        'OperationDefinition',
        'ScalarTypeDefinition',
        'ScalarTypeExtension',
        'SchemaDefinition',
        'SchemaExtension',
        'UnionTypeDefinition',
        'UnionTypeExtension',
      ]);
    });

    test('isExecutableDefinitionNode', () {
      expect(filterNodes((node) => node is ExecutableDefinition), [
        'FragmentDefinition',
        'OperationDefinition',
      ]);
    });

    test('isSelectionNode', () {
      expect(filterNodes((node) => node is Selection), [
        'Field',
        'FragmentSpread',
        'InlineFragment',
      ]);
    });

    test('isValueNode', () {
      expect(filterNodes((node) => node is Value), [
        'BooleanValue',
        'EnumValue',
        'FloatValue',
        'IntValue',
        'ListValue',
        'NullValue',
        'ObjectValue',
        'StringValue',
        'Variable',
      ]);
    });

    // Adapted: there is no isConstValueNode; a const value is one that
    // parseValue accepts with isConst.
    test('isConstValueNode', () {
      bool isConst(String text) =>
          const Parser().parseValue(Source(text), isConst: true)
              is ParseElementSuccess<Value>;

      expect(isConst('"value"'), isTrue);
      expect(isConst(r'$var'), isFalse);

      expect(isConst('{ field: "value" }'), isTrue);
      expect(isConst(r'{ field: $var }'), isFalse);

      expect(isConst('[ "value" ]'), isTrue);
      expect(isConst(r'[ $var ]'), isFalse);
    });

    test('isTypeNode', () {
      expect(filterNodes((node) => node is TypeRef), [
        'ListType',
        'NamedType',
        'NonNullType',
      ]);
    });

    test('isTypeSystemDefinitionNode', () {
      expect(filterNodes((node) => node is TypeSystemDefinition), [
        'DirectiveDefinition',
        'EnumTypeDefinition',
        'InputObjectTypeDefinition',
        'InterfaceTypeDefinition',
        'ObjectTypeDefinition',
        'ScalarTypeDefinition',
        'SchemaDefinition',
        'UnionTypeDefinition',
      ]);
    });

    test('isTypeDefinitionNode', () {
      expect(filterNodes((node) => node is TypeDefinition), [
        'EnumTypeDefinition',
        'InputObjectTypeDefinition',
        'InterfaceTypeDefinition',
        'ObjectTypeDefinition',
        'ScalarTypeDefinition',
        'UnionTypeDefinition',
      ]);
    });

    test('isTypeSystemExtensionNode', () {
      expect(filterNodes((node) => node is TypeSystemExtension), [
        'DirectiveExtension',
        'EnumTypeExtension',
        'InputObjectTypeExtension',
        'InterfaceTypeExtension',
        'ObjectTypeExtension',
        'ScalarTypeExtension',
        'SchemaExtension',
        'UnionTypeExtension',
      ]);
    });

    test('isTypeExtensionNode', () {
      expect(filterNodes((node) => node is TypeExtension), [
        'EnumTypeExtension',
        'InputObjectTypeExtension',
        'InterfaceTypeExtension',
        'ObjectTypeExtension',
        'ScalarTypeExtension',
        'UnionTypeExtension',
      ]);
    });

    test('isSchemaCoordinateNode', () {
      expect(filterNodes((node) => node is SchemaCoordinate), [
        'ArgumentCoordinate',
        'DirectiveArgumentCoordinate',
        'DirectiveCoordinate',
        'MemberCoordinate',
        'TypeCoordinate',
      ]);
    });
  });
}
```

- [ ] **Step 3: Run the ported tests**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/predicates_test.dart)
```

Expected: `+12: All tests passed!`

- [ ] **Step 4: Mark the files as ported and see the coverage check fail**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -22,6 +22,9 @@ const Set<String> portedFiles = {
   'schemaCoordinateLexer-test.ts',
   'printLocation-test.ts',
   'source-test.ts',
+  'predicates-test.ts',
+  'kind-test.ts',
+  'diagnostics-test.ts',
 };
 
 void main() {
```

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of predicates-test.ts`, `rows cover every test of kind-test.ts`, `rows cover every test of diagnostics-test.ts`: `Actual: Set:[]`, followed by the missing `(group, test)` pairs. This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 5: Write the rows**

`kind-test.ts` is a TypeScript typing test and `diagnostics-test.ts` tests Node.js's `diagnostics_channel`: both are skipped.

In `packages/typed_graphql_conformance/mapping/language.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -215,3 +215,19 @@ printLocation-test.ts,printSourceLocation,prints single digit line number with n
 printLocation-test.ts,printSourceLocation,prints line numbers with correct padding,adapted,test/language/print_location_test.dart,"Source has no locationOffset: eight line breaks put the error on line 9, so the excerpt also shows line 8."
 source-test.ts,Source,can be Object.toStringified,skipped,,Symbol.toStringTag is JavaScript only.
 source-test.ts,Source,rejects invalid locationOffset,skipped,,Source has no locationOffset.
+predicates-test.ts,AST node predicates,isDefinitionNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isExecutableDefinitionNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isSelectionNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isValueNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isConstValueNode,adapted,test/language/predicates_test.dart,There is no isConstValueNode: a const value is one parseValue accepts with isConst.
+predicates-test.ts,AST node predicates,isTypeNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isTypeSystemDefinitionNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isTypeDefinitionNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isTypeSystemExtensionNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isTypeExtensionNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+predicates-test.ts,AST node predicates,isSchemaCoordinateNode,adapted,test/language/predicates_test.dart,Dart tests the sealed families with `is` on one parsed node of each kind; graphql-js calls a predicate on `{ kind }`.
+kind-test.ts,Kind,is a term level namespace with term level enum members,skipped,,A TypeScript typing test: Dart has no Kind namespace; node classes are the kinds.
+kind-test.ts,Kind,is a type level namespace with type level enum members,skipped,,A TypeScript typing test: Dart has no Kind namespace; node classes are the kinds.
+diagnostics-test.ts,parse diagnostics channel,emits start and end around a successful parse,skipped,,Node.js diagnostics_channel tracing has no Dart counterpart.
+diagnostics-test.ts,parse diagnostics channel,"emits start, error, and end when the parser throws",skipped,,Node.js diagnostics_channel tracing has no Dart counterpart.
+diagnostics-test.ts,parse diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,Node.js diagnostics_channel tracing has no Dart counterpart.
```

- [ ] **Step 6: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+219: All tests passed!`

- [ ] **Step 7: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,4 +9,5 @@
 - Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`,
   `parser-test.ts`, `schema-parser-test.ts`, `printer-test.ts`,
   `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`,
-  `schemaCoordinateLexer-test.ts`, `printLocation-test.ts`, `source-test.ts`.
+  `schemaCoordinateLexer-test.ts`, `printLocation-test.ts`, `source-test.ts`,
+  `predicates-test.ts`, `kind-test.ts`, `diagnostics-test.ts`.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/language.csv packages/typed_graphql_conformance/test/language/predicates_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/node_samples.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js predicates suite and map kind and diagnostics"
```

### Task 11: Fuzz the print and parse round trip

R10.4 and spec §8, property 1.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/README.md`
- Test: `packages/typed_graphql_conformance/test/fuzz/fuzz_budget.dart`, `packages/typed_graphql_conformance/test/fuzz/random_executable.dart`, `packages/typed_graphql_conformance/test/fuzz/random_parts.dart`, `packages/typed_graphql_conformance/test/fuzz/random_type_system.dart`, `packages/typed_graphql_conformance/test/fuzz/round_trip_fuzz_test.dart`, `packages/typed_graphql_conformance/test/support/node_samples.dart`

**Interfaces:**
- Consumes: M2a: every AST class, `Parser`, `Printer`, `BlockString().isPrintable`; Task 5: the coordinate nodes; Task 10: `NodeSamples`.
- Produces:
  - `FuzzBudget({required int defaultIterations})` with `iterations`, `seed`, `static const int defaultSeed = 20261014`, `Random randomFor(int index)` and `String replay(int index)`; environment `TYPED_GRAPHQL_FUZZ_ITERATIONS`, `TYPED_GRAPHQL_FUZZ_SEED`;
  - `RandomParts(Random random)`: `chance`, `pick`, `some`, `name`, `fragmentName`, `enumValueName`, `value({required bool isConst})`, `string`, `type`, `directives({required bool isConst})`, `arguments({required bool isConst})`;
  - `RandomExecutable(RandomParts parts)`: `operation({required bool isFirst})`, `fragment()`, `selectionSet()`;
  - `RandomTypeSystem(RandomParts parts)`: `definition()`, `extension()`;
  - `NodeSamples.kindsIn(Node root)`.

- [ ] **Step 1: Write the fuzz budget**

R10.4: a fixed count and seed in CI, more on demand. Iteration `i` draws from `Random(seed + i)`, so a failure names the one case to replay.

Create `packages/typed_graphql_conformance/test/fuzz/fuzz_budget.dart`:

```dart
import 'dart:io';
import 'dart:math';

/// How much a fuzzer runs (R10.4): a fixed count in CI, more on demand.
///
/// `TYPED_GRAPHQL_FUZZ_ITERATIONS` raises [iterations] and
/// `TYPED_GRAPHQL_FUZZ_SEED` changes [seed]. Iteration `i` draws from
/// `Random(seed + i)`, so a failure names the one iteration to replay.
final class FuzzBudget {
  /// A budget of [defaultIterations] unless the environment says more.
  FuzzBudget({required int defaultIterations})
    : iterations = _read('TYPED_GRAPHQL_FUZZ_ITERATIONS') ?? defaultIterations,
      seed = _read('TYPED_GRAPHQL_FUZZ_SEED') ?? defaultSeed;

  /// The seed CI uses.
  static const int defaultSeed = 20261014;

  /// How many cases to run.
  final int iterations;

  /// The seed of the first case.
  final int seed;

  /// The random source of case [index].
  Random randomFor(int index) => Random(seed + index);

  /// How to replay case [index], for a failure message.
  String replay(int index) =>
      'case $index of seed $seed: Random(${seed + index})';

  static int? _read(String name) => switch (Platform.environment[name]) {
    final text? => int.tryParse(text),
    null => null,
  };
}
```

- [ ] **Step 2: Write the generators**

The generators only build trees that graphql-js itself would print and read back the same way. Each rule below was found by a failing case while the plan was verified:
- a block string only where `BlockString().isPrintable` holds (graphql-js prints the others quoted, so the flag would not survive);
- no lone surrogates in strings: they cannot be written as GraphQL source;
- only the first definition may be a shorthand query: after a body-less type extension (`extend enum E @d`), a `{` opens that extension's body, in graphql-js too;
- a fragment is never named `on`, an enum value never `true`, `false` or `null`;
- descriptions only on named operations; every extension has at least one part.

Create `packages/typed_graphql_conformance/test/fuzz/random_parts.dart`:

```dart
import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

/// Random names, values, types and directives for the round-trip fuzzer:
/// only what a parser reads back as an equivalent tree.
final class RandomParts {
  /// Draws from [random].
  RandomParts(this.random);

  /// The random source.
  final Random random;

  static const String _nameStart =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_';
  static const String _nameContinue = '${_nameStart}0123456789';

  /// Words the grammar gives a meaning somewhere, which stay plain names
  /// everywhere else.
  static const List<String> _keywords = [
    'on',
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
    'implements',
    'repeatable',
    'true',
    'false',
    'null',
  ];

  /// What strings are made of: quotes, backslashes, line terminators,
  /// control characters and a supplementary character, but no lone
  /// surrogate, which no printed string can hold.
  static const List<String> _stringParts = [
    'a',
    'Z',
    ' ',
    '  ',
    '"',
    '"""',
    r'\',
    '\n',
    '\r\n',
    '\t',
    '\u0001',
    '\u007f',
    'é',
    '\u{1F600}',
  ];

  /// Whether a [percent] chance comes true.
  bool chance(int percent) => random.nextInt(100) < percent;

  /// One of [items].
  T pick<T>(List<T> items) => items[random.nextInt(items.length)];

  /// From [min] to [max] items made by [make].
  List<T> some<T>(int max, T Function() make, {int min = 0}) =>
      List.generate(min + random.nextInt(max - min + 1), (_) => make());

  /// A name; often a keyword, which the grammar must keep a name.
  Name name() {
    if (chance(25)) {
      return Name(pick(_keywords));
    }
    final buffer = StringBuffer(_nameStart[random.nextInt(_nameStart.length)]);
    for (var i = random.nextInt(6); i > 0; i--) {
      buffer.write(_nameContinue[random.nextInt(_nameContinue.length)]);
    }
    return Name(buffer.toString());
  }

  /// A name that is not `on`, which a fragment cannot have (spec §2.8).
  Name fragmentName() => _avoiding(const {'on'});

  /// A name that is not `true`, `false` or `null`: an enum value
  /// (spec §2.9.6).
  Name enumValueName() => _avoiding(const {'true', 'false', 'null'});

  Name _avoiding(Set<String> words) {
    final candidate = name();
    return words.contains(candidate.value)
        ? Name('${candidate.value}_')
        : candidate;
  }

  /// A value; a variable only when not [isConst]. Lists and objects nest
  /// at most three levels.
  Value value({required bool isConst, int depth = 0}) {
    Value nested() => value(isConst: isConst, depth: depth + 1);
    return switch (random.nextInt(depth < 3 ? 10 : 8)) {
      0 when !isConst => Variable(name()),
      0 || 1 => IntValue(_integer()),
      2 => FloatValue(_float()),
      3 => string(),
      4 => BooleanValue(random.nextBool()),
      5 => const NullValue(),
      6 || 7 => EnumValue(enumValueName().value),
      8 => ListValue(some(3, nested)),
      _ => ObjectValue(some(3, () => ObjectField(name(), nested()))),
    };
  }

  /// A quoted or block string; a block string only when its value can be
  /// printed as one, as graphql-js's `isPrintableAsBlockString` decides.
  StringValue string() {
    final text = some(6, () => pick(_stringParts)).join();
    final isBlock = chance(40) && const BlockString().isPrintable(text);
    return StringValue(text, isBlock: isBlock);
  }

  /// A description, or none.
  StringValue? description() => chance(30) ? string() : null;

  /// A named, list or non-null type, lists nested at most twice.
  TypeRef type({int depth = 0}) {
    final TypeRef inner = depth < 2 && chance(30)
        ? ListType(type(depth: depth + 1))
        : NamedType(name());
    return chance(40) ? NonNullType(inner) : inner;
  }

  /// Up to two directives with arguments.
  List<Directive> directives({required bool isConst}) => some(
    2,
    () => Directive(name(), arguments: arguments(isConst: isConst)),
  );

  /// Up to three arguments.
  List<Argument> arguments({required bool isConst}) =>
      some(3, () => Argument(name(), value(isConst: isConst)));

  String _integer() {
    final sign = chance(20) ? '-' : '';
    if (chance(20)) {
      return '${sign}0';
    }
    final digits = some(5, () => random.nextInt(10)).join();
    return '$sign${1 + random.nextInt(9)}$digits';
  }

  String _float() {
    final hasFraction = chance(70);
    final hasExponent = !hasFraction || chance(30);
    final fraction = hasFraction
        ? '.${some(3, () => random.nextInt(10), min: 1).join()}'
        : '';
    final exponent = hasExponent
        ? '${pick(['e', 'E'])}${pick(['', '+', '-'])}${random.nextInt(40)}'
        : '';
    return '${_integer()}$fraction$exponent';
  }
}
```

Create `packages/typed_graphql_conformance/test/fuzz/random_executable.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'random_parts.dart';

/// Random operations and fragments for the round-trip fuzzer.
final class RandomExecutable {
  /// Draws from [parts].
  RandomExecutable(this.parts);

  /// The shared random parts.
  final RandomParts parts;

  /// An operation. Only the first definition may take the shorthand
  /// form `{ ... }`: after a definition with an optional body, such as
  /// `type T`, the `{` would read as that body. Only a named operation has
  /// a description, since graphql-js rejects one on an anonymous
  /// operation.
  OperationDefinition operation({required bool isFirst}) {
    final type = parts.pick(OperationType.values);
    final variables = parts.some(2, _variableDefinition);
    final directives = parts.directives(isConst: false);
    final isShorthand =
        type == OperationType.query && variables.isEmpty && directives.isEmpty;
    final isNamed = parts.chance(70) || (isShorthand && !isFirst);
    final name = isNamed ? parts.name() : null;
    return OperationDefinition(
      type,
      selectionSet(),
      description: isNamed ? parts.description() : null,
      name: name,
      variableDefinitions: variables,
      directives: directives,
    );
  }

  /// A fragment definition.
  FragmentDefinition fragment() => FragmentDefinition(
    parts.fragmentName(),
    NamedType(parts.name()),
    selectionSet(),
    description: parts.description(),
    directives: parts.directives(isConst: false),
  );

  /// One to three selections, nested at most three levels.
  SelectionSet selectionSet({int depth = 0}) =>
      SelectionSet(parts.some(3, () => _selection(depth), min: 1));

  Selection _selection(int depth) => switch (parts.random.nextInt(5)) {
    0 => FragmentSpread(
      parts.fragmentName(),
      directives: parts.directives(isConst: false),
    ),
    1 => InlineFragment(
      parts.chance(70) ? NamedType(parts.name()) : null,
      selectionSet(depth: depth + 1),
      directives: parts.directives(isConst: false),
    ),
    _ => _field(depth),
  };

  Field _field(int depth) => Field(
    parts.chance(20) ? parts.name() : null,
    parts.name(),
    arguments: parts.arguments(isConst: false),
    directives: parts.directives(isConst: false),
    selectionSet: depth < 3 && parts.chance(40)
        ? selectionSet(depth: depth + 1)
        : null,
  );

  VariableDefinition _variableDefinition() => VariableDefinition(
    Variable(parts.name()),
    parts.type(),
    description: parts.description(),
    defaultValue: parts.chance(30) ? parts.value(isConst: true) : null,
    directives: parts.directives(isConst: true),
  );
}
```

Create `packages/typed_graphql_conformance/test/fuzz/random_type_system.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'random_parts.dart';

/// Random type-system definitions and extensions for the round-trip
/// fuzzer, the working draft's directive extensions included.
final class RandomTypeSystem {
  /// Draws from [parts].
  RandomTypeSystem(this.parts);

  /// The shared random parts.
  final RandomParts parts;

  static const List<String> _locations = [
    'QUERY',
    'FIELD',
    'FRAGMENT_SPREAD',
    'VARIABLE_DEFINITION',
    'SCHEMA',
    'OBJECT',
    'ARGUMENT_DEFINITION',
    'ENUM_VALUE',
    'INPUT_FIELD_DEFINITION',
    'DIRECTIVE_DEFINITION',
  ];

  /// A definition of any kind.
  TypeSystemDefinition definition() {
    final name = parts.name();
    final description = parts.description();
    final directives = parts.directives(isConst: true);
    return switch (parts.random.nextInt(8)) {
      0 => SchemaDefinition(
        description: description,
        directives: directives,
        operationTypes: _operationTypes(min: 1),
      ),
      1 => ScalarTypeDefinition(
        name,
        description: description,
        directives: directives,
      ),
      2 => ObjectTypeDefinition(
        name,
        description: description,
        interfaces: _namedTypes(),
        directives: directives,
        fields: parts.some(3, _field),
      ),
      3 => InterfaceTypeDefinition(
        name,
        description: description,
        interfaces: _namedTypes(),
        directives: directives,
        fields: parts.some(3, _field),
      ),
      4 => UnionTypeDefinition(
        name,
        description: description,
        directives: directives,
        types: _namedTypes(),
      ),
      5 => EnumTypeDefinition(
        name,
        description: description,
        directives: directives,
        values: parts.some(3, _enumValue),
      ),
      6 => InputObjectTypeDefinition(
        name,
        description: description,
        directives: directives,
        fields: parts.some(3, _inputValue),
      ),
      _ => DirectiveDefinition(
        name,
        description: description,
        arguments: parts.some(2, _inputValue),
        directives: directives,
        isRepeatable: parts.random.nextBool(),
        locations: parts.some(3, () => Name(parts.pick(_locations)), min: 1),
      ),
    };
  }

  /// An extension of any kind; each has at least one part, as the
  /// grammar requires.
  TypeSystemExtension extension() {
    final name = parts.name();
    final directives = parts.directives(isConst: true);
    final minimum = directives.isEmpty ? 1 : 0;
    return switch (parts.random.nextInt(8)) {
      0 => SchemaExtension(
        directives: directives,
        operationTypes: _operationTypes(min: minimum),
      ),
      1 => ScalarTypeExtension(name, directives: _atLeastOne(directives)),
      2 => ObjectTypeExtension(
        name,
        directives: directives,
        fields: parts.some(3, _field, min: minimum),
      ),
      3 => InterfaceTypeExtension(
        name,
        interfaces: _namedTypes(min: minimum),
        directives: directives,
      ),
      4 => UnionTypeExtension(
        name,
        directives: directives,
        types: _namedTypes(min: minimum),
      ),
      5 => EnumTypeExtension(
        name,
        directives: directives,
        values: parts.some(3, _enumValue, min: minimum),
      ),
      6 => InputObjectTypeExtension(
        name,
        directives: directives,
        fields: parts.some(3, _inputValue, min: minimum),
      ),
      _ => DirectiveExtension(name, directives: _atLeastOne(directives)),
    };
  }

  List<Directive> _atLeastOne(List<Directive> directives) =>
      directives.isEmpty ? [Directive(parts.name())] : directives;

  List<OperationTypeDefinition> _operationTypes({required int min}) =>
      parts.some(
        3,
        () => OperationTypeDefinition(
          parts.pick(OperationType.values),
          NamedType(parts.name()),
        ),
        min: min,
      );

  List<NamedType> _namedTypes({int min = 0}) =>
      parts.some(3, () => NamedType(parts.name()), min: min);

  FieldDefinition _field() => FieldDefinition(
    parts.name(),
    parts.type(),
    description: parts.description(),
    arguments: parts.some(2, _inputValue),
    directives: parts.directives(isConst: true),
  );

  InputValueDefinition _inputValue() => InputValueDefinition(
    parts.name(),
    parts.type(),
    description: parts.description(),
    defaultValue: parts.chance(30) ? parts.value(isConst: true) : null,
    directives: parts.directives(isConst: true),
  );

  EnumValueDefinition _enumValue() => EnumValueDefinition(
    parts.enumValueName(),
    description: parts.description(),
    directives: parts.directives(isConst: true),
  );
}
```

In `packages/typed_graphql_conformance/test/support/node_samples.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -34,6 +34,13 @@ final class NodeSamples {
     return Map.fromEntries(entries);
   }
 
+  /// The kind names of [root] and every node under it.
+  Set<String> kindsIn(Node root) {
+    final found = <String, Node>{};
+    const AstWalker().walk(root, _FirstOfEachKind(found));
+    return found.keys.toSet();
+  }
+
   Document _document(String text) => switch (_parser.parse(Source(text))) {
     ParseSuccess(:final document) => document,
     ParseFailure(:final diagnostics) => fail('$diagnostics'),
```

- [ ] **Step 3: Write the properties**

Spec §8, property 1, plus a check that the generators reach every kind `NodeSamples` knows, so a generator that stops producing a node fails loudly.

Create `packages/typed_graphql_conformance/test/fuzz/round_trip_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/node_samples.dart';
import 'fuzz_budget.dart';
import 'random_executable.dart';
import 'random_parts.dart';
import 'random_type_system.dart';

/// R10.4, property 1: a random valid tree, printed and parsed again, is
/// equivalent to itself, in the canonical and in the minified form.
void main() {
  final budget = FuzzBudget(defaultIterations: 1000);
  const parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true, maxTokens: null),
  );

  Document randomDocument(RandomParts parts) {
    final executable = RandomExecutable(parts);
    final typeSystem = RandomTypeSystem(parts);
    Definition definition(int index) => switch (parts.random.nextInt(4)) {
      0 => executable.operation(isFirst: index == 0),
      1 => executable.fragment(),
      2 => typeSystem.definition(),
      _ => typeSystem.extension(),
    };
    return Document(
      List.generate(1 + parts.random.nextInt(4), definition),
    );
  }

  SchemaCoordinate randomCoordinate(RandomParts parts) =>
      switch (parts.random.nextInt(5)) {
        0 => TypeCoordinate(parts.name()),
        1 => MemberCoordinate(parts.name(), parts.name()),
        2 => ArgumentCoordinate(parts.name(), parts.name(), parts.name()),
        3 => DirectiveCoordinate(parts.name()),
        _ => DirectiveArgumentCoordinate(parts.name(), parts.name()),
      };

  void expectRoundTrip(Document document, Printer printer, int index) {
    final text = printer.print(document);
    final reason = '${budget.replay(index)}\n$text';
    switch (parser.parse(Source(text))) {
      case ParseSuccess(document: final parsed):
        expect(parsed.isEquivalentTo(document), isTrue, reason: reason);
      case ParseFailure(:final diagnostics):
        fail('$reason\n$diagnostics');
    }
  }

  test('print then parse gives an equivalent tree, canonical and minified', () {
    for (var index = 0; index < budget.iterations; index++) {
      final document = randomDocument(RandomParts(budget.randomFor(index)));
      expectRoundTrip(document, const Printer(), index);
      expectRoundTrip(document, const Printer(isMinified: true), index);
    }
  });

  test('print then parse gives an equivalent schema coordinate', () {
    for (var index = 0; index < budget.iterations; index++) {
      final coordinate = randomCoordinate(
        RandomParts(budget.randomFor(index)),
      );
      final text = const Printer().print(coordinate);
      final reason = '${budget.replay(index)}\n$text';
      switch (parser.parseSchemaCoordinate(Source(text))) {
        case ParseElementSuccess(value: final parsed):
          expect(parsed.isEquivalentTo(coordinate), isTrue, reason: reason);
        case ParseElementFailure(:final diagnostics):
          fail('$reason\n$diagnostics');
      }
    }
  });

  test('the generators build every kind of node', () {
    final kinds = <String>{};
    for (var index = 0; index < 200; index++) {
      final parts = RandomParts(budget.randomFor(index));
      kinds
        ..addAll(const NodeSamples().kindsIn(randomDocument(parts)))
        ..addAll(const NodeSamples().kindsIn(randomCoordinate(parts)));
    }
    expect(kinds, const NodeSamples().byKind().keys.toSet());
  });
}
```

- [ ] **Step 4: Run the fuzzers**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/fuzz/round_trip_fuzz_test.dart)
```

Expected: `+3: All tests passed!` at once: the fuzzers test M2a's parser and printer and Tasks 5–7. A failure is a library bug or a generator that broke one of the rules above: report it with the replay line, never weaken the property.

While the plan was verified, the property also held for 20 000 iterations at the default seed and for 150 000 at seed 7:

```sh
(cd packages/typed_graphql_conformance && TYPED_GRAPHQL_FUZZ_ITERATIONS=20000 dart test test/fuzz/round_trip_fuzz_test.dart)
```

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,3 +11,6 @@
   `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`,
   `schemaCoordinateLexer-test.ts`, `printLocation-test.ts`, `source-test.ts`,
   `predicates-test.ts`, `kind-test.ts`, `diagnostics-test.ts`.
+- Round-trip fuzzer (R10.4): random documents and schema coordinates,
+  printed canonical and minified, parse back to equivalent trees;
+  `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` tune it.
```

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -29,6 +29,20 @@ per graphql-js test, with the same group and test names.
 `test/mapping_test.dart` checks the table; with `reference/` fetched it also
 checks that every test of a ported file has a row.
 
+## Fuzzing
+
+`test/fuzz/` holds the fuzzers of R10.4. They run with the other tests, a
+fixed number of cases from a fixed seed; set the environment to run more or
+other cases:
+
+```sh
+TYPED_GRAPHQL_FUZZ_ITERATIONS=100000 TYPED_GRAPHQL_FUZZ_SEED=7 dart test test/fuzz
+```
+
+A failure names its case and the `Random` seed that replays it.
+`round_trip_fuzz_test.dart` prints random documents and coordinates and
+parses them back.
+
 ## License
 
 MIT — see [LICENSE](LICENSE). The ported tests derive from graphql-js,
````

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/test/fuzz/fuzz_budget.dart packages/typed_graphql_conformance/test/fuzz/random_executable.dart packages/typed_graphql_conformance/test/fuzz/random_parts.dart packages/typed_graphql_conformance/test/fuzz/random_type_system.dart packages/typed_graphql_conformance/test/fuzz/round_trip_fuzz_test.dart packages/typed_graphql_conformance/test/support/node_samples.dart
git commit -q -m "test(typed_graphql_conformance): fuzz the print and parse round trip"
```

### Task 12: Fuzz hostile text and map every graphql-js language file

R10.4 and spec §8, property 2, and the last mapping row.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/README.md`, `packages/typed_graphql_conformance/mapping/language.csv`
- Test: `packages/typed_graphql_conformance/test/fuzz/hostile_text_fuzz_test.dart`, `packages/typed_graphql_conformance/test/language/block_string_fuzz_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`

**Interfaces:**
- Consumes: Task 11: `FuzzBudget`; Task 9: `SourceSpan.excerpt`; Task 7: `parseSchemaCoordinate`; M2a: `KitchenSink`, `BlockString`, `GraphqlJsSuite`, `DiagnosticSink.defaultMaxErrors`.
- Produces:
  - `static List<String> GraphqlJsSuite.files`: the sorted `.ts` names in the graphql-js language tests, empty without `reference/`;
  - `mapping_test.dart` without `portedFiles`; it checks every file;
  - 1 row for `blockString-fuzz.ts`.

- [ ] **Step 1: Write the hostile-text fuzzer and port blockString-fuzz.ts**

Spec §8, property 2: random text built from GraphQL pieces and mutated kitchen sinks go through all five entry points (`parse`, `parseValue` with and without `isConst`, `parseTypeRef`, `parseSchemaCoordinate`). None may throw, each reports at most `maxErrors + 1` diagnostics (the sink's own `GQL000` is the one more), and every diagnostic has an excerpt. graphql-js's `blockString-fuzz.ts` is an exhaustive enumeration, not a random fuzzer: it is ported as an ordinary test (about 336 000 strings, one second).

Create `packages/typed_graphql_conformance/test/language/block_string_fuzz_test.dart`:

```dart
// Ported from graphql-js src/language/__tests__/blockString-fuzz.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const blockString = BlockString();

  /// graphql-js's `genFuzzStrings`: the empty string, then every string of
  /// [allowedChars] up to [maxLength] characters.
  Iterable<String> genFuzzStrings(
    List<String> allowedChars,
    int maxLength,
  ) sync* {
    final count = allowedChars.length;
    var combinations = 0;
    var power = 1;
    for (var length = 1; length <= maxLength; length++) {
      power *= count;
      combinations += power;
    }
    yield ''; // special case for empty string
    for (var combination = 0; combination < combinations; combination++) {
      var permutation = '';
      for (
        var leftOver = combination;
        leftOver >= 0;
        leftOver = leftOver ~/ count - 1
      ) {
        permutation = allowedChars[leftOver % count] + permutation;
      }
      yield permutation;
    }
  }

  String lexValue(String text) {
    final lexer = Lexer(Source(text), DiagnosticSink());
    final value = lexer.advance().value;
    if (value == null || lexer.advance().kind != TokenKind.eof) {
      fail('Expected one string token in ${text.codeUnits}');
    }
    return value;
  }

  group('printBlockString', () {
    test('correctly print random strings', () {
      for (final fuzzStr in genFuzzStrings(const [
        '\n',
        '\t',
        ' ',
        '"',
        'a',
        r'\',
      ], 7)) {
        if (!blockString.isPrintable(fuzzStr)) {
          final printed = lexValue(blockString.print(fuzzStr));
          if (printed == fuzzStr) {
            fail('Expected the value of ${fuzzStr.codeUnits} to change');
          }
          continue;
        }
        for (final isMinified in const [false, true]) {
          final printed = blockString.print(fuzzStr, isMinified: isMinified);
          if (lexValue(printed) != fuzzStr) {
            fail(
              'Expected ${printed.codeUnits} to lex as ${fuzzStr.codeUnits}',
            );
          }
        }
      }
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/fuzz/hostile_text_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/kitchen_sink.dart';
import 'fuzz_budget.dart';

/// R10.4, property 2: arbitrary and mutated text never throws, ends, and
/// gives at most `maxErrors + 1` diagnostics, each at a place an excerpt
/// can show, from every parser entry point.
void main() {
  final budget = FuzzBudget(defaultIterations: 1000);
  const parser = Parser();

  /// Pieces of text the lexer and the parser treat specially, and some
  /// they reject: a lone surrogate, NUL, a single quote.
  const pieces = [
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '!',
    r'$',
    '&',
    '|',
    '@',
    ':',
    '=',
    '.',
    '...',
    '"',
    '"""',
    r'\',
    r'\u',
    '#',
    '\n',
    '\r',
    '\r\n',
    ' ',
    '\t',
    ',',
    'a',
    'on',
    'query',
    'fragment',
    'type',
    'extend',
    'directive',
    '1',
    '-',
    '1.5e',
    '0x',
    '\uD800',
    '\u{1F600}',
    '\u0000',
    "'",
    '﻿',
  ];

  String randomText(Random random) => List.generate(
    random.nextInt(80),
    (_) => pieces[random.nextInt(pieces.length)],
  ).join();

  /// A kitchen sink with one to five cuts, copies and insertions.
  String mutated(Random random) {
    var text = random.nextBool() ? KitchenSink.query : KitchenSink.sdl;
    for (var step = random.nextInt(5); step >= 0; step--) {
      final start = random.nextInt(text.length);
      final end = min(text.length, start + random.nextInt(40));
      text = switch (random.nextInt(3)) {
        0 => text.replaceRange(start, end, ''),
        1 => text.replaceRange(start, start, text.substring(start, end)),
        _ => text.replaceRange(
          start,
          start,
          pieces[random.nextInt(pieces.length)],
        ),
      };
    }
    return text;
  }

  void expectWellBehaved(String text, String reason) {
    final source = Source(text);
    final runs = [
      () => parser.parse(source).diagnostics,
      () => parser.parseValue(source).diagnostics,
      () => parser.parseValue(source, isConst: true).diagnostics,
      () => parser.parseTypeRef(source).diagnostics,
      () => parser.parseSchemaCoordinate(source).diagnostics,
    ];
    for (final run in runs) {
      final diagnostics = run();
      expect(
        diagnostics.length,
        lessThanOrEqualTo(DiagnosticSink.defaultMaxErrors + 1),
        reason: reason,
      );
      for (final diagnostic in diagnostics) {
        expect(diagnostic.span?.excerpt, isNotNull, reason: reason);
      }
    }
  }

  test('random text never throws and reports a bounded list', () {
    for (var index = 0; index < budget.iterations; index++) {
      final text = randomText(budget.randomFor(index));
      expectWellBehaved(text, '${budget.replay(index)}: ${text.codeUnits}');
    }
  });

  test('mutated documents never throw and report a bounded list', () {
    for (var index = 0; index < budget.iterations; index++) {
      final text = mutated(budget.randomFor(index));
      expectWellBehaved(text, '${budget.replay(index)}: ${text.codeUnits}');
    }
  });

  test('a long hostile text stays within the sink limit', () {
    final random = budget.randomFor(0);
    final text = List.generate(
      5000,
      (_) => pieces[random.nextInt(pieces.length)],
    ).join();
    expectWellBehaved(text, 'long text of ${budget.replay(0)}');
  });
}
```

- [ ] **Step 2: Run them**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/language/block_string_fuzz_test.dart test/fuzz/hostile_text_fuzz_test.dart)
```

Expected: `block_string_fuzz_test.dart` `+1`, `hostile_text_fuzz_test.dart` `+3`, each `All tests passed!` at once, since they test finished code. While the plan was verified, the hostile-text fuzzer also held for 100 000 iterations.

- [ ] **Step 3: Check every graphql-js file, not a list**

Spec §8 asks the check to fail "when a graphql-js file in the language directory has no rows". M2a checked the files in `portedFiles`; every file has rows now, so the list goes and the check reads the directory.

In `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,6 +40,19 @@ final class GraphqlJsSuite {
   /// Whether graphql-js was fetched into `reference/`.
   static bool get isAvailable => Directory(directory).existsSync();
 
+  /// The names of the test files in [directory], sorted; empty when
+  /// graphql-js was not fetched.
+  static List<String> get files {
+    if (!isAvailable) {
+      return const [];
+    }
+    return [
+      for (final entity in Directory(directory).listSync())
+        if (entity is File && entity.path.endsWith('.ts'))
+          entity.uri.pathSegments.last,
+    ]..sort();
+  }
+
   static final RegExp _block = RegExp(r"^(\s*)(describe|it)\('([^']*)'");
 
   /// Each test as its group path and its name, in file order.
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,25 +8,6 @@ import 'package:test/test.dart';
 import 'support/csv_table.dart';
 import 'support/graphql_js_suite.dart';
 
-/// The graphql-js language test files whose every test has a row (R10.3).
-/// A port task adds its file here with its rows.
-const Set<String> portedFiles = {
-  'lexer-test.ts',
-  'blockString-test.ts',
-  'parser-test.ts',
-  'schema-parser-test.ts',
-  'printer-test.ts',
-  'schema-printer-test.ts',
-  'printString-test.ts',
-  'visitor-test.ts',
-  'schemaCoordinateLexer-test.ts',
-  'printLocation-test.ts',
-  'source-test.ts',
-  'predicates-test.ts',
-  'kind-test.ts',
-  'diagnostics-test.ts',
-};
-
 void main() {
   final table = CsvTable.parse(
     File('mapping/language.csv').readAsStringSync(),
@@ -79,9 +60,16 @@ void main() {
     }
   });
 
+  test('names only graphql-js files that exist', () {
+    final names = {for (final row in table.rows) row['graphql_js_file']};
+    expect(GraphqlJsSuite.files, containsAll(names));
+  }, skip: !GraphqlJsSuite.isAvailable);
+
+  // Spec §8: every file of the graphql-js language tests has a row for
+  // each of its tests, so a new upstream file or test fails here.
   group('rows cover every test of', () {
-    for (final file in portedFiles) {
-      test(file, skip: !GraphqlJsSuite.isAvailable, () {
+    for (final file in GraphqlJsSuite.files) {
+      test(file, () {
         final mapped = {
           for (final row in table.rows)
             if (row['graphql_js_file'] == file) (row['group'], row['test']),
```

- [ ] **Step 4: Run the table check and see it fail**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of blockString-fuzz.ts`: `Actual: Set:[]`.

- [ ] **Step 5: Write the row**

In `packages/typed_graphql_conformance/mapping/language.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -231,3 +231,4 @@ kind-test.ts,Kind,is a type level namespace with type level enum members,skipped
 diagnostics-test.ts,parse diagnostics channel,emits start and end around a successful parse,skipped,,Node.js diagnostics_channel tracing has no Dart counterpart.
 diagnostics-test.ts,parse diagnostics channel,"emits start, error, and end when the parser throws",skipped,,Node.js diagnostics_channel tracing has no Dart counterpart.
 diagnostics-test.ts,parse diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,Node.js diagnostics_channel tracing has no Dart counterpart.
+blockString-fuzz.ts,printBlockString,correctly print random strings,ported,test/language/block_string_fuzz_test.dart,
```

- [ ] **Step 6: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+228: All tests passed!`, among them `names only graphql-js files that exist` and 15 `rows cover every test of …`.

- [ ] **Step 7: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,7 +10,12 @@
   `parser-test.ts`, `schema-parser-test.ts`, `printer-test.ts`,
   `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`,
   `schemaCoordinateLexer-test.ts`, `printLocation-test.ts`, `source-test.ts`,
-  `predicates-test.ts`, `kind-test.ts`, `diagnostics-test.ts`.
+  `predicates-test.ts`, `kind-test.ts`, `diagnostics-test.ts`,
+  `blockString-fuzz.ts`; the mapping test requires rows for every graphql-js
+  language test file.
 - Round-trip fuzzer (R10.4): random documents and schema coordinates,
   printed canonical and minified, parse back to equivalent trees;
   `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` tune it.
+- Hostile-text fuzzer (R1.6, R10.4): random and mutated text through every
+  parser entry point stays within the sink limit, and every diagnostic has
+  a source excerpt.
```

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -41,7 +41,9 @@ TYPED_GRAPHQL_FUZZ_ITERATIONS=100000 TYPED_GRAPHQL_FUZZ_SEED=7 dart test test/fu
 
 A failure names its case and the `Random` seed that replays it.
 `round_trip_fuzz_test.dart` prints random documents and coordinates and
-parses them back.
+parses them back; `hostile_text_fuzz_test.dart` feeds random and mutated
+text to every parser entry point and checks that it reports, within the
+sink limit, and never throws.
 
 ## License
 
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/mapping/language.csv packages/typed_graphql_conformance/test/fuzz/hostile_text_fuzz_test.dart packages/typed_graphql_conformance/test/language/block_string_fuzz_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/graphql_js_suite.dart
git commit -q -m "test(typed_graphql_conformance): fuzz hostile text and map every graphql-js language file"
```

### Task 13: Documents, full verification and the handoff

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/superpowers/HANDOFF.md`, `packages/typed_graphql/README.md`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/README.md`

**Interfaces:**
- Consumes: Tasks 1–12.
- Produces:
  - the status in `CLAUDE.md`, the READMEs and the barrel's library comment; the "Learned in M2b" notes;
  - the evidence that M2b is done, and a handoff that says so.

- [ ] **Step 1: Update the documents**

The core README gets a "Visiting and rewriting" section. Its example was run, and the output shown is what it printed.

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -22,9 +22,10 @@ Minimum SDK: Dart 3.13 (`sdk: ^3.13.0`) in every package and in generated
 code. No dependency on `package:gql` or its ecosystem.
 
 Status: under construction. M1 (foundations) delivered the workspace, the
-code rules, CI, the diagnostics model and the protocol data types. M2a
-(language core) delivers the syntax trees, the lexer, the parser, the
-printer and the ported graphql-js language suites.
+code rules, CI, the diagnostics model and the protocol data types. M2
+(language) delivers the syntax trees, the lexer, the parser, the printer,
+visitors and transformers, schema coordinates, source excerpts, every
+graphql-js language suite and the language fuzzers.
 
 ## Documents
 
@@ -234,6 +235,15 @@ Learned in M2a:
   library overrides `rebuildFrom(Object? read)` without the internal
   `ChildReader`.
 
+Learned in M2b:
+- Recursion over a syntax tree overflows the stack on the web long before
+  the VM; walk deep structures with an explicit stack.
+- A cascade cannot stand in a branch of `?:`: `c ? [...]..sort() : x` does
+  not parse. Write an `if` with two returns.
+- In a document, `{` after a body-less type extension (`extend enum E @d`)
+  opens that extension's body, as in graphql-js: a shorthand query can
+  only come first.
+
 **Dart style the lints do not check.** Acronyms longer than two letters are
 words (`Json`, `Sse`); doc comments start with a one-sentence summary and
 refer to identifiers in `[brackets]`; a boolean property starts with
@@ -291,4 +301,6 @@ fails when it finds none.
 - Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
 - Conformance mapping table: `packages/typed_graphql_conformance/mapping/language.csv`,
   checked by `test/mapping_test.dart` there; port helpers in its `test/support/`.
+- Fuzzers: `packages/typed_graphql_conformance/test/fuzz/`;
+  `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` tune them.
 - CI: `.github/workflows/ci.yml`.
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -58,8 +58,8 @@ void main() {
 ```
 
 > **Status: under construction.** Nothing is published to pub.dev yet, and
-> every API may change before 0.1.0. Stage M2 (language) is the current
-> one: the parser and the printer are in; visitors come next.
+> every API may change before 0.1.0. Stage M2 (language) is done: the
+> parser, the printer and visitors are in; the type system (M3) comes next.
 
 ## Table of contents
 
@@ -100,13 +100,13 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 
 | Package | Role | Status |
 |---|---|---|
-| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, parser and printer (M1, M2a) |
+| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language (M1, M2) |
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
-| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language suites (M2a) |
+| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language suites and fuzzers (M2) |
 
 ## Install
 
@@ -132,6 +132,8 @@ input:
 - `Parser().parse(Source(text))` gives a `Document`, or every syntax error
   as a `Diagnostic` with a code and a place; `Printer().print(node)` prints
   it back the way graphql-js does.
+- `AstWalker` walks a tree with an `AstVisitor`, `AstTransformer` rewrites
+  one, and `Parser().parseSchemaCoordinate` reads `Query.hero(episode:)`.
 
 ## Documentation
 
````

In `packages/typed_graphql/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -11,15 +11,16 @@ web (dart2js and dart2wasm). Part of
 [typed_graphql](https://github.com/4akloon/graphql_dart).
 
 > **Status: under construction.** This release has the diagnostics model, the
-> protocol data types, and the language: syntax trees, the lexer, the parser
-> and the printer. Visitors arrive later in M2, the type system in M3 and
-> validation in M4 (see the
+> protocol data types, and the language: syntax trees, the lexer, the
+> parser, the printer, visitors and schema coordinates. The type system
+> arrives in M3 and validation in M4 (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
 ## Contents
 
 - [Install](#install)
 - [Parsing and printing](#parsing-and-printing)
+- [Visiting and rewriting](#visiting-and-rewriting)
 - [Reading the wire format](#reading-the-wire-format)
 - [Diagnostics](#diagnostics)
 - [License](#license)
@@ -89,6 +90,92 @@ query Hero($id:ID!){hero(id:$id){name ...on Droid{primaryFunction}}}
 default) and `maxDepth` (128). Working-draft syntax, such as
 `extend directive`, is off unless `allowDirectiveExtensions` is set.
 
+## Visiting and rewriting
+
+`AstWalker` walks a tree depth-first and calls an `AstVisitor` on the way
+in and out; `enter` returns `VisitAction.next`, `skip` (not this node's
+children) or `stop`. `ParallelVisitor` runs several visitors in one walk.
+`AstTransformer` rewrites a tree bottom-up: `rewrite` returns the node, a
+replacement or `null` to remove it, and the original tree stays as it was.
+Neither recurses, so a tree of any depth is safe on the web too.
+`Parser().parseSchemaCoordinate` reads a schema coordinate, and a
+`SourceSpan` shows its line the way graphql-js's `printLocation` does.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+/// Counts the fields of a document.
+final class FieldCounter extends AstVisitor {
+  int count = 0;
+
+  @override
+  VisitAction enter(Node node) {
+    if (node is Field) {
+      count++;
+    }
+    return VisitAction.next;
+  }
+}
+
+/// Adds `__typename` to every selection set that lacks it.
+final class AddTypename extends AstTransformer {
+  const AddTypename();
+
+  @override
+  Node? rewrite(Node node) => switch (node) {
+    SelectionSet(:final selections) when !selections.any(_isTypename) =>
+      SelectionSet([...selections, Field(null, const Name('__typename'))]),
+    _ => node,
+  };
+
+  static bool _isTypename(Selection selection) =>
+      selection is Field && selection.name.value == '__typename';
+}
+
+void main() {
+  const parser = Parser();
+  const printer = Printer(isMinified: true);
+  if (parser.parse(Source('{ hero { name friends { name } } }'))
+      case ParseSuccess(:final document)) {
+    final counter = FieldCounter();
+    const AstWalker().walk(document, counter);
+    print(counter.count);
+    if (const AddTypename().transform(document) case final Node rewritten) {
+      print(printer.print(rewritten));
+    }
+  }
+
+  // A schema coordinate names one element of a schema.
+  if (parser.parseSchemaCoordinate(Source('Query.hero(episode:)'))
+      case ParseElementSuccess(:final value)) {
+    print('${value.runtimeType}: ${const Printer().print(value)}');
+  }
+
+  // A span shows the line it points at, as graphql-js does.
+  final source = Source('{\n  hero(id: )\n}', name: 'hero.graphql');
+  if (parser.parse(source) case ParseFailure(:final diagnostics)) {
+    for (final diagnostic in diagnostics) {
+      print(diagnostic);
+      print(diagnostic.span?.excerpt);
+    }
+  }
+}
+```
+
+It prints:
+
+```text
+4
+{hero{name friends{name __typename}__typename}__typename}
+ArgumentCoordinate: Query.hero(episode:)
+hero.graphql:2:12: error GQL008: Unexpected ")".
+hero.graphql:2:12
+1 | {
+2 |   hero(id: )
+  |            ^
+3 | }
+```
+
 ## Reading the wire format
 
 Bad input never throws. `JsonReader` turns text into a `JsonValue`, a sealed
@@ -142,7 +229,8 @@ The parser reports through this model, and the validator will:
 
 - `Source` is a document and its name; `locationOf(offset)` gives a 1-based
   line and column, counted in UTF-16 code units.
-- `SourceSpan` is a range of a `Source`.
+- `SourceSpan` is a range of a `Source`; `excerpt` shows its line and the
+  lines around it, with a caret.
 - `Diagnostic` is one problem: a `DiagnosticCode` with a stable id
   (`GQL000`), a severity, a message, a span and related spans.
 - `DiagnosticSink` collects diagnostics in order and stops at `maxErrors`
````

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,7 +8,8 @@
 
 > **Status: under construction.** Stage M2 of the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)
-> ports the graphql-js language suites; nothing is exported.
+> ports every graphql-js language suite and adds the language fuzzers;
+> nothing is exported.
 
 ## Ported suites
 
@@ -27,7 +28,7 @@ per graphql-js test, with the same group and test names.
 | `reason` | why, for `adapted` and `skipped` |
 
 `test/mapping_test.dart` checks the table; with `reference/` fetched it also
-checks that every test of a ported file has a row.
+checks that every test of every graphql-js language test file has a row.
 
 ## Fuzzing
 
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,7 +2,8 @@
 /// wire protocol, with diagnostics instead of exceptions.
 ///
 /// Under construction: this release has the diagnostics model, the protocol
-/// data types, and the language (syntax trees, lexer, parser, printer).
+/// data types, and the language (syntax trees, lexer, parser, printer,
+/// visitors, transformers and schema coordinates).
 library;
 
 export 'src/diagnostics/diagnostic.dart';
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
- the root suite gives `+34`, the core `+382` on the VM and as exe, and the five skeleton packages `+2` each;
- the conformance package gives `+228` with `reference/` fetched. Without it, `names only graphql-js files that exist` is skipped and the 15 coverage tests are not created;
- the core gives `+370` in Chrome with each compiler (the VM-only tests are not counted there). This includes the two 100 000-level walks of Review Focus 1.

- [ ] **Step 3: Check that the language layer stays pure**

Run: `grep -rln "dart:io" packages/typed_graphql/lib || echo "no dart:io"`

Expected: `no dart:io` (R0.6). `layers_test.dart` passed in Step 2, so `language/` still imports only `diagnostics/` and itself, and `diagnostics/source_excerpt.dart` imports nothing from `language/`.

- [ ] **Step 4: Record the result in the handoff**

In `docs/superpowers/HANDOFF.md`:
- set the line that starts with `Last updated:` to the first line below;
- replace the table row that starts with `| M2 Language |` by the second, whatever that row says now.

Leave everything else as it is.

```markdown
Last updated: 2026-10-14 (M2b implemented, final review pending). Read this
```

```markdown
| M2 Language | [spec](specs/2026-10-14-m2-language-design.md) | M2a: [plan](plans/2026-10-14-m2a-language-core.md); M2b: [plan](plans/2026-10-14-m2b-language-tools.md) | M2a merged into `main` locally (not pushed); M2b implemented on its branch, final review pending; then M3 |
```

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add CLAUDE.md README.md docs/superpowers/HANDOFF.md packages/typed_graphql/README.md packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql_conformance/README.md
git commit -q -m "docs: record the M2b language tools"
```

---

## Requirement coverage

| Id | Requirement (verbatim from `docs/requirements.md`) | Where |
|---|---|---|
| R0.3 | Bad input (documents, schemas, variables, responses) never throws: results are sealed types carrying every diagnostic. Exceptions only for programmer errors and inside user resolvers | Tasks 6–7 (coordinate text gives diagnostics; `ParseElementResult`), Task 12 (hostile text through all five entry points). Programmer errors: `StateError` for removing a required child (Task 3) |
| R0.6 | The core package is pure Dart: no `dart:io`, no dependencies except `meta`; it compiles with dart2js and dart2wasm | `layers_test.dart` in every green check; Task 13, Steps 2–3 |
| R0.7 | Spec conformance is measured with ported graphql-js v17 suites and a coverage mapping table | Tasks 4, 8, 9, 10, 12: every one of the 15 files of graphql-js's language tests has rows (233), and the check reads the directory |
| R1.6 | `maxTokens` and `maxDepth` limits | Task 12 checks that the limits and the sink bound hostile text; Tasks 1 and 3 make the traversal tools safe beyond `maxDepth` |
| R1.9 | `AstVisitor` with no-op defaults, `ParallelVisitor`, `AstTransformer` | Tasks 1–3; Task 4 (`visitor-test.ts`) |
| R1.10 | `Printer`: canonical and minified output; parse → print → parse is stable | Task 7 (coordinates), Task 11 (the random round trip, both forms) |
| R1.11 | Schema coordinates: parse and print | Tasks 5–7; Task 8 (the graphql-js coordinate tests) |
| R10.2 | Size-limit ratchet and core layer-direction tests | Every green check; the allowlists stay empty |
| R10.3 | `typed_graphql_conformance` with ported graphql-js suites and a coverage mapping table | Tasks 4, 8, 9, 10, 12 |
| R10.4 | Parse → print → parse fuzzing | Task 11 (property 1 of spec §8), Task 12 (property 2) |

## Open questions

Each has the plan's choice; the plan runs as written unless the user decides otherwise.

1. **Keep `leave` read-only?** The plan follows spec §6: `leave` returns nothing and edits go through `AstTransformer`, which skips 14 graphql-js visitor tests (finding 1). The alternative, a `leave` that returns an action, buys early exit on leave and nothing that code generation or validation (M4) is known to need. Recommended: keep it.
2. **`Source.locationOffset`?** The plan does not add it (finding 2). It matters when a document is embedded in another file, for example a `gql` string inside Dart source that the builder (M9) reads, so its diagnostics point at the right line. Recommended: decide in M9.

## Self-review

- **Spec coverage.** Every item of the M2b row of the spec's section 1 has a task: `AstVisitor` and `AstWalker` (Task 1), `ParallelVisitor` (Task 2), `AstTransformer` (Task 3), schema coordinates as nodes, lexer, parser and printer (Tasks 5–7), the visitor, coordinate-lexer and `printLocation` ports (Tasks 4, 8, 9), the rows M2a left for M2b (Tasks 9, 10, 12), the fuzzing of section 8 (Tasks 11–12), and the documents (each task, then Task 13).
- **Verified code.** Every code block was applied, task by task, to a copy of `main` at `164f77c`, and every commit passed the green check. Each TDD task was seen failing before its implementation with the message quoted in its "see them fail" step, and passing after with the count quoted. The core tests also passed with `--compiler exe` (`+382`) and in Chrome with dart2js and dart2wasm (`+370` each); the conformance suite passed with `--compiler exe` and dart2js too.
- **Code rules.** The largest new `lib/` file has 126 lines (`schema_coordinate.dart`); the longest new method has 35 lines (`SchemaCoordinateParser.coordinate`). The largest test file has 380 lines (`visitor_kitchen_sink_test.dart`). No allowlist entry, no `// ignore:`, no top-level function besides `main`, and no `dynamic`.
- **Names and types.** The names in each task's "Interfaces" match the code in its steps, and later tasks use the same names.
- **No placeholders.** Every file is given whole or as a diff that was applied.

## Execution handoff

Two ways to run this plan:

1. **Subagent-driven (recommended).** Dispatch a fresh `implementer` subagent (model `sonnet`) for each task, then a `reviewer` subagent (model `sonnet`) on that task. A final whole-branch review with model `opus` comes at the end. Use superpowers:subagent-driven-development. Tasks 5–8 depend on each other's interfaces (`TokenSource`, the coordinate nodes and their `AstJson`), which the "Interfaces" blocks pin, and a fresh reviewer per task catches drift early.
2. **Native.** Run the tasks in this session with superpowers:executing-plans, with a checkpoint after Tasks 4, 8 and 12.

Work on a branch `m2b-language-tools` in a worktree, from `main` at `164f77c`. Fetch `reference/` once (`tool/fetch_reference.sh`). Do not push, tag or publish without the user's yes. Executors append the trailers their session instructs.
