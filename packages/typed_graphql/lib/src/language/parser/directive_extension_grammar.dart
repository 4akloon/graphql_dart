import '../ast/type_system_extension.dart';
import 'definition_grammar.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';

/// The working draft's `extend directive @name Directives[Const]`. It is
/// always registered, so that with the option off the parser names the
/// feature (`GQL014`) instead of failing at `directive`.
final class DirectiveExtensionGrammar implements DefinitionGrammar {
  /// Creates the grammar; [isEnabled] mirrors
  /// `ParserOptions.allowDirectiveExtensions`.
  DirectiveExtensionGrammar(
    this.cursor,
    this.directives, {
    required this.isEnabled,
  });

  /// The token stream.
  final TokenCursor cursor;

  /// The directive productions.
  final DirectiveParser directives;

  /// Whether directive extensions are accepted.
  final bool isEnabled;

  @override
  bool startsDefinition() {
    if (!cursor.peekKeyword('extend')) {
      return false;
    }
    final keyword = cursor.lookahead();
    return keyword.kind == .name && keyword.value == 'directive';
  }

  @override
  DirectiveExtension definition() {
    final extend = cursor.token;
    cursor.expectKeyword('extend');
    cursor.expectKeyword('directive');
    if (!isEnabled) {
      // Past `directive`, so recovery does not resume at it as a definition.
      cursor.fail(
        .workingDraftFeatureDisabled,
        'Directive extensions are a working-draft feature; enable them '
        'with ParserOptions.allowDirectiveExtensions.',
        at: extend,
      );
    }
    cursor.expect(.at);
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    if (directiveList.isEmpty) {
      cursor.unexpected();
    }
    return DirectiveExtension(
      name,
      directives: directiveList,
      start: extend.start,
      end: cursor.lastEnd,
    );
  }
}
