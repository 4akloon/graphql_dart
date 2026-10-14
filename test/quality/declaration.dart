/// A declaration found by [DeclarationScanner]: a top-level type or
/// function, or a member of a type.
final class Declaration(
  /// The name: `Type`, `function`, or `Type.member` for a member (`Type.new`
  /// for an unnamed constructor, `Type.this` for the body of a primary
  /// constructor).
  final String name,

  /// The index of the first line, from 0; annotations and doc comments
  /// are not part of it.
  final int start,

  /// The index of the last line.
  final int end, {

  /// For a member, whether it is a method, getter, setter, operator or
  /// constructor rather than a field or an enum value.
  final bool isCallable = false,

  /// For a member, whether it is a constructor.
  final bool isConstructor = false,

  /// The number of parameters of a callable member; 0 for the rest.
  final int parameterCount = 0,
}) {
  /// Creates a declaration.
  this;

  /// The number of lines, both ends included.
  int get length => end - start + 1;

  /// The line number people count, from 1.
  int get lineNumber => start + 1;
}
