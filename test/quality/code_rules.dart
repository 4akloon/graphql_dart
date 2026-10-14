import 'blanked_code.dart';
import 'declaration_scanner.dart';
import 'nesting_meter.dart';

/// The code rules of `CLAUDE.md` ("Code rules") that a test can check,
/// applied to one Dart file of the workspace.
///
/// [violations] are the rules that allow no exception. [oversizedFile]
/// and [longMethods] are measurements: the size ratchet compares them with
/// an allowlist. Paths may use `\` (Windows) or `/`.
final class CodeRules {
  /// Creates the rules.
  const CodeRules();

  /// The most lines a file in `lib/` (or `bin/`) may have.
  static const int libFileLimit = 300;

  /// The most lines a file in `test/` (or `tool/`) may have.
  static const int testFileLimit = 500;

  /// The most lines a method, getter, operator or constructor in `lib/`
  /// may have, signature and closing bracket included.
  static const int methodLimit = 40;

  /// The most parameters a method in `lib/` may take; constructors are
  /// exempt.
  static const int parameterLimit = 5;

  /// The most control blocks that may nest.
  static const int nestingLimit = 3;

  static final RegExp _part = RegExp(r'^part\b');
  static final RegExp _dynamic = RegExp(r'\bdynamic\b');
  static final RegExp _catch = RegExp(r'\bcatch\s*\(');
  static final RegExp _catchWithOn = RegExp(
    r'\bon\s+[\w$<>?,. ]+\s+catch\s*\(',
  );
  static final RegExp _grabBag = RegExp(
    r'(?:^|_)(?:utils?|helpers?|common|misc)(?:_|\.dart$|$)',
  );
  static final RegExp _sealedRoot = RegExp(r'\bsealed\s+(?:class|mixin)\b');

  /// The violations of the rules that allow no exception, each as
  /// `path:line: what is wrong`.
  List<String> violations(String path, String content) {
    final file = _File(path, content);
    return [
      ..._lineRules(file),
      ..._nesting(file),
      for (final function in file.scanner.functions)
        if (function.name != 'main')
          '${file.path}:${function.lineNumber}: the top-level function '
              '${function.name}; put it in a class',
      if (file.isLib) ..._libRules(file),
    ];
  }

  /// The number of lines of the file at [path], as `wc -l` counts them,
  /// when it is over its limit; null when it is within it.
  int? oversizedFile(String path, String content) {
    final file = _File(path, content);
    final lines = '\n'.allMatches(content).length;
    return lines > (file.isLib ? libFileLimit : testFileLimit) ? lines : null;
  }

  /// The methods of a file in `lib/` over [methodLimit], keyed by
  /// `path#Type.member`, with their number of lines.
  Map<String, int> longMethods(String path, String content) {
    final file = _File(path, content);
    if (!file.isLib) {
      return const {};
    }
    return {
      for (final member in file.scanner.members)
        if (member.isCallable && member.length > methodLimit)
          '${file.path}#${member.name}': member.length,
    };
  }

  List<String> _lineRules(_File file) => [
    for (var i = 0; i < file.code.lines.length; i++)
      ...switch (file.code.lines[i]) {
        final line when _part.hasMatch(line) => [
          '${file.path}:${i + 1}: a part directive; split into libraries',
        ],
        final line when _dynamic.hasMatch(line) => [
          '${file.path}:${i + 1}: dynamic; use Object? or a real type',
        ],
        final line when _catch.hasMatch(line) && !_catchWithOn.hasMatch(line) =>
          ['${file.path}:${i + 1}: a catch without on; name the exception'],
        _ => const <String>[],
      },
  ];

  List<String> _nesting(_File file) => [
    for (final line in NestingMeter(file.code).linesDeeperThan(nestingLimit))
      '${file.path}:${line + 1}: control blocks nest deeper than '
          '$nestingLimit; return early or extract a method',
  ];

  List<String> _libRules(_File file) => [
    if (file.pathInPackage.any(_grabBag.hasMatch))
      '${file.path}:1: a utils or helpers file; name it after what it does',
    for (final member in file.scanner.members)
      if (member.isCallable &&
          !member.isConstructor &&
          member.parameterCount > parameterLimit)
        '${file.path}:${member.lineNumber}: ${member.name} takes '
            '${member.parameterCount} parameters, over $parameterLimit; '
            'take a parameter object',
    ?_publicTypes(file),
  ];

  /// The violation of "one public class or sealed family per file", or
  /// null when the file keeps it.
  String? _publicTypes(_File file) {
    final public = [
      for (final type in file.scanner.types)
        if (!type.type.name.startsWith('_')) type,
    ];
    final roots = [
      for (final type in public)
        if (_sealedRoot.hasMatch(type.header)) type.type.name,
    ];
    final families = [
      for (final type in public)
        if (!roots.any(
          (root) => RegExp(
            '\\b(?:extends|implements|with)\\b[^{;]*\\b$root\\b',
          ).hasMatch(type.header),
        ))
          type.type.name,
    ];
    return families.length <= 1
        ? null
        : '${file.path}:1: ${families.join(', ')} are separate public types; '
              'keep one public class or sealed family per file';
  }
}

/// One file being checked: its path with `/` separators and its code.
final class _File(String path, final String content) {
  final String path = path.replaceAll(r'\', '/');

  // `late`: the size rules count lines without blanking, and only some
  // rules need the declarations.
  late final BlankedCode code = BlankedCode(content);
  late final DeclarationScanner scanner = DeclarationScanner(code);

  static const Set<String> _sourceFolders = {'lib', 'bin', 'test', 'tool'};

  /// The folders and the file name from the source folder (`lib`, `bin`,
  /// `test` or `tool`) down, the source folder first.
  List<String> get pathInPackage => path
      .split('/')
      .skipWhile((folder) => !_sourceFolders.contains(folder))
      .toList();

  /// Whether the file is library code (`lib/` or `bin/`) rather than a
  /// test or a tool.
  bool get isLib => switch (pathInPackage) {
    ['test' || 'tool', ...] => false,
    _ => true,
  };
}
