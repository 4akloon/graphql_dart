import '../../language/ast/value.dart';
import 'applied_directive.dart';

/// Reads an argument of an applied directive as a list of strings, as input
/// coercion does (spec §3.12.3): a bare string is a list of one.
///
/// Anything else reads as an empty list, and a non-string item is skipped:
/// schema validation reports a wrongly typed argument (`GQL124`).
final class const StringListArgument(
  /// The applied directive that holds the argument.
  final AppliedDirective directive,
) {
  /// Creates the reader.
  this;

  /// The strings of the argument [name]; empty when it is absent.
  List<String> named(String name) => switch (directive.argument(name)) {
    ListValue(:final values) => [
      for (final value in values)
        if (value case StringValue(:final value)) value,
    ],
    StringValue(:final value) => [value],
    _ => const [],
  };
}
