# Handoff: where typed_graphql stands and how to continue

Last updated: 2026-10-14 (M3a merged into `main` locally, not pushed). Read this
first on a new device or in a new Claude session. Session memory and scratch
directories do not travel; this file and the repository hold everything
needed.

## State

| Stage | Design | Plan | Code |
|---|---|---|---|
| Architecture | [spec](specs/2026-10-13-typed-graphql-design.md), [requirements](../requirements.md), [roadmap](../roadmap.md) | — | — |
| M1 Foundations | the architecture spec (no stage spec) | [plan](plans/2026-10-13-m1-foundations.md) | done: merged into `main` locally (not pushed); next is M2 |
| M2 Language | [spec](specs/2026-10-14-m2-language-design.md) | M2a: [plan](plans/2026-10-14-m2a-language-core.md); M2b: [plan](plans/2026-10-14-m2b-language-tools.md) | M2a and M2b merged into `main` locally (M2a pushed, M2b not); M2 is complete; next is M3 (schema) |
| M3 Type system | [spec](specs/2026-10-14-m3-type-system-design.md) | M3a: [plan](plans/2026-10-14-m3a-schema-core.md) | M3a merged into `main` locally (not pushed); next is the M3b plan (validation, introspection) |

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

## Open for M3b

Found by the M3a reviews.

- **CSV conversion.** Every row of `mapping/schema.csv` whose reason says
  validation arrives in M3b (23 rows) must gain the `validateSchema`
  assertion: `ValidSchema` normally, `InvalidSchema` for "allows extension of
  interface with missing Object fields" and "allows extension of union by
  adding itself". Both "Allows to disable SDL validation" rows are adapted tests
  already (an unknown directive builds); M3b adds the `ValidSchema.assumeValid`
  link. "Throws on unknown types" (x2) and
  "Rejects invalid SDL" (x2) assert real `GQL1xx` codes.
- **Spec section 7** must list "applied directive must be defined" and
  "referenced type must exist" explicitly.
- **Spans of references added by `extend`.** An interface or union member
  added by an extension from another `Source` is a bare `NamedType` whose
  offsets belong to the extension's source, while the type's span belongs to
  the base. Decide: store a span next to each reference, or point the
  diagnostic at the type.
- **`fromIntrospection`** returns the sealed `BuildResult`, but spec section 8
  also says `DecodeFailure`: reconcile.
- **`locations`** of `SchemaDirective` is `List<String>`: decide a typed
  location for M4.
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
