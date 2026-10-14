# Discovery

How an AI coding agent in a project that does not use typed_graphql finds it
through pub.dev and web search, chooses it over a hand-written solution, and
sees what to copy. This page is for maintainers; the design is the
[agent discoverability spec](superpowers/specs/2026-10-14-agent-discoverability-design.md).
The workspace suite in `test/discovery/` checks what can be checked offline.

## Say only what works today

The rule for every sentence of a README, a pubspec description and
`llms.txt`: **say only what works today.** An agent that follows a README to
a feature that does not exist is worse off than one that finds nothing. Name
what is missing and the stage that brings it. Compare approaches, never
packages: no third-party package is named, ranked or judged.

## Queries

The searches typed_graphql answers, or will. A stage that makes a query true
adds its row (or turns it to "yes") together with its README line and its
`llms.txt` entry; until then the query is not targeted anywhere.

| Query | Stage | Works today |
|---|---|---|
| parse GraphQL query dart | M2 | yes |
| print or format a GraphQL document dart | M2 | yes |
| GraphQL syntax error line column dart | M2 | yes |
| GraphQL AST visitor transform dart | M2 | yes |
| build GraphQL schema from SDL dart | M3 | yes |
| print GraphQL schema SDL dart | M3 | yes |
| decode GraphQL response errors dart | M1 | yes |
| GraphQL request response JSON types dart | M1 | yes |
| validate a GraphQL schema dart | M3 | yes |
| GraphQL introspection query schema dart | M3 | yes |
| validate a GraphQL operation dart | M4 | no |
| execute a GraphQL query dart | M5 | no |
| GraphQL server dart | M7 | no |
| generate a typed GraphQL client dart | M10 | no |

## Metadata

pub.dev searches a package's name, description, README and doc comments
([pub.dev search help](https://pub.dev/help/search)). The pubspec rules below
come from the [pubspec reference](https://dart.dev/tools/pub/pubspec) and
pub.dev's rules as `test/discovery/pubspec_metadata_test.dart` checks them;
where a rule is our convention or not confirmed, it says so:

- `description`: plain text, no markdown or HTML, 60 to 180 characters. Our
  convention, not a pub.dev rule: start with a verb and the platform.
- `topics`: at most 5; each 2 to 32 characters of `a-z`, `0-9` and `-`,
  starting with a letter, ending with a letter or digit, no `--`.
- `repository`: the package folder, written as
  `https://github.com/4akloon/graphql_dart/tree/main/packages/<name>`, so that
  pub.dev can rewrite the README's relative links and images. Not verified by
  the pages checked below (the issue
  [dart-lang/pub-dev#5068](https://github.com/dart-lang/pub-dev/issues/5068)
  was not opened); confirm at M16.
- `issue_tracker`: `https://github.com/4akloon/graphql_dart/issues`.
- Images and badges use absolute URLs; doc comments use no relative link,
  because the API reference does not rewrite them.

### Repository verification

Whether pub.dev rewrites relative links only for a verified repository, and
what it checks to verify one, is not confirmed by the pages read: an open
question. Read on 2026-10-14: [pub.dev help](https://pub.dev/help) and its
[search](https://pub.dev/help/search) page. Read on 2026-10-15: the
[publishing](https://pub.dev/help/publishing) and
[scoring](https://pub.dev/help/scoring) pages and the
[pubspec reference](https://dart.dev/tools/pub/pubspec), which says only that
`repository` "should contain the URL for your package's source code
repository". None of them describes the verification. Look again before the
release (M16) and replace this paragraph with what pub.dev says, quoted and
linked.

## README

- The core's README opens with the task in the words of the queries, then
  the status banner. Right after Install comes **Should I use this?** with
  four labels: *Use it when*, *You do not need it when*, *What it replaces*,
  *Which package*. Every claim there is shown in a guide, and the item links
  the guide section.
- A skeleton package says **Not usable yet.** right under its status banner
  and makes no other claim.
- A link that leaves the package folder is an absolute URL: pub.dev publishes
  the folder alone.

## llms.txt

`llms.txt` at the repository root has the [llmstxt.org](https://llmstxt.org)
shape: one `#` title, one `>` summary, then the sections *Packages* (each with
its README status), *Guides* (every `packages/typed_graphql/doc/*.md`) and
*Reference*. Every link is an absolute
`https://github.com/4akloon/graphql_dart/blob/main/<path>` URL to a file of
the repository. pub.dev package URLs are added at M16.

## Links

Every relative link of the root README, this page and every package README
leads to a file or folder, and an anchor to a heading; the checker is the
core documentation suite's `MarkdownLinks`.

## After a release

At M16, and after each later release, once the owner has said yes to
publishing:

1. Search pub.dev and the web for every query marked "yes".
2. Write what came up, query by query, into the release pull request's
   description.
3. Fix a README, description or `llms.txt` sentence that a result shows to
   be wrong or missing, in a follow-up change.

No document promises a ranking.
