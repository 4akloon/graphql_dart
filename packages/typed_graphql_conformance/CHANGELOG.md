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
  `predicates-test.ts`, `kind-test.ts`, `diagnostics-test.ts`,
  `blockString-fuzz.ts`; the mapping test requires rows for every graphql-js
  language test file.
- Round-trip fuzzer (R10.4): random documents and schema coordinates,
  printed canonical and minified, parse back to equivalent trees;
  `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` tune it.
- Hostile-text fuzzer (R1.6, R10.4): random and mutated text through every
  parser entry point stays within the sink limit, and every diagnostic has
  a source excerpt.
- `mapping/schema.csv`, the conformance table of the schema suites, checked
  by the same mapping test; `SchemaPort`, the port helpers. Ported
  graphql-js schema suites: `printSchema-test.ts`, `buildASTSchema-test.ts`,
  `extendSchema-test.ts`.
- SDL round-trip fuzzer (R10.4): random schemas printed as SDL build back
  to the same elements and print the same text.
- Hostile-SDL fuzzer (R10.4): random and mutated type-system text, built
  and used to extend a schema, stays within the sink limit, reaches every
  build diagnostic and never throws.
- Ported graphql-js `validation-test.ts` (schema validation), with
  `ValidationPort`: each error as its message and `line:column` locations,
  compared with graphql-js's; template-named tests become loops.
- The build and extend ports check `validateSchema` where graphql-js does
  (`SchemaPort.validate`, `validationErrors`); SDL validation is the
  validator's: an unknown directive is `GQL117`, an unknown type `GQL116`.
- Ported graphql-js `getIntrospectionQuery-test.ts`; each query is parsed,
  since operation validation arrives in M4.
- Ported graphql-js `introspectionFromSchema-test.ts`; the schemas are
  written as SDL.
