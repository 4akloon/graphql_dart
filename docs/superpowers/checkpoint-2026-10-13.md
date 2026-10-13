# Checkpoint 2026-10-13

Resume point for the `typed_graphql` rewrite. M1 replaces this file with
`docs/superpowers/HANDOFF.md`; delete this one then.

## State

- Design is done and approved: [spec](specs/2026-10-13-typed-graphql-design.md),
  [requirements](../requirements.md), [roadmap](../roadmap.md),
  [research and decisions](../research/README.md). Committed on `main`; nothing pushed.
- The old graphql-java port (`lib/`, `example/`, `test/`, old `pubspec.yaml`) is still
  in the tree. M1 deletes it.
- Next artifact: the M1 plan, `docs/superpowers/plans/2026-10-13-m1-foundations.md`,
  written by an opus subagent. If the file is missing, that run was lost: dispatch it
  again (model `opus`, nothing committed by the agent, scratch work only in the
  scratchpad directory).
- M1 has no stage spec of its own. The plan carries an "M1 design decisions" section for
  what the architecture spec leaves open (`DiagnosticCode` shape, `JsonValue`
  representation, protocol type names that do not collide with the client's
  `GraphQLResponse`, the ratchet mechanism).

## How to continue

1. Read the plan once the file exists.
2. Execute it with `superpowers:subagent-driven-development` in a git worktree:
   one fresh `implementer` (model `sonnet`) per task, a `reviewer` after each,
   `opus` only for the final whole-branch review.
3. Merge the worktree branch into `main` locally when the final review is clean.
4. Stop only when a decision is needed. `git push`, publishing and opening issues
   still need an explicit yes.
5. Then write the M2 (Language) stage spec, then its plan.

## Toolchain

Dart 3.13.1 stable is installed locally. The reference specifications are fetched
into the git-ignored `reference/` by `tool/fetch_reference.sh`.
