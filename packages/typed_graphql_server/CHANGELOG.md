# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- The README says the package cannot execute requests yet.
- Typed refs: `OutputRef<T>` and `InputRef<T>`, `LeafRef<T>` for scalars and
  enums, `.nullable`, `b.list` and `b.inputList`; the built-in scalars
  `b.int`, `b.float`, `b.string`, `b.boolean` and `b.id`.
- `ExecutableSchemaBuilder<C>` declares custom scalars over a core
  `ScalarCodec` (`scalar`), enums over Dart enums (`enumType`,
  `EnumValueMapping`), input objects (`inputObject`, `oneOfInputObject`),
  object types (`object`, `ObjectOptions`), interfaces and unions
  (`interface`, `union`, `resolveType`, field inheritance through listed
  interfaces).
- Typed fields in two steps: `t.field(name, type, ...)` fixes the result
  type, then `pure`, `resolve`, `resolveWith` or `declareOnly`; `deprecated`
  and `withDirectives` modify the stub. A resolver of the wrong type does
  not compile (checked by the compile-failure tests).
- Typed arguments: `Arg`, `Arg.optional` with `Optional`, `Present` and
  `Absent`, `Arguments`, `ArgumentsDef` for an arguments class.
- `ExecutableSchemaBuilder.build` assembles the declared types into a
  validated `ExecutableSchema<C>`; the builder's own checks (`GQL300`-`GQL302`)
  and the core validator report through `SchemaBuildError`. `BuildOptions`
  holds the directives, `includesDeferAndStream` and the description.
- `FieldInfo` (field name, parent type name, response path) is the last
  argument of a resolver.
- The Schema Builder and Execution guides, with the dartdoc categories
  `builder` and `execution`.
