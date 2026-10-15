/// How a request ended, the status-like part of a `ServerResponse`, which a
/// transport maps to a status of its protocol.
///
/// {@category server}
enum ServerOutcome {
  /// The operation ran; the result has `data`, which may be null after field
  /// errors, cancellation or a timeout.
  executed,

  /// The request is not executable: no query, a syntax or validation error,
  /// a limit, CSRF prevention, a persisted document problem, an operation
  /// that cannot be selected or variables that do not coerce. The result has
  /// no `data`.
  requestError,

  /// A mutation in a `GET` request.
  methodNotAllowed,

  /// An unexpected error in the pipeline itself, such as the context
  /// factory, an extension or a store; its message is masked by the profile.
  internalError,
}
