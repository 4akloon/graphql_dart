# Contributing to typed_graphql

## Contents

- [Prerequisites](#prerequisites)
- [Getting the code](#getting-the-code)
- [Repository layout](#repository-layout)
- [Everyday commands](#everyday-commands)
- [Design rules](#design-rules)
- [Coding conventions](#coding-conventions)
- [Dart 3.13](#dart-313)
- [Tests](#tests)
- [Diagnostic codes](#diagnostic-codes)
- [Commits and pull requests](#commits-and-pull-requests)

## Prerequisites

- Dart SDK 3.13 or newer (`sdk: ^3.13.0`). Every package is pure Dart;
  Flutter is not needed.
- Google Chrome, to run the core's tests compiled to JavaScript and Wasm.

## Getting the code

This repository is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces):
all packages resolve together from one lockfile. Run this once from the
repository root:

```sh
dart pub get
```

## Repository layout

The packages are listed in the [root README](README.md#packages). Requirements,
the roadmap, the architecture spec and the research are in [docs/](docs/);
[CLAUDE.md](CLAUDE.md) is the full guide to the code and its rules.
[docs/discovery.md](docs/discovery.md) says how agents and people find the
packages, and what a README, a pubspec description and `llms.txt` may claim.

## Everyday commands

From the repository root unless noted:

```sh
dart format packages test
dart analyze --fatal-infos
dart test                                   # the code rules of the whole workspace

cd packages/typed_graphql && dart test      # and likewise for every package
cd packages/typed_graphql && dart test --compiler exe
cd packages/typed_graphql && dart test -p chrome --compiler dart2js
cd packages/typed_graphql && dart test -p chrome --compiler dart2wasm

# Before a release, for each publishable package:
cd packages/<package> && dart pub publish --dry-run
```

## Design rules

- **Bad input never throws.** Parsing, validation, coercion and decoding
  return sealed results that carry every diagnostic. Exceptions are for
  programmer errors (`ArgumentError`, `RangeError`, `StateError`).
- **Every problem has a stable code** from the `DiagnosticCode` catalog and a
  place in the source, or a path in the JSON.
- **Fully typed.** No `dynamic` and no `Map<String, dynamic>` in a public
  signature; arbitrary JSON is `JsonValue`.
- **The core is pure Dart.** `typed_graphql` depends only on `meta`, imports
  no `dart:io`, and runs on the VM, AOT, dart2js and dart2wasm. Its layers
  import downwards only: `diagnostics`, `language`, `protocol`, `schema`,
  `validation`.
- **Independent of `package:gql`.** No dependency on it or its ecosystem.
- **`analyzer` only in `typed_graphql_builder`.**

## Coding conventions

`analysis_options.yaml` (on `package:lints/recommended.yaml`) is enforced
with `--fatal-infos`; every public member has a doc comment. The workspace
suite in `test/quality/` enforces the rest:

- files in `lib/` at most 300 lines, test files at most 500, methods at most
  40, at most 5 parameters per method, control blocks nested at most 3 deep;
- one public class or sealed family per file in `lib/`;
- no `part` files, no top-level functions except `main`, no `utils` or
  `helpers` files, no `dynamic`, no `catch` without `on`.

Components that report problems take a `DiagnosticSink` through their
constructor. Never silence a lint with `// ignore:`.

## Dart 3.13

Use the stable 3.13 features where they fit: primary constructors, dot
shorthands (`.error`), null-aware elements (`'key': ?value`), switch
expressions and patterns, records, class modifiers. Give a primary
constructor a documented `this;` body so `public_member_api_docs` passes. In
tests, `expect(...)` arguments have no context type, so use full names there.

## Tests

- Tests come with the code, in the same commit; a new branch of logic has a
  test that fails without it.
- A test that needs `dart:io` starts with `@TestOn('vm')`: the core suite
  also runs in Chrome.
- Ported graphql-js tests (from M2) are listed in the conformance mapping
  table in the same commit.

## Diagnostic codes

A new code goes into `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`
in id order, with a doc comment that says when it is reported. Ids are
public API: never renumber, reuse or remove one.

## Commits and pull requests

- Branch off `main`. Commit messages are Conventional Commits with the
  package as the scope (`feat(typed_graphql): ...`).
- Before pushing: format, analyze, and the suites of the packages you
  touched, plus `dart test` at the root.
- Add a line to the affected package's `CHANGELOG.md` for every user-facing
  change; mark a breaking one `**Breaking:**`.
