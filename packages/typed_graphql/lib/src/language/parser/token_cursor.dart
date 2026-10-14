import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source_span.dart';
import '../ast/name.dart';
import '../lexer/lexer.dart';
import '../lexer/token.dart';
import '../lexer/token_kind.dart';
import 'syntax_abort.dart';

/// The parser's view of the token stream: the current token, one token of
/// lookahead, the expectations of graphql-js's parser and the way a
/// syntax error is reported.
///
/// A failure reports one diagnostic and throws a [SyntaxAbort]. It stays
/// silent at an error token, which the lexer reported, at an offset that
/// already has a diagnostic, and once [isStopped].
final class TokenCursor {
  /// Creates a cursor over [lexer] that reports into [sink].
  TokenCursor(this.lexer, this.sink, {this.maxDepth})
    : _token = lexer.advance();

  /// The token source.
  final Lexer lexer;

  /// Where syntax errors go.
  final DiagnosticSink sink;

  /// The deepest [nested] call allowed; null for no limit.
  final int? maxDepth;

  Token _token;
  Token? _lookahead;
  int _lastEnd = 0;
  int _balance = 0;
  int _depth = 0;
  final Set<int> _reportedOffsets = {};

  /// The current token, not consumed yet.
  Token get token => _token;

  /// The end of the last consumed token: the end of the node being built.
  int get lastEnd => _lastEnd;

  /// Opening minus closing brackets, braces and parentheses consumed; the
  /// recovery uses it to stay at the level where the error happened.
  int get balance => _balance;

  /// Whether parsing must stop: the token limit or the sink's limit was
  /// reached.
  bool get isStopped => lexer.isLimitReached || sink.isFull;

  /// The token after [token], read without consuming [token].
  Token lookahead() => _lookahead ??= lexer.advance();

  /// Consumes [token].
  void advance() {
    _lastEnd = _token.end;
    _balance += switch (_token.kind) {
      .braceLeft || .bracketLeft || .parenLeft => 1,
      .braceRight || .bracketRight || .parenRight => -1,
      _ => 0,
    };
    _token = _lookahead ?? lexer.advance();
    _lookahead = null;
  }

  /// Whether [token] is of [kind].
  bool peek(TokenKind kind) => _token.kind == kind;

  /// Whether [token] is the name [word].
  bool peekKeyword(String word) => _token.kind == .name && _token.value == word;

  /// Consumes and returns [token] when it is of [kind]; fails otherwise.
  Token expect(TokenKind kind) {
    final token = _token;
    if (token.kind != kind) {
      final found = token.description;
      fail(.expectedToken, 'Expected ${kind.description}, found $found.');
    }
    advance();
    return token;
  }

  /// Consumes [token] when it is of [kind], and says whether it did.
  bool expectOptional(TokenKind kind) {
    if (_token.kind != kind) {
      return false;
    }
    advance();
    return true;
  }

  /// Consumes the keyword [word]; fails when [token] is another token.
  void expectKeyword(String word) {
    if (!expectOptionalKeyword(word)) {
      final found = _token.description;
      fail(.expectedToken, 'Expected "$word", found $found.');
    }
  }

  /// Consumes [token] when it is the keyword [word], and says whether it
  /// did.
  bool expectOptionalKeyword(String word) {
    if (!peekKeyword(word)) {
      return false;
    }
    advance();
    return true;
  }

  /// Consumes a name token and returns it as a [Name] node.
  Name name() {
    final token = _token;
    if (token case Token(kind: .name, :final value?)) {
      advance();
      return Name(value, start: token.start, end: token.end);
    }
    fail(.expectedToken, 'Expected Name, found ${token.description}.');
  }

  /// [open], one or more items, [close]: graphql-js's `many`.
  List<T> many<T>(TokenKind open, T Function() item, TokenKind close) {
    expect(open);
    final items = [item()];
    while (!expectOptional(close)) {
      items.add(item());
    }
    return items;
  }

  /// [many] when [token] is [open], or no items.
  List<T> optionalMany<T>(TokenKind open, T Function() item, TokenKind close) =>
      peek(open) ? many(open, item, close) : <T>[];

  /// [open], zero or more items, [close]: graphql-js's `any`.
  List<T> any<T>(TokenKind open, T Function() item, TokenKind close) {
    expect(open);
    final items = <T>[];
    while (!expectOptional(close)) {
      items.add(item());
    }
    return items;
  }

  /// One or more items separated by [delimiter], which may also lead.
  List<T> delimitedMany<T>(TokenKind delimiter, T Function() item) {
    expectOptional(delimiter);
    final items = [item()];
    while (expectOptional(delimiter)) {
      items.add(item());
    }
    return items;
  }

  /// Fails with `Unexpected <token>.` at [at], or at [token].
  Never unexpected([Token? at]) {
    final token = at ?? _token;
    fail(.unexpectedToken, 'Unexpected ${token.description}.', at: token);
  }

  /// Reports [message] with [code] at [at], or at [token], and throws a
  /// [SyntaxAbort].
  Never fail(
    DiagnosticCode code,
    String message, {
    Token? at,
    bool endsDefinition = false,
  }) {
    final token = at ?? _token;
    final isSilent = token.kind == .error || isStopped;
    if (!isSilent && _reportedOffsets.add(token.start)) {
      final span = SourceSpan(lexer.source, token.start, token.end);
      sink.report(Diagnostic(code, .error, message, span: span));
    }
    throw SyntaxAbort(endsDefinition: endsDefinition);
  }

  /// Runs [parse] one nesting level deeper; fails when that passes
  /// [maxDepth], dropping the whole definition (R1.6).
  T nested<T>(T Function() parse) {
    final limit = maxDepth;
    if (limit != null && _depth >= limit) {
      fail(
        .depthLimitExceeded,
        'Document nests deeper than $limit levels.',
        endsDefinition: true,
      );
    }
    _depth++;
    try {
      return parse();
    } finally {
      _depth--;
    }
  }
}
