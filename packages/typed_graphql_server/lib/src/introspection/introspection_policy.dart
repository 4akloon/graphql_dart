/// Whether an execution answers `__schema` and `__type`.
///
/// `__typename` is answered either way: it describes the response, not the
/// schema.
///
/// {@category introspection}
enum IntrospectionPolicy {
  /// `__schema` and `__type` are answered (September2025 4.2).
  enabled,

  /// `__schema` and `__type` are field errors (`GQL338`), each with a null
  /// value.
  disabled,
}
