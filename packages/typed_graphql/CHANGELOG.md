# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`. Diagnostics compare by value.
- `JsonValue`, a sealed family for arbitrary JSON; `PathSegment` and
  `DecodeResult`.
- `JsonReader`: JSON text to `JsonValue`, with a nesting limit and no
  exceptions.
- `GraphQLError`: the error format of the spec, read and written.
- `GraphQLRequest` and `ResponsePayload` (`ExecutionResult`,
  `RequestErrorResult`).
- The syntax tree: `Node` (`children`, `withChildren`, `isEquivalentTo`),
  `Name`, `Document`, and the `Value` and `TypeRef` families.
- Executable nodes: `OperationDefinition`, `FragmentDefinition`, the
  `Selection` family, `SelectionSet`, `VariableDefinition`, `Argument`,
  `Directive`.
- Type system nodes: the `TypeSystemDefinition` and `TypeSystemExtension`
  families (with `TypeDefinition` and `TypeExtension`), field, input value,
  enum value and root operation type definitions.
