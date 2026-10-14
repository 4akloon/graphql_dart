# typed_graphql_conformance

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-tool-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**Repository tool of typed_graphql: ported graphql-js suites, fuzzers and benchmarks. Never published.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** Stage M2 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)
> ports the graphql-js language suites; nothing is exported.

## Ported suites

Tests under `test/language/` are ported from graphql-js 17
(`reference/graphql-js`, fetched by `tool/fetch_reference.sh`), one Dart test
per graphql-js test, with the same group and test names.
`mapping/language.csv` records each graphql-js test:

| Column | Meaning |
|---|---|
| `graphql_js_file` | the file in `src/language/__tests__/`, such as `lexer-test.ts` |
| `group` | the `describe` blocks around the test, joined by ` > ` |
| `test` | the `it` name |
| `status` | `ported` (same assertions), `adapted` (a deliberate design difference changes them) or `skipped` (behaviour this library does not have) |
| `dart_file` | the Dart test file, relative to this package; empty when skipped |
| `reason` | why, for `adapted` and `skipped` |

`test/mapping_test.dart` checks the table; with `reference/` fetched it also
checks that every test of a ported file has a row.

## Fuzzing

`test/fuzz/` holds the fuzzers of R10.4. They run with the other tests, a
fixed number of cases from a fixed seed; set the environment to run more or
other cases:

```sh
TYPED_GRAPHQL_FUZZ_ITERATIONS=100000 TYPED_GRAPHQL_FUZZ_SEED=7 dart test test/fuzz
```

A failure names its case and the `Random` seed that replays it.
`round_trip_fuzz_test.dart` prints random documents and coordinates and
parses them back; `hostile_text_fuzz_test.dart` feeds random and mutated
text to every parser entry point and checks that it reports, within the
sink limit, and never throws.

## License

MIT — see [LICENSE](LICENSE). The ported tests derive from graphql-js,
MIT, Copyright (c) GraphQL Contributors — see
[LICENSE-graphql-js](LICENSE-graphql-js).
