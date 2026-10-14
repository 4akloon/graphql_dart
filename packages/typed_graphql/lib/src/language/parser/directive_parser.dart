import '../ast/argument.dart';
import '../ast/directive.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses directives and arguments (spec §2.6, §2.12).
final class DirectiveParser {
  /// Creates a parser reading from [cursor] with [values].
  DirectiveParser(this.cursor, this.values);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// `Directives[?Const]`: zero or more `@name(arguments)`.
  List<Directive> directives({required bool isConst}) {
    final directives = <Directive>[];
    while (cursor.peek(.at)) {
      directives.add(_directive(isConst: isConst));
    }
    return directives;
  }

  /// `Arguments[?Const]`: `(name: value ...)`, or none.
  List<Argument> arguments({required bool isConst}) => cursor.optionalMany(
    .parenLeft,
    () => _argument(isConst: isConst),
    .parenRight,
  );

  Directive _directive({required bool isConst}) {
    final start = cursor.token.start;
    cursor.expect(.at);
    final name = cursor.name();
    final arguments = this.arguments(isConst: isConst);
    return Directive(
      name,
      arguments: arguments,
      start: start,
      end: cursor.lastEnd,
    );
  }

  Argument _argument({required bool isConst}) {
    final start = cursor.token.start;
    final name = cursor.name();
    cursor.expect(.colon);
    final value = values.value(isConst: isConst);
    return Argument(name, value, start: start, end: cursor.lastEnd);
  }
}
