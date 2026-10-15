/// The values of `__TypeKind` (September2025 4.2.1).
enum TypeKind(
  /// The name in the schema.
  final String spelling,
) {
  /// `SCALAR`.
  scalar('SCALAR'),

  /// `OBJECT`.
  object('OBJECT'),

  /// `INTERFACE`.
  interface('INTERFACE'),

  /// `UNION`.
  union('UNION'),

  /// `ENUM`.
  enumeration('ENUM'),

  /// `INPUT_OBJECT`.
  inputObject('INPUT_OBJECT'),

  /// `LIST`.
  list('LIST'),

  /// `NON_NULL`.
  nonNull('NON_NULL'),
}
