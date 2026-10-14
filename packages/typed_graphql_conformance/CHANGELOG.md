# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- Depends on `typed_graphql` only.
- `mapping/language.csv`, the conformance mapping table, and the test that
  checks it.
- Ported graphql-js suites: `lexer-test.ts`, `blockString-test.ts`,
  `parser-test.ts`, `schema-parser-test.ts`, `printer-test.ts`,
  `schema-printer-test.ts`, `printString-test.ts`, `visitor-test.ts`,
  `schemaCoordinateLexer-test.ts`, `printLocation-test.ts`, `source-test.ts`,
  `predicates-test.ts`, `kind-test.ts`, `diagnostics-test.ts`.
- Round-trip fuzzer (R10.4): random documents and schema coordinates,
  printed canonical and minified, parse back to equivalent trees;
  `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` tune it.
