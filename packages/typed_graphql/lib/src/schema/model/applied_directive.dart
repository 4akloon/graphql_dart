import '../../diagnostics/source_span.dart';
import '../../language/ast/argument.dart';
import '../../language/ast/value.dart';

/// A directive applied to a schema element, `@name(arguments)`, as the SDL
/// wrote it (spec §3.13).
///
/// The arguments are constant language [Value] nodes; nothing checks them
/// against the directive's definition here (that is schema validation).
///
/// {@category schema}
final class AppliedDirective(
  /// The directive name, without the `@`.
  final String name, {
  List<Argument> arguments = const [],

  /// Where the directive was written; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates an applied directive.
  this;

  /// The arguments, in the order they were written.
  final List<Argument> arguments = List.unmodifiable(arguments);

  /// The value of the first argument named [name]; null when there is none.
  Value? argument(String name) {
    for (final argument in arguments) {
      if (argument.name.value == name) {
        return argument.value;
      }
    }
    return null;
  }
}
