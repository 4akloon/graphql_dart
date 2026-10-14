import '../ast/name.dart';
import '../ast/selection.dart';
import '../ast/selection_set.dart';
import 'directive_parser.dart';
import 'recovery.dart';
import 'syntax_abort.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses selection sets, fields and fragment spreads (spec §2.4–§2.8);
/// a failed selection is dropped and parsing resumes at the next one.
final class SelectionParser {
  /// Creates a parser reading from [cursor].
  SelectionParser(
    this.cursor,
    this.values,
    this.directives, {
    required this.allowsEmpty,
  }) : _recovery = Recovery(cursor);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// Whether `{ }` is accepted (working draft).
  final bool allowsEmpty;

  final Recovery _recovery;

  /// `SelectionSet`: `{ selection ... }`, one nesting level deeper.
  SelectionSet selectionSet() => cursor.nested(_selectionSet);

  /// `FragmentName`: a name other than `on`.
  Name fragmentName() {
    if (cursor.peekKeyword('on')) {
      cursor.unexpected();
    }
    return cursor.name();
  }

  SelectionSet _selectionSet() {
    final start = cursor.token.start;
    cursor.expect(.braceLeft);
    if (cursor.peek(.braceRight) && !allowsEmpty) {
      cursor.fail(.emptySelectionSet, 'Unexpected empty selection set.');
    }
    final selections = <Selection>[];
    var hasDropped = false;
    while (!cursor.expectOptional(.braceRight)) {
      if (_selectionOrSkip() case final selection?) {
        selections.add(selection);
      } else {
        hasDropped = true;
      }
    }
    if (selections.isEmpty && (!allowsEmpty || hasDropped)) {
      // Every selection failed and was reported (or empty sets are not
      // allowed); an empty set would misstate the source, so the
      // enclosing selection fails too.
      throw const SyntaxAbort();
    }
    return SelectionSet(selections, start: start, end: cursor.lastEnd);
  }

  /// A selection, or null when it failed and was skipped; at the end of
  /// the document the whole definition fails.
  Selection? _selectionOrSkip() {
    final first = cursor.token;
    final balance = cursor.balance;
    try {
      return cursor.peek(.spread) ? _fragment() : _field();
    } on SyntaxAbort catch (abort) {
      if (abort.endsDefinition || cursor.isStopped) {
        rethrow;
      }
      _recovery.skipSelection(first, balance);
      if (cursor.peek(.eof)) {
        rethrow;
      }
      return null;
    }
  }

  Field _field() {
    final start = cursor.token.start;
    final nameOrAlias = cursor.name();
    final hasAlias = cursor.expectOptional(.colon);
    final name = hasAlias ? cursor.name() : nameOrAlias;
    final arguments = directives.arguments(isConst: false);
    final directiveList = directives.directives(isConst: false);
    final selectionSet = cursor.peek(.braceLeft) ? this.selectionSet() : null;
    return Field(
      hasAlias ? nameOrAlias : null,
      name,
      arguments: arguments,
      directives: directiveList,
      selectionSet: selectionSet,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// `...Name` or `... on Type { }` (an inline fragment may omit the
  /// type condition).
  Selection _fragment() {
    final start = cursor.token.start;
    cursor.expect(.spread);
    final hasTypeCondition = cursor.expectOptionalKeyword('on');
    if (!hasTypeCondition && cursor.peek(.name)) {
      final name = fragmentName();
      final directiveList = directives.directives(isConst: false);
      return FragmentSpread(
        name,
        directives: directiveList,
        start: start,
        end: cursor.lastEnd,
      );
    }
    final typeCondition = hasTypeCondition ? values.namedType() : null;
    final directiveList = directives.directives(isConst: false);
    final selectionSet = this.selectionSet();
    return InlineFragment(
      typeCondition,
      selectionSet,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }
}
