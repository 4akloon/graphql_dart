import 'blanked_code.dart';
import 'declaration.dart';
import 'signature.dart';

/// Finds the declarations of a formatted Dart library by its brackets.
///
/// A type starts on a line in the first column with `class`, `mixin`,
/// `enum`, `extension` or `typedef`; its body is the first `{` outside
/// brackets after that. A member starts on a line inside the body where
/// exactly one bracket is open and the indent is two spaces, and ends
/// before the next such line;
/// annotations and doc comments are not part of it. False negatives are
/// accepted, a false positive is a bug of this class.
final class DeclarationScanner(final BlankedCode code) {
  static final RegExp _typeHeader = RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
    r'(class|mixin|enum|extension\s+type|extension|typedef)\s+'
    r'(?:const\s+)?([A-Za-z_$][\w$]*)',
  );

  static final RegExp _directive = RegExp(
    r'^(?:import|export|part|library)\b',
  );

  // `late`: computed once, on the first use of [types] or [members].
  late final List<_TypeSpan> _spans = [
    for (var i = 0; i < code.lines.length; i++)
      if (_typeHeader.firstMatch(code.lines[i]) case final header?)
        _spanOf(header, i),
  ];

  /// The top-level types, in file order, each with the header text up to
  /// its body.
  List<({Declaration type, String header})> get types => [
    for (final span in _spans)
      (
        type: Declaration(span.name, span.start, span.close ?? span.open),
        header: code.lines.sublist(span.start, span.open + 1).join('\n'),
      ),
  ];

  /// The members of every type, in file order; the values of an enum are
  /// not members.
  List<Declaration> get members => [
    for (final span in _spans) ..._membersOf(span),
  ];

  /// The top-level functions, getters and setters, in file order.
  List<Declaration> get functions => [
    for (var i = 0; i < code.lines.length; i++)
      if (_functionAt(i) case final name?) Declaration(name, i, i),
  ];

  /// The span of the type whose [header] is on line [start].
  _TypeSpan _spanOf(RegExpMatch header, int start) {
    final name = header[2]!;
    final isEnum = header[1] == 'enum';
    int? open;
    var depth = 0;
    for (final (line, unit) in code.unitsFrom(start)) {
      if (open == null && depth == 0 && unit == ';') {
        return _TypeSpan(name, start, line, null, isEnum: isEnum);
      }
      if (open == null && depth == 0 && unit == '{') {
        open = line;
      }
      depth += BlankedCode.bracketBalance(unit);
      if (open != null && depth == 0) {
        return _TypeSpan(name, start, open, line, isEnum: isEnum);
      }
    }
    return _TypeSpan(name, start, open ?? start, null, isEnum: isEnum);
  }

  List<Declaration> _membersOf(_TypeSpan span) {
    final close = span.close;
    if (close == null) {
      return const [];
    }
    final starts = [
      for (var i = _firstMemberLine(span); i < close; i++)
        if (_isMemberLevel(i)) i,
    ];
    return [
      for (var n = 0; n < starts.length; n++)
        if (!code.lines[starts[n]].trimLeft().startsWith('@'))
          _member(
            span.name,
            starts[n],
            _lastCodeLine(
              starts[n],
              n + 1 < starts.length ? starts[n + 1] : close,
            ),
          ),
    ];
  }

  /// The first line of [span]'s body after its enum values, if any.
  int _firstMemberLine(_TypeSpan span) {
    if (!span.isEnum) {
      return span.open + 1;
    }
    for (var i = span.open; i < (span.close ?? span.open); i++) {
      if (code.lines[i].trimRight().endsWith(';') && code.depths[i + 1] == 1) {
        return i + 1;
      }
    }
    return span.close ?? span.open;
  }

  /// Whether a member starts on [line]: one bracket is open, the line is
  /// indented by two spaces as `dart format` indents members, and it does
  /// not close a bracket.
  bool _isMemberLevel(int line) {
    final text = code.lines[line];
    return code.depths[line] == 1 &&
        text.startsWith('  ') &&
        !text.startsWith(RegExp(r'   |  [)\]}]')) &&
        text.trim().isNotEmpty;
  }

  /// The last line before [next] that has code.
  int _lastCodeLine(int start, int next) {
    var end = next - 1;
    while (end > start && code.lines[end].trim().isEmpty) {
      end--;
    }
    return end;
  }

  Declaration _member(String type, int start, int end) {
    final signature = Signature(code.lines.sublist(start, end + 1).join('\n'));
    final name = signature.name;
    final isConstructor =
        name == type ||
        name == 'this' ||
        name.startsWith('$type.') ||
        code.lines[start].trimLeft().startsWith('factory ');
    final member = name == type ? 'new' : name.replaceFirst('$type.', '');
    return Declaration(
      '$type.$member',
      start,
      end,
      isCallable: signature.isCallable,
      isConstructor: isConstructor,
      parameterCount: signature.parameterCount,
    );
  }

  /// The name of the top-level function that starts on line [index], or
  /// null when none does.
  String? _functionAt(int index) {
    final line = code.lines[index];
    if (code.depths[index] != 0 ||
        line.trim().isEmpty ||
        line.startsWith(RegExp(r'[\s@)\]}]')) ||
        _directive.hasMatch(line) ||
        _typeHeader.hasMatch(line)) {
      return null;
    }
    final signature = Signature(line);
    return signature.isCallable ? signature.name : null;
  }
}

/// Where a type sits: its header starts on [start], its body opens on
/// [open] and closes on [close] (null without a body).
final class _TypeSpan(
  final String name,
  final int start,
  final int open,
  final int? close, {
  required final bool isEnum,
});
