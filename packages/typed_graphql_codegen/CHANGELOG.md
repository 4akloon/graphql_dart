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
- The guide documents generation and the generated schema types (enums, input
  objects, `@oneOf`, scalars, pruning, the file header) and lists `GQL507` and
  `GQL508`.
- `ClientGenerator.generate` writes a library per document file, at the file's
  path plus `.dart`: the classes of the file's fragments (a data class with
  `decode`, `toJson`, value equality and a private codec per field, and a
  `...Fragments` holder per selection that spreads fragments) and the imports
  they need. Depends on `package:path`.
- A selection on an interface or union that tells types apart (`... on User`)
  generates a sealed class that reads `__typename`, a final class per type
  and an unknown class for any other type; fields every class selects the same
  way are declared by the sealed class.
- `ClientGenerator.generate` writes the operations of each document file, in
  document order with its fragments: the operation class (`GetUserQuery`,
  `...Mutation`, `...Subscription`) with its `operationDocument` (minified
  text of the operation and the fragments it spreads, with `__typename` added
  to every field with a selection, and its SHA-256), the variables class
  (`required` or `Optional` per variable, written only), and the data class
  with `decode(json, variables:)` and the defaults of its Boolean variables.
  Depends on `package:crypto`.
- Names are checked over operations and fragments too: classes, the members of
  every class (fields, variables, fragment accessors) and file paths, as
  `GQL507`/`GQL508`, in file and offset order. A subscription that spreads a
  fragment on an abstract type at its root is a `GQL504`.
- `persisted_operations` writes the persisted-operations manifest (ids, names,
  types and minified bodies, sorted by name) as the last generated file.
- The guide documents the generated operations and fragments: a program that
  generates a document's library, the class names, data masking, sealed
  classes for abstract types, `@include` and `@skip`, variables, the
  document text and the persisted-operations manifest, decoding, and the
  `GQL504` subscription case and `GQL507` for members and files.
