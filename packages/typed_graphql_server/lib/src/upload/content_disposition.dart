import 'package:meta/meta.dart';

/// The `content-disposition` header of one part of a `multipart/form-data`
/// body (RFC 7578 section 4.2): the field name and, for a file, its name.
///
/// Only `name` and `filename` are read. `filename*` (RFC 8187) is ignored, so
/// the name a browser sends in `filename` is the one used.
@internal
final class ContentDisposition {
  const ContentDisposition._(this.name, this.filename);

  /// Reads [header], or returns null when it is absent, is not `form-data`,
  /// has no `name` or is malformed.
  static ContentDisposition? parse(String? header) {
    if (header == null) return null;
    final scanner = _Scanner(header);
    if (scanner.readUntilSemicolon().toLowerCase() != 'form-data') return null;
    String? name;
    String? filename;
    while (scanner.skipSemicolon()) {
      final parameter = scanner.readParameter();
      if (parameter == null) return null;
      switch (parameter) {
        case ('name', final value):
          name ??= value;
        case ('filename', final value):
          filename ??= value;
        case _:
      }
    }
    return name == null ? null : ContentDisposition._(name, filename);
  }

  /// The field name.
  final String name;

  /// The file name the client gave, or null for a field that is not a file.
  final String? filename;
}

/// A cursor over the text of the header.
final class _Scanner {
  _Scanner(this._text);

  final String _text;
  int _position = 0;

  bool skipSemicolon() {
    if (_position >= _text.length || _text[_position] != ';') return false;
    _position++;
    return true;
  }

  String readUntilSemicolon() {
    final start = _position;
    while (_position < _text.length && _text[_position] != ';') {
      _position++;
    }
    return _text.substring(start, _position).trim();
  }

  /// The next `name=value` pair with a lower-case name, `('', '')` for a
  /// parameter without a value, or null when the value is malformed.
  (String, String)? readParameter() {
    final start = _position;
    while (_position < _text.length &&
        _text[_position] != '=' &&
        _text[_position] != ';') {
      _position++;
    }
    final name = _text.substring(start, _position).trim().toLowerCase();
    if (_position >= _text.length || _text[_position] == ';') return ('', '');
    _position++;
    final value = _readValue();
    return value == null ? null : (name, value);
  }

  String? _readValue() {
    while (_position < _text.length && _text[_position] == ' ') {
      _position++;
    }
    if (_position >= _text.length || _text[_position] != '"') {
      return readUntilSemicolon();
    }
    final value = _readQuoted();
    if (value == null) return null;
    while (_position < _text.length && _text[_position] == ' ') {
      _position++;
    }
    return _position < _text.length && _text[_position] != ';' ? null : value;
  }

  String? _readQuoted() {
    final value = StringBuffer();
    _position++;
    while (_position < _text.length) {
      final character = _text[_position++];
      if (character == '"') return value.toString();
      if (character == r'\' && _position < _text.length) {
        value.write(_text[_position++]);
      } else {
        value.write(character);
      }
    }
    return null;
  }
}
