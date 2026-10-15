# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- The README says the package is under construction: it checks a project and
  does not generate code yet.
- `CodegenConfig.parse` reads `typed_graphql.yaml` (R7.1) into a
  `ConfigResult`; its problems are `GQL500` (YAML syntax) and `GQL501`.
- `SchemaLoader.load` reads the schema file (SDL, or an introspection result
  from a `.json` path) into a `ValidSchema`; a file that is not JSON or not a
  JSON object is `GQL502`.
- `ClientGenerator.check` validates the schema, the scalar mappings and the
  documents of a project (`GQL503`-`GQL506`); `ClientGenerator.rules` are the
  specified rules without the unused-fragment and lone-anonymous rules, plus
  named operations and no `@defer`/`@stream`.
- `ProjectFile`: a file of the project, its path and text; the engine reads
  only given files.
- The Client Code Generation guide covers the configuration keys, checking a
  project and the codes `GQL500`-`GQL506`; the `codegen` dartdoc category.
- A `.graphql` file with no tokens adds nothing instead of failing the project; stricter checks of `schema`, paths and `headers` (all `GQL501`).
- `ClientGenerator.generate` returns a `GenerationResult` (`GeneratedFile`s and
  diagnostics) and writes the schema-types library at `schema_types`: the
  enums and input objects the documents use, with `@oneOf` inputs as sealed
  classes; `check` is `generate(...).diagnostics`.
- `GQL507` (a Dart name declared twice) and `GQL508` (a generated name that
  hides a Dart type the generated code uses) are reported before any file is
  written.
- Golden cases in `test/goldens/` and an analysis test that analyzes and runs
  the generated code in a temporary package (tag `analysis`).
