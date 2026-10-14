import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/ast/value.dart';
import '../../language/printer/printer.dart';

/// Prints a value for a message, as long as it is short.
///
/// graphql-js prints the whole value in every message about it. A message
/// about an object that is repeated for each of its fields, at each level
/// of nesting, would then cost the size of the value times the number of
/// messages, so a value larger than [maxSize] prints as its brackets
/// with `...` inside. This is a deviation from graphql-js, recorded in the
/// M3 design (§13, deviation 14).
final class const BoundedValuePrinter() {
  /// Creates the printer; it keeps no state.
  this;

  /// The size above which a value is not printed: the number of nodes plus
  /// the characters of their names and text.
  static const int maxSize = 1000;

  static const Printer _printer = Printer();

  /// [value] as the language printer prints it; its brackets with `...`
  /// when it is larger than [maxSize].
  String print(Value value) =>
      _isSmall(value) ? _printer.print(value) : _omitted(value);

  static String _omitted(Value value) => switch (value) {
    ObjectValue() => '{ ... }',
    ListValue() => '[ ... ]',
    _ => '...',
  };

  // A walk with its own stack that stops as soon as the budget is spent,
  // so it costs at most maxSize however large the value is.
  bool _isSmall(Value value) {
    var budget = maxSize;
    final pending = <Node>[value];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      budget -= 1 + _textLength(node);
      if (budget < 0) {
        return false;
      }
      pending.addAll(node.children);
    }
    return true;
  }

  static int _textLength(Node node) => switch (node) {
    Name(:final value) ||
    IntValue(:final value) ||
    FloatValue(:final value) ||
    StringValue(:final value) ||
    EnumValue(:final value) => value.length,
    _ => 0,
  };
}
