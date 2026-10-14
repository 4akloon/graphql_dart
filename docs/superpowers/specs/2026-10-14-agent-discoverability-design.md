# Agent discoverability: design

Status: approved by the owner 2026-10-14 (open points decided in section 9). Not part of a numbered stage; it refines
R11.1 (READMEs) and adds a small process around it. It never overrides the
[architecture](2026-10-13-typed-graphql-design.md).

## 1. Goal and scope

An AI coding agent in a project that does **not** use `typed_graphql` is given
a task such as "parse this GraphQL query in Dart". It should find the library
through pub.dev search and web search, choose it over a hand-written solution,
and see what to copy.

Decisions taken with the owner (2026-10-14):

- Nothing is published, so there is no patch release and no registry search to
  check yet. The work is **prepared now and goes into the first release
  (0.0.1, stage M16)**. Post-publish checking is a step of M16 (section 8).
- "Process only, no recipes yet": this stage builds the metadata, the README
  opening with a "Should I use this?" block, `llms.txt` and a link checker.
  The recipe format (compiled example + page-equals-file test) is **not built**
  and not populated; it is left for the stages that add capability.
- Audience: agents in projects that do not use the library. AGENTS.md or skills
  for existing users, MCP servers, registries and external posts are out.

Scope by package:

| Package | Treatment |
|---|---|
| `typed_graphql` | full: metadata, README opening, "Should I use this?", queries |
| `typed_graphql_server`, `_shelf`, `_client`, `_codegen`, `_builder` | skeletons today: `repository` fixed, README status banner kept, **no** discovery claims; they join the query list when their stage lands |
| `typed_graphql_conformance` | `publish_to: none`; excluded everywhere |

The rule that governs every sentence: **say only what works today.** An agent
that follows a README to a feature that does not exist is worse off than one
that finds nothing. The README names what is missing and its stage.

## 2. Search queries

Written for what the core does today. A query is added to this list in the
stage that makes it true.

1. parse GraphQL query dart
2. print or format a GraphQL document dart
3. GraphQL syntax error line column dart
4. GraphQL AST visitor transform dart
5. build GraphQL schema from SDL dart
6. print GraphQL schema SDL dart
7. decode GraphQL response errors dart
8. GraphQL request response JSON types dart
9. validate a GraphQL schema dart
10. GraphQL introspection query schema dart

Not yet targeted, because they do not work yet: validate an operation (M4),
execute (M5), serve (M7), generate a client (M10). The
queries live in `docs/discovery.md` (section 7) with the stage that unlocks
each.

## 3. Metadata (pub.dev rules, as the test checks them)

The limits below are pub.dev's rules as the metadata test checks them; the
[dart.dev pubspec reference](https://dart.dev/tools/pub/pubspec) does not
state the topic rules, so their source is not confirmed on that page.

- `description`: plain text, no markdown, 60 to 180 characters. Start with a
  verb and the platform. Proposal for `typed_graphql` (check the length in the
  test, not by eye):
  *Parses, prints and builds GraphQL documents and schemas in pure Dart for the
  VM, web and Wasm, with error-resilient diagnostics and wire-protocol types.*
- `topics`: at most 5; each 2 to 32 characters, lowercase `a-z`, `0-9`, `-`,
  starting with a letter, ending alphanumeric, no consecutive hyphens.
  Proposal: `graphql`, `parser`, `ast`, `sdl`, `schema`.
- `repository`: for a monorepo, the package folder, so that pub.dev can
  rewrite relative links and images:
  `https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql`
  (the form the pub-dev maintainers give in
  [dart-lang/pub-dev#5068](https://github.com/dart-lang/pub-dev/issues/5068)).
  This works only with **repository verification** (pub.dev verifies the
  repository; the steps are unconfirmed, see the open check below). The generated API reference does not
  rewrite relative links, so doc comments keep using none (already a rule from
  M3c).
- `issue_tracker` stays; images and badges use absolute URLs.
- Pub points ask for an example and documented API: both exist since M3c.

Open check for the plan: the exact verification steps pub.dev wants are not on
the pages I could fetch. The plan has a task to confirm them against pub.dev's
own help before the release, and the link checker (section 6) does not depend
on them.

## 4. README

For `typed_graphql`:

- **Opening sentence**: the task in the words of the queries, e.g. "Parse,
  print and transform GraphQL queries and SDL in Dart, and build a schema from
  SDL, with every syntax error reported once, with its line and column." It
  keeps the status banner directly under it.
- **Install**, then a block **"Should I use this?"** right after:
  - *Use it when* you need to parse, print, rewrite or inspect GraphQL text, or
    build a schema from SDL, in Dart (VM, web or Wasm), and want errors as
    values with stable codes and places.
  - *You do not need it when* you only send a query string to a server and read
    the JSON back; and, today, when you need to validate an operation or
    execute (those arrive in M4 and M5). Schema validation, introspection and
    coordinate resolution work today (M3b).
  - *What it replaces*: matching GraphQL text with regular expressions or string
    splitting, and reading responses as `Map<String, dynamic>`. The concrete
    faults: a regular expression does not see comments, block strings or nested
    selections, and fails silently on them; a dynamic map reads `errors` and
    `path` without checking their shape, so a wrong field is a runtime cast
    error far from the cause.
  - *Which package*: this one is the core with no dependencies but `meta`; the
    server and client packages build on it and are not usable yet.
- Approaches are compared, packages are not: no third-party package is named,
  ranked or judged anywhere.
- Every claim in the block is backed by a guide section or a test: the plan
  links each sentence to the guide that shows it.

The other packages keep their README; a one-line "not usable yet" under the
status banner is checked by the test in section 6.

## 5. `llms.txt`

At the repository root, in the [llmstxt.org](https://llmstxt.org) shape: one H1
(`typed_graphql`), a blockquote summary paragraph, then H2 sections of links
with a one-line description each: *Packages* (with status), *Guides*
(`packages/typed_graphql/doc/*.md`), *Reference* (roadmap, requirements).
Absolute URLs only, of the form
`https://github.com/4akloon/graphql_dart/blob/main/<path>`. A test maps each URL
back to a repository path and requires that the file exists (offline; the URL
prefix is a constant of the test). Pub.dev package URLs are added at M16.

## 6. Tests

All offline, in the workspace suite (`test/discovery/`, run by the root
`dart test`), one thing per test:

- Metadata, for every package without `publish_to: none`: description length in
  60..180, no markdown characters; topics match the rules; `repository` equals
  `https://github.com/4akloon/graphql_dart/tree/main/packages/<name>`;
  `issue_tracker` present.
- README of `typed_graphql`: the first paragraph contains "Dart" and "GraphQL";
  the "Should I use this?" heading comes after "Install" and before the next
  heading's content; each of its four labels is present. Skeleton READMEs carry
  the "not usable yet" line.
- `llms.txt`: one H1, one blockquote, only absolute links, every link maps to an
  existing file.
- Links: the M3c link checker (`test/doc/markdown_links.dart`) is extended to
  the root README, `docs/discovery.md` and every package README; relative links
  must resolve, anchors must exist. The checker is shared, not copied; if
  importing across packages is awkward the plan moves it to the workspace
  `test/` support folder and the package suite imports it from there.

Size and style limits of `CLAUDE.md` apply to the test code.

## 7. `docs/discovery.md`

A short maintainers' page (English): the query list with the stage that unlocks
each query; the rules of section 3; how to re-check after a release (section 8);
the sentence rule "say only what works today". Linked from the roadmap's rules
for plans and from `CONTRIBUTING.md`.

## 8. Release and verification

- Changes are metadata and documentation only. They are part of 0.0.1, which is
  unreleased, so each changed package gets one line in its existing
  `## 0.0.1 - Unreleased` CHANGELOG section (the repository URL changes in all
  six publishable packages).
- Nothing is pushed, tagged or published without the owner's explicit yes.
  `dart pub publish` only with `--dry-run`; the dry run is part of the stage's
  final check.
- At M16, after publishing (owner's go): search pub.dev and the web for each
  query, write the results into the release PR description, and promise no
  ranking in any document.

## 9. Decisions on the open points

Taken 2026-10-14 when the owner answered "do everything" to the review request,
adopting the recommendations:

1. Skeleton packages keep their descriptions; only the `repository` fix and the
   "not usable yet" line change.
2. `docs/roadmap.md` gets the rule "a stage that adds a capability adds its
   query to `docs/discovery.md`, its README line and its `llms.txt` entry" next
   to the M3c documentation rule. The plan includes it.
3. Recipes stay deferred; the first stage that should bring them is M5
   (execution), when "serve GraphQL in Dart" becomes true.
