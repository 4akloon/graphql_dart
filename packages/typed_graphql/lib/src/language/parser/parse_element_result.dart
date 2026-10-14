import '../../diagnostics/diagnostic.dart';
import '../ast/node.dart';

/// The result of parsing one value or type reference:
/// [ParseElementSuccess] or [ParseElementFailure], with [diagnostics].
///
/// {@category language}
sealed class ParseElementResult<T extends Node>(List<Diagnostic> diagnostics) {
  /// Creates a result.
  this;

  /// Every diagnostic of the parse, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}

/// An element without syntax errors.
///
/// {@category language}
final class ParseElementSuccess<T extends Node>(
  /// The element.
  final T value,
  super.diagnostics,
) extends ParseElementResult<T> {
  /// Creates a success.
  this;
}

/// An element with syntax errors; there is no partial element.
///
/// {@category language}
final class ParseElementFailure<T extends Node>(super.diagnostics)
    extends ParseElementResult<T> {
  /// Creates a failure.
  this;
}
