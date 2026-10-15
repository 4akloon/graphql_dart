/// What the executor does when a field fails (spec 6, the `onError`
/// proposal).
///
/// {@category execution}
enum ErrorBehavior {
  /// A field error makes the field null; at a non-null position the null
  /// propagates to the nearest nullable parent (September2025 section
  /// 6.4.4). This is the specified behaviour.
  propagate,

  /// A field error makes the field null and stops there, even when the
  /// field is non-null: nothing propagates.
  nullValue,

  /// The first error ends the execution: the response has `data: null` and
  /// that error only.
  halt,
}
