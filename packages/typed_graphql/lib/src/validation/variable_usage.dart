import '../language/ast/type_ref.dart';
import '../language/ast/value.dart';

/// A variable used as a value, with the input type expected where it
/// stands, as graphql-js's `VariableUsage`.
///
/// {@category validation}
final class VariableUsage(
  /// The variable, `$name`.
  final Variable node,

  /// The input type of the position; null where the document names an
  /// argument or field the schema does not have.
  final TypeRef? type, {

  /// The list or input object type that holds the position, if any.
  final TypeRef? parentType,

  /// The default value of the argument or input field at the position;
  /// null in a list and where there is none.
  final Value? defaultValue,
}) {
  /// Creates a usage.
  this;
}
