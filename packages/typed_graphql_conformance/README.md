# typed_graphql_conformance

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-tool-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**Repository tool of typed_graphql: ported graphql-js suites, fuzzers and benchmarks. Never published.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** Stage M2 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)
> ports every graphql-js language suite and adds the language fuzzers;
> M3a ports the graphql-js schema builder, extension and printer suites
> and adds the SDL fuzzers. Nothing is exported.

## Ported suites

Tests under `test/language/` and `test/schema/` are ported from graphql-js
17 (`reference/graphql-js`, fetched by `tool/fetch_reference.sh`), one Dart
test per graphql-js test, with the same group and test names.
`mapping/language.csv` and `mapping/schema.csv` record each graphql-js test:

| Column | Meaning |
|---|---|
| `graphql_js_file` | the file: in `src/language/__tests__/` for `language.csv`, such as `lexer-test.ts`; in `src/` for `schema.csv`, such as `utilities/__tests__/printSchema-test.ts` |
| `group` | the `describe` blocks around the test, joined by ` > ` |
| `test` | the `it` name |
| `status` | `ported` (same assertions), `adapted` (a deliberate design difference changes them) or `skipped` (behaviour this library does not have) |
| `dart_file` | the Dart test file, relative to this package; empty when skipped |
| `reason` | why, for `adapted` and `skipped` |

`test/mapping_test.dart` checks the tables; with `reference/` fetched it also
checks that every test of every graphql-js language test file, and of each
graphql-js schema test file the stage ports, has a row.

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
sink limit, and never throws. `schema_round_trip_fuzz_test.dart` prints
random schemas as SDL and builds them back: the rebuilt schema holds the
same elements (`SchemaDump`) and prints the same text;
`hostile_sdl_fuzz_test.dart` builds random and mutated type-system text,
and extends a schema with it, and checks that the builder reports every
kind of problem, within the sink limit, and never throws.
`valid_operation_fuzz_test.dart` builds random operations that are valid by
construction over random valid schemas (`RandomValidSchema`,
`RandomOperation`) and checks that every specified rule accepts them;
`hostile_operation_fuzz_test.dart` validates random and mutated documents
with every rule and limit on and checks that the result is bounded and
never throws; `hostile_shape_fuzz_test.dart` validates documents of hostile
shapes (deep, wide, exponentially expanding, cyclic) and checks that each
run ends within ten seconds and that exponential merging gives `GQL230`.

## License

MIT — see [LICENSE](LICENSE). The ported tests derive from graphql-js,
MIT, Copyright (c) GraphQL Contributors — see
[LICENSE-graphql-js](LICENSE-graphql-js).
