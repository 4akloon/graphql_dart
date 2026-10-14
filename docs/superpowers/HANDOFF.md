# Handoff: where typed_graphql stands and how to continue

Last updated: 2026-10-14 (M3a, M3c and M3b merged into `main` locally, not pushed). Read this
first on a new device or in a new Claude session. Session memory and scratch
directories do not travel; this file and the repository hold everything
needed.

## State

| Stage | Design | Plan | Code |
|---|---|---|---|
| Architecture | [spec](specs/2026-10-13-typed-graphql-design.md), [requirements](../requirements.md), [roadmap](../roadmap.md) | — | — |
| M1 Foundations | the architecture spec (no stage spec) | [plan](plans/2026-10-13-m1-foundations.md) | done: merged into `main` locally (not pushed); next is M2 |
| M2 Language | [spec](specs/2026-10-14-m2-language-design.md) | M2a: [plan](plans/2026-10-14-m2a-language-core.md); M2b: [plan](plans/2026-10-14-m2b-language-tools.md) | M2a and M2b merged into `main` locally (M2a pushed, M2b not); M2 is complete; next is M3 (schema) |
| M3 Type system | [spec](specs/2026-10-14-m3-type-system-design.md) | M3a: [plan](plans/2026-10-14-m3a-schema-core.md); M3b: [plan](plans/2026-10-14-m3b-schema-validation.md) | M3a and M3b merged into `main` locally (not pushed); M3 is complete; next is M4 (operation validation) |
| M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
| Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | implemented on its branch (not merged): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |

**Decisions (2026-10-14):**
- Layer order is diagnostics < language < protocol < schema < validation; the
  spec's arrow `protocol ← diagnostics, language` means protocol depends on
  diagnostics and language.
- `JsonValue` is a sealed class family, not an extension type (an extension
  type cannot be sealed or matched with `is`).
- `Source`, `SourceLocation` and `SourceSpan` live in `diagnostics/`.
- `analysis_options.yaml` is adapted from typed_openapi's, not verbatim.
- The client's web (dart2js, dart2wasm) test runs are deferred to M11.

## How a stage is done

The superpowers skills: `brainstorming`, `writing-plans`,
`subagent-driven-development`.

1. **Design.** Ask the user one question at a time, each with a recommended
   option, in Ukrainian. Write the stage spec in English under
   `docs/superpowers/specs/` and commit it on main.
2. **Plan.** An Opus agent writes the plan from the spec. Every code block is
   checked in a scratch workspace before it goes into the plan. Bring the
   plan's open questions to the user, then commit the plan on main.
3. **Implement.** Create a worktree from main on a branch such as
   `feat/m2-language`. For each task, one fresh Sonnet implementer, then a
   Sonnet reviewer of that task. One implementer at a time.
4. **Final review.** An Opus review of the whole branch, one fix round, and a
   scoped re-review. Residuals go into `docs/roadmap.md` with a reason.
5. **Merge.** `git merge --no-ff` into main, re-run every suite on the merged
   tree, remove the worktree and the branch, update this file.

## Open for publishing (M16)

- Every publishable pubspec's `repository` points at its package folder
  (`https://github.com/4akloon/graphql_dart/tree/main/packages/<pkg>`), so
  pub.dev can rewrite relative README links once the repository is verified.
  What pub.dev checks for verification is still open: confirm it before
  publishing ([discovery.md](../discovery.md), "Repository verification").
- After publishing, search pub.dev and the web for each query and record the
  results in the release PR ([discovery.md](../discovery.md), "After a
  release").
- Chrome runs (dart2js/dart2wasm) cannot launch under the 8 GB `ulimit`; CI covers them.

## Open items

M3b is complete and merged into `main` locally (not pushed). Left open by the M3a reviews, M3b's scope or the M3b reviews; M3b resolved the CSV conversion, spec section 7, the spans of references, `fromIntrospection` and the typed locations.

- **`ScalarCodec<Object>`** covariance: a wrongly typed `encode` is a
  `TypeError`, not an `ArgumentError` (M5).
- **`maxErrors`** of a build cannot be lowered in a test: `SchemaBuilder` and
  `BuildReport` expose no limit.
- **Parser recursion.** `Parser` recurses on nested values, so a raised
  `maxDepth` (about 1000) or `null` can overflow the stack on deeply nested
  object values; the default 128 is safe. Make object-value parsing iterative
  or cap `maxDepth` (M2 follow-up).
- **Conformance in Chrome.** `typed_graphql_conformance/test/support_test.dart`
  uses `dart:io` without `@TestOn('vm')`; the package is not web-targeted and CI
  runs only the core in Chrome. Annotate it or keep the package VM-only.
- **Hostile-input tests measure time, not memory.** They use `Stopwatch`
  limits (synchronous code cannot be interrupted by a `Timeout`); a memory
  regression shows only as a slow run. Measure RSS in a VM-only test if one
  appears.
- **Introspection reader limits.** An `ofType` chain deeper than 100 wrappers
  is `GQL155` (the most `IntrospectionQuery(typeDepth: 100)` can ask); directive
  deprecation in a result is ignored (working-draft, see the Introspection
  guide); a result that redefines a built-in directive has it dropped.
- **Directive reference cycles with repeated names.** A cycle is judged per
  directive name (the first definition is the node).

## Rules the user set

- **Outward actions need the user's explicit yes:** pushing to GitHub, tags,
  publishing to pub.dev, creating issues or PRs. `dart pub publish` runs only
  with `--dry-run`.
- **Models.** Sonnet for implementers and reviewers, never Haiku. Opus for
  designs, plans and final reviews.
- **Language.** Talk with the user in Ukrainian. Everything in the repository
  is English.
- **Code quality.** `CLAUDE.md` is binding. The ratchet in `test/quality/`
  holds files in `lib/` to 300 lines, test files to 500, methods to 40.
  Allowlists start empty and never grow. No `// ignore:` anywhere.
- **Style references.** typed_openapi for code rules and process documents,
  basalt for user documentation (README skeleton, `doc/*.md` guides,
  CHANGELOG format).

## Repository

- Remote: https://github.com/4akloon/graphql_dart (`main`).
- CI: `.github/workflows/ci.yml` (format and analyze; tests on 3.13.0 and
  stable on Linux, stable on macOS and Windows; AOT; the core in Chrome with
  dart2js and dart2wasm; publish dry-run).
- `reference/` is git-ignored; `tool/fetch_reference.sh` fetches it.
