# Handoff: where typed_graphql stands and how to continue

Last updated: 2026-10-14 (M1 merged into main, not pushed). Read this
first on a new device or in a new Claude session. Session memory and scratch
directories do not travel; this file and the repository hold everything
needed.

## State

| Stage | Design | Plan | Code |
|---|---|---|---|
| Architecture | [spec](specs/2026-10-13-typed-graphql-design.md), [requirements](../requirements.md), [roadmap](../roadmap.md) | — | — |
| M1 Foundations | the architecture spec (no stage spec) | [plan](plans/2026-10-13-m1-foundations.md) | done: merged into `main` locally (not pushed); next is M2 |
| M2 Language | next: write `specs/…-m2-language-design.md` | — | — |

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
