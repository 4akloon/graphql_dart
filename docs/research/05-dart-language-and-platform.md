# 05. Dart language and platform capabilities (as of 2026-10)

Date: 2026-10-13. Scope: the Dart language, core libraries, formatter/analyzer/codegen tooling, and compilation targets (VM/AOT/JS/Wasm) relevant to `graphql_dart` — a from-scratch, fully typed, spec-complete GraphQL implementation (lexer/parser, immutable AST, schema/type system, validation, async execution engine, introspection, HTTP/WebSocket/SSE transports, typed client + code generation). Method: primary-source research against dart.dev (blog, language docs, changelog, `resources/whats-new`), `github.com/dart-lang/sdk` (CHANGELOG, runtime pragma docs, benchmarks, issues), `github.com/dart-lang/language` (`accepted/`, `working/`, issues, funnel), `github.com/dart-lang/dart_style`, pub.dev package changelogs (`analyzer`, `build_runner`, `source_gen`, `build`, `dart_style`, `hooks`), flutter.dev / docs.flutter.dev release notes, and the local toolchain (`dart --version`, `flutter --version`). Every factual claim below carries a source link; local-toolchain facts are marked `[local]`.

Local toolchain, captured 2026-10-13:
```
$ dart --version
Dart SDK version: 3.13.1 (stable) (Tue Aug 18 01:00:59 2026 -0700) on "linux_x64"
$ flutter --version
Flutter 3.47.1 • channel stable
Tools • Dart 3.13.1 • DevTools 2.60.0
```
`[local]`

The existing `graphql_dart` codebase (`lib/src/language/*`, a hand-written mutable AST — `Node`, `Value`/`IntValue`/`FloatValue`/`BooleanValue`/`ArrayValue`, `Type`/`ListType`/`TypeName`, `Definition`, `Selection`, a visitor in `node_visitor.dart`) currently declares `environment: sdk: ^3.2.3` in `pubspec.yaml` — i.e. it predates almost everything in section 1 below except records/patterns/class-modifiers/exhaustiveness themselves. This report's recommendations are written against that shape of codebase.

## 0. In brief

1. **Latest stable Dart is 3.13** (3.13.x patch train, currently 3.13.5), released 2026-08-12. Dart ships a new stable roughly every three months. ([dart.dev/resources/whats-new](https://dart.dev/resources/whats-new), [dart.dev/tools/sdk](https://dart.dev/tools/sdk))
2. **Flutter's current stable channel is Flutter 3.47** (released 2026-08-12), bundling **Dart 3.13**. Confirmed both from Flutter's own docs and locally (`flutter --version` → Dart 3.13.1). Flutter 3.50 (→ Dart 3.14) targets November 2026 and is not yet released. ([docs.flutter.dev/release/release-notes](https://docs.flutter.dev/release/release-notes), [docs.flutter.dev/install/archive](https://docs.flutter.dev/install/archive)) `[local]`
3. **Primary constructors** graduated from an experimental preview in Dart 3.12 to **stable in Dart 3.13** — a direct ergonomic win for the AST/type-system node classes already in this repo. ([dart.dev/blog/announcing-dart-3-13](https://dart.dev/blog/announcing-dart-3-13))
4. **Macros were cancelled** on 2025-01-29. The team is instead shipping "more bespoke language features" for data (primary/declaring constructors, pattern matching) and promised (but, as of 3.13, has not yet shipped) **augmentations**, extracted from the macro prototype, to speed up classic `build_runner`-based code generation. Design the codegen package around `build_runner`/`source_gen`, not macros. ([dart.dev/blog/an-update-on-dart-macros-data-serialization](https://dart.dev/blog/an-update-on-dart-macros-data-serialization))
5. **Records, patterns, sealed/final/base/interface/mixin modifiers, and exhaustive switches** (all Dart 3.0, 2023-05-10) plus **extension types** (Dart 3.3, 2024-02-15) are the backbone to build the AST/type-system/value model on. ([dart.dev/blog/announcing-dart-3](https://dart.dev/blog/announcing-dart-3), [dart.dev/blog/new-in-dart-3-3-extension-types-javascript-interop-and-more](https://dart.dev/blog/new-in-dart-3-3-extension-types-javascript-interop-and-more))
6. **Native assets / build hooks** matured from experimental to a documented stable feature across 3.9–3.13: `dart build` was beta-preview in 3.9, **build hooks went stable in 3.10**, and **link hooks + recorded-use tree-shaking shipped in 3.13**. Not needed for a pure-Dart GraphQL core, but relevant if we ever ship a native (e.g. SIMD-JSON or Rust) fast-path parser as an optional package. ([dart.dev/blog/announcing-dart-3-10](https://dart.dev/blog/announcing-dart-3-10), [dart.dev/tools/hooks](https://dart.dev/tools/hooks))
7. **dart2wasm/WasmGC is mature**: Dart-to-Wasm compilation has been generally available for Flutter web since Flutter 3.24 (mid-2024), `dart compile wasm` is a first-class, non-experimental `dart compile` target today, and incremental work (deferred loading) is still landing, targeted at Flutter 3.50 (Nov 2026). ([docs.flutter.dev/platform-integration/web/wasm](https://docs.flutter.dev/platform-integration/web/wasm), [dart.dev/tools/dart-compile](https://dart.dev/tools/dart-compile))
8. **The codegen ecosystem had real churn.** `analyzer` moved its whole element model to a new API (first called "element2", now just "the v2 element model") across analyzer 7.x–14.x and **deprecated element model v1**; `build_runner` ≥2.15 requires Dart ≥3.11; `source_gen` 4.x requires Dart ≥3.9; `dart_style` is on its 3.x "tall style" line (current 3.1.13). A code generator written today must target the v2 element model directly, not v1. ([pkg/analyzer element_model_migration_guide.md](https://github.com/dart-lang/sdk/blob/main/pkg/analyzer/doc/element_model_migration_guide.md), [pub.dev/packages/build_runner/versions](https://pub.dev/packages/build_runner/versions), [pub.dev/packages/source_gen/versions/4.2.3/changelog](https://pub.dev/packages/source_gen/versions/4.2.3/changelog), [pub.dev/packages/dart_style/changelog](https://pub.dev/packages/dart_style/changelog))
9. **`Isolate.run`** (stable since Dart 2.19 / Flutter 3.7, 2023-01-24) is explicitly recommended by Dart's own docs for "parsing and decoding exceptionally large JSON blobs" — almost literally our use case for offloading large query/response parsing and expensive validation (e.g. query-complexity analysis) off the event loop. ([dart.dev/language/isolates](https://dart.dev/language/isolates), [dart.dev/blog/better-isolate-management-with-isolate-run](https://dart.dev/blog/better-isolate-management-with-isolate-run))
10. **Extension types are a compile-time-only, zero-runtime-cost wrapper** — erased at compile time, no allocation — ideal for typed IDs, branded strings/`NodeId`s, and "newtype" wrappers in the type system and client layers. **Records are not guaranteed zero-cost**: the feature spec explicitly leaves heap-allocation elision to the compiler's optimizer/escape analysis, so budget them as "cheap small values," not "free." ([dart.dev/language/extension-types](https://dart.dev/language/extension-types), [dart-lang/language records feature-specification.md](https://github.com/dart-lang/language/blob/main/accepted/3.0/records/feature-specification.md))
11. `Iterable<Future<T>>.wait` (an extension on `dart:core`'s `Iterable`) gives a built-in, allocation-light way to resolve a GraphQL selection set's sibling fields **concurrently**, which is exactly what the spec requires for query (non-mutation) field execution. ([api.dart.dev/dart-core/Iterable-class.html](https://api.dart.dev/dart-core/Iterable-class.html))
12. **Recommended SDK constraint: `sdk: ^3.13.0`** across all packages in the monorepo (core, validation, execution, codegen, client, transports) — see the final section for the full trade-off analysis against older Flutter stables.

## 1. Dart 3.0–3.5 baseline

All of the following shipped in **Dart 3.0** (2023-05-10, "Announcing Dart 3" — 100% sound null safety, records, patterns, class modifiers) unless noted. ([dart.dev/blog/announcing-dart-3](https://dart.dev/blog/announcing-dart-3))

### Records (3.0)
Anonymous, immutable, structurally-typed aggregates. ([dart.dev/language/records](https://dart.dev/language/records))
```dart
(Token, int) scanNext(String src, int pos) {
  // ... lexer logic ...
  return (token, pos + token.length);
}
```
**How we use it**: multi-value returns from the lexer (`(Token, int offset)`), from the parser's internal recursive-descent helpers, and as lightweight (value, path-segment) pairs while walking a `GraphQLError`'s `path`. Avoid records as the *public* AST node type — use sealed classes there so visitors get exhaustiveness (see below) and named, documented classes in generated docs.

### Patterns, destructuring, switch expressions (3.0)
```dart
Value parseValue(Token t) => switch (t) {
  Token(kind: TokenKind.int, :final text) => IntValue(int.parse(text)),
  Token(kind: TokenKind.string, :final text) => StringValue(text),
  Token(kind: TokenKind.name, text: 'true' || 'false', :final text) =>
    BooleanValue(text == 'true'),
  _ => throw GraphQLSyntaxError('Unexpected token', t.location),
};
```
**How we use it**: token classification in the lexer, destructuring record returns, and dispatch over `Value`/`Type`/`Selection` kinds in the executor and printer — replacing long `if (x is Foo) ... else if (x is Bar)` chains with a single exhaustive `switch`.

### sealed / final / base / interface / mixin class modifiers (3.0)
```dart
sealed class Value {}
final class IntValue extends Value { final int value; IntValue(this.value); }
final class StringValue extends Value { final String value; StringValue(this.value); }
final class ListValue extends Value { final List<Value> values; ListValue(this.values); }
// ... EnumValue, ObjectValue, BooleanValue, FloatValue, NullValue, VariableValue
```
**How we use it**: close every AST hierarchy (`Node`, `Value`, `Type`, `Selection`, `Definition`) with `sealed`, so the compiler enforces exhaustive handling everywhere we `switch` over a node kind — this is the single biggest correctness lever available for a spec-complete implementation, because every time the GraphQL spec (or a future Dart AST revision) adds a new value/type/selection kind, every non-exhaustive `switch` across the codebase becomes a compile error instead of a silent runtime gap. ([dart.dev/language/class-modifiers](https://dart.dev/language/class-modifiers))

### Exhaustiveness checking (3.0)
```dart
String printValue(Value v) => switch (v) {
  IntValue(:final value) => '$value',
  StringValue(:final value) => '"${_escape(value)}"',
  ListValue(:final values) => '[${values.map(printValue).join(', ')}]',
  // Compile error if any Value subtype is left out, because Value is sealed.
};
```
([dart.dev/language/branches](https://dart.dev/language/branches))

### Extension types (3.3, 2024-02-15)
Compile-time-only wrapper type with a different static interface over an existing representation type; erased entirely at compile time. ([dart.dev/language/extension-types](https://dart.dev/language/extension-types), [dart.dev/blog/new-in-dart-3-3-extension-types-javascript-interop-and-more](https://dart.dev/blog/new-in-dart-3-3-extension-types-javascript-interop-and-more))
```dart
extension type const TypeName._(String name) {
  factory TypeName(String name) {
    if (!_nameRegex.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'invalid GraphQL name');
    }
    return TypeName._(name);
  }
}
```
**How we use it**: zero-cost branded wrappers — `TypeName`, `FieldName`, `NodeId`, `OperationName` — so the type system and executor catch "a raw `String` used where a validated GraphQL name is required" at compile time, with **no allocation or boxing at runtime** (unlike a `class` wrapper, which would allocate one object per name). Also the natural fit for the typed client's JS/JSON interop boundary later (same mechanism Dart itself uses for `package:web`/`dart:js_interop`).

(Dart 3.1/3.2/3.4/3.5 shipped on the standard ~3-month cadence between 3.0 and 3.6 — e.g. Dart 3.2 (2023-11-15) added non-null promotion for private final fields and DevTools extensions, and Dart 3.4 shipped alongside Flutter 3.22 at I/O 2024 (2024-05-14) — but introduced no additional AST/type-system-shaping language features beyond the above for our purposes. ([dart.dev/blog/announcing-dart-3-2](https://dart.dev/blog/announcing-dart-3-2), [dart.dev/tools/sdk](https://dart.dev/tools/sdk)))

## 2. Dart 3.6 → 3.13: everything shipped since

| Dart ver. | Release date | Feature |
|---|---|---|
| 3.6 | 2024-12-11 | Digit separators (`1_000_000`); pub workspaces introduced |
| 3.7 | ~2025-02 | Wildcard variables (`_`); new "tall style" `dart format` |
| 3.8 | 2025-05-20 | Null-aware elements in collection literals (`?e`) |
| 3.9 | 2025-08-14 | Null-safety-complete type promotion/reachability; `dart build` beta preview; Dart/Flutter MCP server |
| 3.10 | 2025-11-12 | Dot shorthands (`.foo`); analyzer plugin system; **build hooks stable** |
| 3.11 | 2026-02-11 | Pub workspaces glob support (`pkg/*`); `pub cache gc` |
| 3.12 | 2026-05-20 | Private named parameters (`_name:`); primary constructors (experimental preview) |
| 3.13 | 2026-08-12 | **Primary constructors stable**; link hooks + recorded-use tree-shaking; formatter block-formats `as`/`is`/`is!` |

Sources: ([dart.dev/blog/announcing-dart-3-6](https://dart.dev/blog/announcing-dart-3-6), [dart.dev/blog/announcing-dart-3-7](https://dart.dev/blog/announcing-dart-3-7), [dart.dev/blog/announcing-dart-3-8](https://dart.dev/blog/announcing-dart-3-8), [dart.dev/blog/announcing-dart-3-9](https://dart.dev/blog/announcing-dart-3-9), [dart.dev/blog/announcing-dart-3-10](https://dart.dev/blog/announcing-dart-3-10), [dart.dev/blog/announcing-dart-3-11](https://dart.dev/blog/announcing-dart-3-11), [dart.dev/blog/announcing-dart-3-12](https://dart.dev/blog/announcing-dart-3-12), [dart.dev/blog/announcing-dart-3-13](https://dart.dev/blog/announcing-dart-3-13))

### Digit separators (3.6)
```dart
const maxQueryComplexity = 1_000_000;
```
Purely cosmetic for us (large complexity-budget / timeout-ms constants). ([dart.dev/blog/announcing-dart-3-6](https://dart.dev/blog/announcing-dart-3-6))

### Pub workspaces (3.6, glob support 3.11)
```yaml
# root pubspec.yaml
name: graphql_dart_workspace
environment:
  sdk: ^3.13.0
workspace:
  - packages/*
```
**How we use it**: split the project into workspace packages (`graphql_dart_core`, `graphql_dart_validation`, `graphql_dart_execution`, `graphql_dart_codegen`, `graphql_dart_client`, `graphql_dart_http`, `graphql_dart_ws`) that resolve against one shared lockfile without a separate melos-style tool, while each still ships an independent, correctly versioned pub.dev package. ([dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces), [dart.dev/blog/announcing-dart-3-11](https://dart.dev/blog/announcing-dart-3-11))

### Wildcard variables (3.7)
```dart
switch (selection) {
  case FieldSelection(:final name, arguments: _):
    visitField(name);
  case FragmentSpread(:final _):
    // fragment name intentionally ignored here
}
```
Lets destructuring patterns bind-and-discard without inventing throwaway names or analyzer "unused variable" warnings. ([dart.dev/blog/announcing-dart-3-7](https://dart.dev/blog/announcing-dart-3-7))

### New "tall style" formatter (3.7, `dart_style` 3.x)
Language-versioned: files at language version ≥3.7 are formatted in the new style (trailing-comma-like argument/parameter splitting), older files keep the pre-3.7 style. Current `dart_style` is 3.1.13. **This matters directly for the code generator**: generated `.g.dart` files must be formatted with a `dart_style` version/language-version pairing that matches what the target project expects, or `dart format --set-exit-if-changed` in CI will flag generator output as unformatted. ([dart.dev/blog/announcing-dart-3-7](https://dart.dev/blog/announcing-dart-3-7), [pub.dev/packages/dart_style/changelog](https://pub.dev/packages/dart_style/changelog))

### Null-aware elements (3.8)
```dart
final args = [
  ?requiredArg,
  if (optionalArg case final a?) a,
  ...?extraDirectiveArgs,
];
```
**How we use it**: building argument lists / selection sets while filtering out absent (not just `null`-valued) optional directives and variable values, replacing `if (x != null) x` collection-if noise. ([dart.dev/language/collections](https://dart.dev/language/collections), [dart.dev/blog/announcing-dart-3-8](https://dart.dev/blog/announcing-dart-3-8))

### Dot shorthands (3.10)
```dart
ExecutionResult resolve(Field f) => switch (f.kind) {
  .scalar => .single(computeScalar(f)),      // ExecutionResult.single
  .object => .nested(computeObject(f)),      // ExecutionResult.nested
};
```
**How we use it**: concise `enum`/factory-constructor call sites in generated client code and examples wherever the expected type is inferable from context (resolver return kinds, `GraphQLErrorCode.*`, directive-location enums). ([dart.dev/blog/announcing-dart-3-10](https://dart.dev/blog/announcing-dart-3-10))

### Private named parameters (3.12)
```dart
class FieldNode extends Node {
  FieldNode({required this.name, required SourceLocation? _location})
      : super(location: _location);
  final FieldName name;
}
```
Before 3.12 a named parameter couldn't start with `_`; this lets internal-only constructor parameters (e.g. a raw, unvalidated payload, or an internal location override) exist without ever being part of the public named-parameter API surface. ([dart.dev/blog/announcing-dart-3-12](https://dart.dev/blog/announcing-dart-3-12))

### Primary constructors (experimental 3.12 → stable 3.13)
```dart
final class FieldNode(
  final FieldName name,
  final List<ArgumentNode> arguments,
  final SelectionSetNode? selectionSet,
  final SourceLocation? location,
) extends Node;
```
Requires language version ≥3.13. Collapses "declare the field, then repeat it in the constructor parameter list, then repeat it again in the initializer" down to one declaration — directly applicable to every one of the ~45 AST node classes already in `lib/src/language/`. The Dart team also shipped IDE quick-fixes ("Convert to primary constructor" / "Convert to in-body constructor") to make the migration mechanical. ([dart.dev/language/primary-constructors](https://dart.dev/language/primary-constructors), [dart.dev/blog/announcing-dart-3-13](https://dart.dev/blog/announcing-dart-3-13), [dart.dev/blog/bringing-primary-constructors-to-dart](https://dart.dev/blog/bringing-primary-constructors-to-dart))

### Build hooks (stable 3.10) / link hooks + tree-shaking (3.13)
```dart
// hook/build.dart — only relevant if we ship a native fast-path package
import 'package:hooks/hooks.dart';
void main(List<String> args) => build(args, (input, output) async { /* ... */ });
```
Not needed for the pure-Dart GraphQL core. Relevant only for an optional, separate package (e.g. a SIMD/Rust-backed JSON scanner) that a consumer could opt into. ([dart.dev/tools/hooks](https://dart.dev/tools/hooks))

## 3. Macros, augmentations, and the post-macro codegen story

Macros were paused on 2025-01-29 ("An update on Dart macros & data serialization", Vijay Menon): after repeated technical setbacks around analysis/compile-time cost, the Dart team stopped macro development entirely. The post explicitly redirects effort to (a) "more bespoke language features" for data — which is exactly what primary/declaring constructors and the private-named-parameters work above are — and (b) shipping **augmentations**, extracted from the macro prototype, "a feature [that] stands on its own and will improve existing code generation," plus unspecified `build_runner` build-time improvements. ([dart.dev/blog/an-update-on-dart-macros-data-serialization](https://dart.dev/blog/an-update-on-dart-macros-data-serialization))

As of Dart 3.13 (2026-08-12) we found **no blog post or changelog entry announcing augmentations as shipped/stable** — it remains a promised-but-undelivered feature 19 months after the announcement. **Do not design the code generator around macros or augmentations.** Build it on `build_runner` + `source_gen` + `analyzer`'s new element model (section 4), which is the only currently-stable code-generation path.

**Policy**: ❌ macros (cancelled, do not use); ⚠️ augmentations (design the codegen package's public API so that, if augmentations ship, the generated-code/hand-written-code split could later move from "separate `part`/`.g.dart` file" to "an augmentation of the same library" without an API-breaking change — but do not block on it).

## 4. Codegen ecosystem versions and churn

| Package | Current | Min Dart SDK | Notable churn |
|---|---|---|---|
| `analyzer` | 14.4.0 | — | Migrated to a new ("element2"/v2) element-model API starting ~7.3–7.4; **element model v1 is now deprecated** | ([pub.dev/packages/analyzer/changelog](https://pub.dev/packages/analyzer/changelog), [element_model_migration_guide.md](https://github.com/dart-lang/sdk/blob/main/pkg/analyzer/doc/element_model_migration_guide.md)) |
| `build_runner` | 2.16.1 | 3.11.0 | `build` 3.0.0-dev requires `analyzer`'s new `element2` APIs (breaking) | ([pub.dev/packages/build_runner/versions](https://pub.dev/packages/build_runner/versions), [pub.dev/packages/build/changelog](https://pub.dev/packages/build/changelog)) |
| `source_gen` | 4.3.0 | 3.9.0 (for 4.2.x) | — | ([pub.dev/packages/source_gen](https://pub.dev/packages/source_gen), [source_gen 4.2.3 changelog](https://pub.dev/packages/source_gen/versions/4.2.3/changelog)) |
| `dart_style` | 3.1.13 | — | 3.x line is the "tall style"; `DartFormatter()`'s language-version parameter is becoming mandatory | ([pub.dev/packages/dart_style/changelog](https://pub.dev/packages/dart_style/changelog)) |

**How we use this**: the `graphql_dart_codegen` package (schema-first and/or document-first Dart client generation) should be built as a standard `build_runner`/`source_gen` `Builder`, written directly against `package:analyzer`'s current element model (not the deprecated v1 `Element` API — follow the SDK's own migration guide), and should depend on `dart_style: ^3.1.0` (or widen to accept the installed project's `dart_style` via the loose constraint pattern `source_gen` itself uses) so emitted code is tall-style formatted and passes `dart format --set-exit-if-changed` out of the box. Given the real version churn observed above (analyzer 7→14 in roughly 18 months), **pin ranges loosely** (`analyzer: '>=X.0.0 <(X+N).0.0'`) the way `source_gen` itself does, rather than exact-pinning, and budget CI time for periodic bumps.

## 5. Compilation targets: dart2wasm, dart compile, native assets

`dart compile` today supports six output types side by side: self-contained `exe`, `aot-snapshot`, `jit-snapshot`, portable `kernel`, `js`, and `wasm` (WebAssembly/WasmGC module + source map) — `wasm` is listed as an ordinary, non-experimental target in the current docs. ([dart.dev/tools/dart-compile](https://dart.dev/tools/dart-compile))

Flutter's Wasm/WasmGC web support has been generally available since **Flutter 3.24** (mid-2024) — `flutter build web --wasm` — with further work (deferred loading of Wasm modules) still landing and targeted for the upcoming **Flutter 3.50** (Nov 2026). Chromium/V8 has supported WasmGC since Chrome 119; Firefox 120 added stable WasmGC support with one known interop limitation at last check. ([docs.flutter.dev/platform-integration/web/wasm](https://docs.flutter.dev/platform-integration/web/wasm))

Native assets / build hooks (`hook/build.dart`, `package:hooks`, `package:code_assets`) let a package compile or download non-Dart (C/C++/Rust/Go) libraries and call them through `@Native` FFI bindings; `dart build` (distinct from `dart compile`, which explicitly does **not** run hooks and fails if any are present) runs them. Build hooks: stable since 3.10. Link hooks (tree-shake unused native code before bundling) and "recorded usage" tree-shaking: stable since 3.13; `package:hooks` itself reached its `1.0.0` stable release and is currently at 2.2.0. ([dart.dev/tools/hooks](https://dart.dev/tools/hooks), [dart.dev/tools/dart-compile](https://dart.dev/tools/dart-compile), [pub.dev/packages/hooks/changelog](https://pub.dev/packages/hooks/changelog))

**How we use this**: keep the core GraphQL packages (lexer/parser/AST/validation/execution/client) pure Dart with no `dart:ffi`/`dart:io`-only dependencies on hot paths, so they compile cleanly to `exe`/`aot-snapshot` (server), `js`/`wasm` (web client), and run under Flutter on all platforms without conditional imports beyond the standard `dart:io` vs `package:web` split already required for HTTP/WebSocket transports. If we ever add a native fast-path JSON/UTF-8 scanner, ship it as a separate opt-in package using `hook/build.dart`, so pure-Dart/Wasm consumers are unaffected.

## 6. Performance-relevant facts for a parser/executor

**Records: optimizer-dependent, not guaranteed zero-alloc.** The accepted records spec is explicit: "We expect records to often be used for multiple return values. In that case ... we would like compilers to be able to easily optimize away the heap allocation and initialization of the record object" — i.e. elision is a compiler *optimization opportunity* (escape analysis), not a language guarantee. Treat records as "a cheap, non-boxed-per-field aggregate that *may* be stack-allocated/scalarized by the optimizer when it can prove the record doesn't escape," and still avoid building huge records in hot loops when a positional return or a mutable accumulator would do. ([records feature-specification.md](https://github.com/dart-lang/language/blob/main/accepted/3.0/records/feature-specification.md))

**Extension types: genuinely zero-cost.** Unlike records, extension types are static-only and "compiled away at run time ... essentially zero cost" by construction (no wrapper object ever exists) — use them freely for branded/validated wrapper types without a performance tax. ([dart.dev/language/extension-types](https://dart.dev/language/extension-types))

**`@pragma('vm:prefer-inline')`** (mirrored as `wasm:prefer-inline` and `dart2js:prefer-inline` on the other two backends) bypasses the compiler's normal cost-based inlining heuristic for a specific callee. It cannot force-inline methods containing a `try` block or declared `async`/`async*`/`sync*`. Reserve it for small, hot, leaf functions in the lexer's character-classification/scanning path after profiling — it is a targeted escape hatch, not a general-purpose speed switch. ([runtime/docs/pragmas.md](https://github.com/dart-lang/sdk/blob/main/runtime/docs/pragmas.md), [Frequently-asked-questions-about-the-Dart-VM.md](https://dart.googlesource.com/sdk/+/60a57cd42d64dc03e9f07aa60a2e250755c1ef28/docs/Frequently-asked-questions-about-the-Dart-VM.md))

**`String.codeUnitAt` vs `.runes`.** `codeUnitAt(i)` is O(1) indexed UTF-16 code-unit access with no allocation; `.runes` builds a `Runes` iterable over Unicode scalar values and must be walked with an iterator (no O(1) random access). A GraphQL source document is ASCII-dominant per the spec's `SourceCharacter` grammar; **scan with `codeUnitAt`/byte indexing, not `.runes`**, and only fall back to full Unicode-aware handling inside string-value escape processing where it's actually required. ([api.dart.dev/dart-core/String-class.html](https://api.dart.dev/dart-core))

**`Uint8List` for byte-oriented scanning.** When the source comes off a socket/HTTP/WebSocket frame as bytes, index a `Uint8List` directly (no boxing per byte) rather than decoding to `String` first if the lexer needs to run before full UTF-8 validation — decode to `String` once, lazily, for error messages only. ([dart:typed_data](https://api.dart.dev/dart-typed_data))

**`StringBuffer` for token/value assembly.** Avoid repeated `String` `+`/interpolation concatenation (O(n²)) when building escaped string-value contents or SDL-printer output; use a single `StringBuffer` per node/value and `write`/`writeCharCode` into it.

**`dart:convert`'s fused UTF-8→JSON decoder.** `utf8.decoder.fuse(json.decoder)` (or `JsonUtf8Decoder`) decodes a byte stream straight into JSON values without materializing an intermediate `String`, which is the right default for the HTTP/WebSocket transport's incoming-request and incoming-response decoding path. ([dart:convert library](https://dart.dev/libraries/dart-convert))

**`async`/`Future` cost vs `FutureOr` sync fast path.** Every `async` function is desugared into a state machine that always returns a `Future` (an allocation) even when its body never actually suspends. The Dart SDK's own micro-benchmark suite directly compares three resolver-shaped functions — a plain sync function, one declared to return `FutureOr<T>`, and one declared `async` — because this is a recognized, measurable cost difference. **Design resolver/field-execution function signatures to return `FutureOr<T>`** (not `Future<T>`) so a synchronous resolver (the common case for scalar/property-access fields) can return a bare value with zero `Future` allocation, while an actually-asynchronous resolver (DB/network call) can still return a real `Future<T>`; the executor awaits with `(await maybeFutureOr) as T`-style handling either way. ([dart-lang/sdk benchmarks/Calls/dart/Calls.dart](https://dart.googlesource.com/sdk/+/0f15e32ad3551ca492a5a7c62d9182d1e4fd4627/benchmarks/Calls/dart/Calls.dart), [dart:async FutureOr](https://api.dart.dev/dart-async/FutureOr-class.html))

**Sealed-class `switch` dispatch.** A `switch`/pattern match over a sealed hierarchy compiles down to ordinary type tests / class-id checks — the language guarantees compile-time *exhaustiveness*, not a special runtime dispatch fast-path. One sharp edge worth designing against: the AOT compiler performs allocation-aware dead-branch elimination on sealed-class switches (it can prove some subclass is never actually constructed and strip that branch); this optimization has had at least one real correctness bug in a large codebase (`dart-lang/sdk#56010`, "Switch statement over sealed class removed by Dart AOT compiler"). **Always run the test suite against an AOT-compiled binary** (`dart compile exe`), not just JIT (`dart run`), before release, specifically because sealed-switch-over-AST-node code is exactly the shape this class of bug hits. ([dart-lang/sdk#56010](https://github.com/dart-lang/sdk/issues/56010), [dart.dev/language/class-modifiers](https://dart.dev/language/class-modifiers))

**Isolates for CPU-heavy work.** `Isolate.run` (stable since Dart 2.19/Flutter 3.7) is Dart's own recommended tool for exactly this category of problem; the docs list "Parsing and decoding exceptionally large JSON blobs" and "Performing complex searching and filtering on large lists" as canonical use cases — i.e. large-document parsing, deep validation, and query-complexity/depth analysis are reasonable candidates to run on a worker isolate (or an isolate pool for a server handling concurrent requests) rather than blocking the request-handling isolate's event loop. ([dart.dev/language/isolates](https://dart.dev/language/isolates))

**Concurrent sibling-field resolution.** `Iterable<Future<T>>` has a built-in `.wait` extension ("Waits for futures in parallel") in `dart:core`, giving a zero-dependency way to implement the GraphQL spec's "fields may be resolved concurrently, in any order, for queries" rule: `final values = await selections.map(resolveField).wait;`. ([api.dart.dev/dart-core/Iterable-class.html](https://api.dart.dev/dart-core/Iterable-class.html))

## 7. Features in the pipeline — design forward-compatibly, do not depend on yet

| Feature | Status | Design implication |
|---|---|---|
| **Declaring constructors** (general form, beyond the primary-constructor syntax that already shipped) | `working/declaring-constructors`, "In-progress", experiment flag `declaring-constructors` | Would let *non-primary* (named/secondary) constructors also declare+initialize fields. Don't restructure the AST around the assumption every class only ever needs one (primary) constructor — some node types (e.g. ones with multiple named factory-style constructors) will want this once it ships. |
| **Static extension members** ("extension statics") | `working/0723-static-extensions`, two competing variant specs, unshipped | Would let us attach static parse/factory helpers (e.g. `TypeName.fromSDL(...)`) directly onto an extension type via `extension` syntax instead of a same-named top-level function. Keep such helpers as clearly-named top-level or static factory functions today so the migration, when available, is mechanical. |
| **Augmentations** | Promised 2025-01-29 as a macro-prototype spinoff; no stable-ship announcement found through Dart 3.13 (2026-08-12) | Keep the codegen package's generated-vs-hand-written split behind a narrow interface (e.g. always a `part` file or always a companion library, never string-concatenated into the user's file) so it could later target augmentations without an API break. |
| Dart 4.0 funnel items (e.g. proposed removal of `new` in constructor invocations) | Open issues on `dart-lang/language`, no committed timeline | Avoid relying on deprecated-leaning syntax (`new Foo()`) in generated code or examples; it already isn't needed since Dart 2, and an explicit Dart-4.0 removal proposal exists. |

Source for all of the above: the `dart-lang/language` repository's `working/` directory and issue tracker, which is what the repo's own `README` calls "the language funnel" — "the features that are being actively worked on." ([dart-lang/language README](https://github.com/dart-lang/language), [working/declaring-constructors/feature-specification.md](https://github.com/dart-lang/language/blob/main/working/declaring-constructors/feature-specification.md), [working/0723-static-extensions/feature-specification.md](https://github.com/dart-lang/language/blob/main/working/0723-static-extensions/feature-specification.md), [dart-lang/language issue #4726](https://github.com/dart-lang/language/issues/4726))

## Feature policy table

| Feature | Stable since | Status | How we use it | Policy |
|---|---|---|---|---|
| Records | 3.0 (2023-05) | Stable | Multi-value lexer/parser returns, (value, path) pairs | ✅ use (not as public AST type) |
| Patterns & destructuring | 3.0 | Stable | Token classification, binding in visitors | ✅ use |
| Switch expressions | 3.0 | Stable | Dispatch over Value/Type/Selection kinds | ✅ use |
| sealed/final/base/interface/mixin | 3.0 | Stable | Close Node/Value/Type/Selection hierarchies | ✅ use |
| Exhaustiveness checking | 3.0 | Stable | Compile-time coverage of all node kinds | ✅ use |
| Extension types | 3.3 (2024-02) | Stable | Zero-cost `TypeName`/`FieldName`/`NodeId` wrappers | ✅ use |
| Digit separators | 3.6 (2024-12) | Stable | Readability of large constants | ✅ use (low impact) |
| Pub workspaces | 3.6, glob 3.11 | Stable | Monorepo package layout | ✅ use |
| Wildcard variables | 3.7 (2025-02) | Stable | Discard unused pattern bindings | ✅ use |
| Tall-style formatter (`dart_style` 3.x) | 3.7 | Stable | Generated-code formatting | ✅ use, pin loosely |
| Null-aware elements | 3.8 (2025-05) | Stable | Filter absent args/directives in literals | ✅ use |
| `dart build` native compiler frontend | beta 3.9 | Beta/maturing | Not needed for pure-Dart core | ⚠️ only if native fast-path added |
| Build hooks (native assets) | 3.10 (2025-11) | Stable | Not needed for pure-Dart core | ⚠️ only if native fast-path added |
| Dot shorthands | 3.10 | Stable | Concise enum/factory literals | ✅ use |
| Analyzer plugin system | 3.10 | Stable | Custom lints for generated/schema code | ✅ use (optional) |
| Private named parameters | 3.12 (2026-05) | Stable | Internal-only ctor params on Node subtypes | ✅ use |
| Primary constructors | stable 3.13 (2026-08) | Stable | Flatten all AST/type-system node classes | ✅ use (floor must be ≥3.13) |
| Link hooks + recorded-use tree-shaking | 3.13 | Stable | Only relevant with native assets | ⚠️ only if native fast-path added |
| Declaring constructors (general) | — | Experimental (flag) | Multi-constructor field declaration | ⚠️ design forward-compatibly |
| Static extension members | — | Unshipped, in design | Static factories on extension types | ⚠️ design forward-compatibly |
| Augmentations | — | Promised, unshipped | Generated/hand-written code split | ⚠️ design forward-compatibly |
| Macros | — | **Cancelled** (2025-01-29) | n/a | ❌ avoid entirely |
| `dart compile wasm` / dart2wasm | GA groundwork 3.3; Flutter web GA since Flutter 3.24 | Stable | Client/transport layer must stay Wasm-clean | ✅ design for compatibility |
| `Isolate.run` | 2.19 / Flutter 3.7 (2023-01) | Stable | Offload large-doc parse/validate/complexity-analysis | ✅ use |
| `Iterable<Future<T>>.wait` | long-standing `dart:core` extension | Stable | Concurrent sibling-field resolution | ✅ use |
| `utf8.decoder.fuse(json.decoder)` | long-standing `dart:convert` | Stable | Byte-stream transport decoding, no intermediate String | ✅ use |
| `FutureOr<T>` resolver signatures | long-standing `dart:async` | Stable | Avoid `Future` allocation for sync resolvers | ✅ use |
| `@pragma('vm:prefer-inline')` | long-standing VM pragma | Stable (low-level) | Hot lexer inner loops, post-profiling only | ⚠️ use carefully |
| `String.codeUnitAt` over `.runes` | long-standing `dart:core` | Stable | Lexer scanning hot path | ✅ use |
| `analyzer` v2 element model | rolled out 7.x→14.x, v1 deprecated | Stable (moving target) | Codegen package's only supported target | ✅ use (must), pin loosely |
| `build_runner`/`source_gen`/`build` current majors | br ≥2.16 (Dart ≥3.11), sg ≥4.3 (Dart ≥3.9) | Stable, moving target | Codegen package foundation | ✅ use, pin loosely |

## Recommended SDK constraint and feature policy

**Recommendation: `environment: sdk: '^3.13.0'`** in every workspace package's `pubspec.yaml` (core, validation, execution, codegen, client, HTTP/WebSocket/SSE transports).

Rationale:
- `^3.13.0` is required to use **primary constructors** (stable only as of 3.13) across the ~45 existing AST node classes — this is the single highest-value syntax win identified in this report for a hand-rolled AST, and the task explicitly asks to use the latest Dart to the maximum.
- `^3.13.0` also gets link hooks + recorded-use tree-shaking "for free" should a native fast-path package be added later, without a second SDK-bump migration.
- Every other feature in the table above (records/patterns/sealed classes/extension types/null-aware elements/dot shorthands/private named params/wildcards/tall-style formatting) is already available well below 3.13, so raising the floor to 3.13 costs nothing *within* the feature set we want — it only costs compatibility with Flutter installations older than the current stable.

**Ecosystem cost — Flutter compatibility.** Flutter's **current stable channel (3.47, released 2026-08-12) already bundles Dart 3.13.1** (confirmed both via `flutter --version` locally and via Flutter's own release notes), so a `^3.13.0` floor excludes **no one on current Flutter stable**. It does exclude:
- Flutter 3.44 (Dart 3.12, released 2026-05) — loses primary constructors only, since private named params/dot shorthands/etc. all already work there.
- Flutter 3.41 (Dart 3.11, released 2026-02) and older — loses primary constructors and private named parameters.

Given Dart/Flutter's own support policy ("only the latest stable version is supported"; the Dart team expects users to move to a new stable roughly every 3 months), and that Flutter's own release cadence already keeps most app developers on Dart within one quarter of latest, **`^3.13.0` is the correct default** for a library whose explicit design goal is "use the capabilities of the latest Dart version to the maximum." ([dart.dev/tools/sdk](https://dart.dev/tools/sdk), [docs.flutter.dev/install/archive](https://docs.flutter.dev/install/archive))

If a future consumer explicitly needs to support older Flutter installs, the fallback is **`^3.9.0`** (keeps null-safety-complete promotion, the MCP server tooling, and everything from section 1; loses primary constructors, private named parameters, dot shorthands, the analyzer plugin system, and stable build hooks) — but that should be a conscious, documented exception per package, not the workspace default.

**Feature policy, restated as a one-line rule per bucket:**
- ✅ **Use freely**: records (as internal plumbing, not public AST), patterns/switch expressions, sealed/final/base/interface/mixin modifiers + exhaustiveness, extension types, null-aware elements, dot shorthands, wildcard variables, private named parameters, primary constructors, pub workspaces, `Isolate.run`, `Iterable.wait`, `FutureOr<T>` resolver signatures, fused `utf8`/`json` decoding, `codeUnitAt`-based scanning.
- ⚠️ **Use carefully / only when justified by profiling or an explicit native-assets need**: `@pragma('vm:prefer-inline')`, build hooks/native assets/`dart build`, pinning exact `analyzer`/`build_runner`/`dart_style` versions (pin ranges instead), relying on sealed-switch dead-branch elimination without an AOT test pass.
- ❌ **Avoid entirely**: macros (cancelled); `new` in constructor invocations in generated/example code (slated for Dart 4.0 removal); depending on declaring-constructors, static extension members, or augmentations as if already shipped.
