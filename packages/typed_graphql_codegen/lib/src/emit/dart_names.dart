/// Turns GraphQL names into Dart identifiers.
///
/// GraphQL names cannot contain `$`, so a `$` added here never collides with
/// another GraphQL name.
///
/// {@category codegen}
final class DartNames {
  /// Creates the name converter.
  const DartNames();

  /// Members every generated data or input class has.
  static const Set<String> objectMembers = <String>{
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    'toJson',
    'codec',
    'decode',
    'fragments',
    // Prefixes of the imports the instance members use.
    'client',
    'graphql',
  };

  /// Members every generated enum has, including those of `Enum`.
  static const Set<String> enumMembers = <String>{
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    'values',
    'index',
    'name',
    'raw',
    'codec',
    'parse',
  };

  static const Set<String> _reservedWords = <String>{
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  /// A class name from a GraphQL type, operation or fragment name.
  String typeName(String name) {
    final (String prefix, String rest) = _splitUnderscores(name);
    if (!rest.contains('_')) {
      return '$prefix${_upperFirst(rest)}';
    }
    final StringBuffer out = StringBuffer(prefix);
    for (final String part in _parts(rest)) {
      out.write(
        _isUpperCase(part) && part.length > 1
            ? _titleCase(part)
            : _upperFirst(part),
      );
    }
    return out.toString();
  }

  /// A field, variable, argument or enum value name.
  ///
  /// A reserved word or a member in [reservedMembers] gets a `$` suffix.
  String memberName(String name, {Set<String> reservedMembers = const {}}) {
    if (name == '__typename') {
      return 'typename';
    }
    final (String prefix, String rest) = _splitUnderscores(name);
    final List<String> parts = _parts(rest);
    final StringBuffer out = StringBuffer(prefix);
    if (parts.isNotEmpty) {
      out.write(_firstPart(parts.first));
      for (final String part in parts.skip(1)) {
        out.write(_isUpperCase(part) ? _titleCase(part) : _upperFirst(part));
      }
    }
    final String result = out.toString();
    if (_reservedWords.contains(result) || reservedMembers.contains(result)) {
      return '$result\$';
    }
    return result;
  }

  /// [memberName] with its first character upper-cased, `$` kept.
  String capitalized(String memberName) => _upperFirst(memberName);

  String _firstPart(String part) {
    if (_isUpperCase(part)) {
      return part.toLowerCase();
    }
    return '${part[0].toLowerCase()}${part.substring(1)}';
  }

  (String, String) _splitUnderscores(String name) {
    int count = 0;
    while (count < name.length && name[count] == '_') {
      count++;
    }
    return (r'$' * count, name.substring(count));
  }

  List<String> _parts(String rest) =>
      rest.split('_').where((part) => part.isNotEmpty).toList();

  bool _isUpperCase(String part) {
    for (final int unit in part.codeUnits) {
      final bool isUpper = unit >= 0x41 && unit <= 0x5a;
      final bool isDigit = unit >= 0x30 && unit <= 0x39;
      if (!isUpper && !isDigit) {
        return false;
      }
    }
    return part.isNotEmpty;
  }

  String _titleCase(String part) =>
      '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';

  String _upperFirst(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
