/// How serious a diagnostic is.
///
/// {@category diagnostics}
enum DiagnosticSeverity {
  /// The input is invalid: a result that carries one is a failure.
  error,

  /// The input is valid but suspicious, such as a use of a deprecated
  /// field; a success may carry warnings.
  warning,
}
