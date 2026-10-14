# M1 plan checkpoint

Date: 2026-10-13. Plan file: `2026-10-13-m1-foundations.md`. Status: **complete and verified**. The plan is no longer a draft, and no task carries a DRAFT marker. This file can be deleted once the plan is committed.

## Where the work is

Scratch (not needed any more):
`/tmp/claude-1000/-home-genius-projects-graphql-dart/2f656142-4c63-42bb-bdf9-1a11d9d5842c/scratchpad/`

- `ws/` is the trial workspace.
- `plan/` holds the template and `assemble.py`, which inserts the verified files into the plan, and `replay.py`.
- `replay/` is a clone of main with all 14 tasks applied and committed locally. It was never pushed.

## Tasks

All 14 tasks are written in full and verified:

- **Replay.** The plan was replayed from a clean clone of `main`. Every Create/Replace block and bash block was applied and each task was committed locally. After every task the green check passed: format, `analyze --fatal-infos`, the root suite, and every package's tests.
- **Test counts.** The root suite went 8 → 17 → 34 tests. The core went 2 → 9 → 28 → 44 → 65 → 79 → 99 → 118.
- **Final tree.** It is identical to the trial workspace, file for file.
- **On the replay tree:**
  - exe runs pass;
  - Chrome runs pass with dart2js and with dart2wasm (109 tests each);
  - all six dry-runs report 0 warnings, both at the Task 1 commit and at the end;
  - the README examples print what the READMEs claim;
  - both ratchets fail on injected violations.

Nothing is still to run. What could not be run here: CI on exactly 3.13.0 (3.13.1 was used), macOS and Windows, and `actionlint`.

## Design decisions and findings

These are in the plan, in the sections "M1 design decisions" and "Spec deviations and findings". Findings 1–4 and 8 need the user's decision:

1. `JsonValue` is a sealed class family, not an extension type.
2. The layer-arrow reading.
3. `Source` lives in `diagnostics/`.
4. The verbatim `analysis_options.yaml` has typed_openapi comments and leaves out the 3.12/3.13 lints.
5. (Finding 8) R10.5 web runs for the client are deferred to M11.
