/// A value of a generated enum: a known value or an unknown one, both with
/// the GraphQL name (R7.6).
///
/// {@category operations}
abstract interface class DataEnum {
  /// The value's name in GraphQL, such as `ADMIN`.
  String get raw;
}
