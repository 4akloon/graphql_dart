# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`.
- `JsonValue`, a sealed family for arbitrary JSON; `PathSegment` and
  `DecodeResult`.
- `JsonReader`: JSON text to `JsonValue`, with a nesting limit and no
  exceptions.
