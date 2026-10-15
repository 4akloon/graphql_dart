# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- The README says the package is not usable yet.
- `CodegenConfig.parse` reads `typed_graphql.yaml` (R7.1) into a
  `ConfigResult`; its problems are `GQL500` (YAML syntax) and `GQL501`.
- `SchemaLoader.load` reads the schema file (SDL, or an introspection result
  from a `.json` path) into a `ValidSchema`; a file that is not JSON or not a
  JSON object is `GQL502`.
- `ClientGenerator.check` validates the schema, the scalar mappings and the
  documents of a project (`GQL503`-`GQL506`); `ClientGenerator.rules` are the
  specified rules without the unused-fragment and lone-anonymous rules, plus
  named operations and no `@defer`/`@stream`.
