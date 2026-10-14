import 'dart:convert';

import 'decode_result.dart';
import 'json_value.dart';
import 'path_segment.dart';

/// Reads untrusted JSON, as text or as the output of `jsonDecode`, into a
/// [JsonValue].
///
/// Bad input is a [DecodeFailure], never an exception: text that is not
/// JSON, a number too large to be finite (`1e400`), a map key that is not a
/// string, a Dart object that is not JSON, and arrays and objects nested
/// deeper than [maxDepth]. A key repeated in one object keeps its last
/// value, as `jsonDecode` and JavaScript's `JSON.parse` do.
///
/// {@category protocol}
final class JsonReader {
  /// Creates a reader that accepts at most [maxDepth] arrays and objects
  /// nested in one another.
  ///
  /// [maxDepth] must be between 0 and [maxSupportedDepth]: a larger limit
  /// would let the recursive conversion overflow the stack, which is a
  /// programming error, so it is asserted.
  const JsonReader({this.maxDepth = defaultMaxDepth})
    : assert(
        maxDepth >= 0 && maxDepth <= maxSupportedDepth,
        'maxDepth must be between 0 and JsonReader.maxSupportedDepth',
      );

  /// The default of [maxDepth].
  static const int defaultMaxDepth = 512;

  /// The largest [maxDepth] a reader accepts; the recursive conversion is
  /// known to fit in the stack at this depth on the VM, dart2js and
  /// dart2wasm.
  static const int maxSupportedDepth = 1000;

  /// The most arrays and objects nested in one another; a scalar at the top
  /// has depth 0, `[]` has 1, `[[]]` has 2.
  final int maxDepth;

  /// Parses [text] as JSON.
  ///
  /// The nesting is measured on the text before `jsonDecode` runs, because
  /// `jsonDecode` on the web recurses once per level and would overflow
  /// the stack first.
  DecodeResult<JsonValue> parse(String text) {
    if (_NestingScanner(text).isDeeperThan(maxDepth)) {
      return _tooDeep();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      return DecodeFailure('not JSON: ${error.message}');
    }
    return read(decoded);
  }

  /// Converts [value]: the output of `jsonDecode`, or plain Dart objects
  /// (`null`, `bool`, `num`, `String`, `List`, `Map` with `String` keys).
  ///
  /// A list or map that appears several times in [value] is walked again at
  /// each appearance, so an in-process object graph with heavy sharing is
  /// expensive to read.
  DecodeResult<JsonValue> read(Object? value) => _read(value, 0);

  DecodeResult<JsonValue> _read(Object? value, int depth) => switch (value) {
    null => const DecodeSuccess(JsonNull()),
    bool() => DecodeSuccess(JsonBool(value)),
    num() when value.isFinite => DecodeSuccess(JsonNumber(value)),
    num() => DecodeFailure('$value is not a finite number'),
    String() => DecodeSuccess(JsonString(value)),
    List<Object?>() => _array(value, depth + 1),
    Map<Object?, Object?>() => _object(value, depth + 1),
    _ => const DecodeFailure('not a JSON value'),
  };

  DecodeResult<JsonValue> _array(List<Object?> list, int depth) {
    if (depth > maxDepth) {
      return _tooDeep();
    }
    final items = <JsonValue>[];
    for (var i = 0; i < list.length; i++) {
      switch (_read(list[i], depth).inside(PathIndex(i))) {
        case DecodeSuccess(:final value):
          items.add(value);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonArray(items));
  }

  DecodeResult<JsonValue> _object(Map<Object?, Object?> map, int depth) {
    if (depth > maxDepth) {
      return _tooDeep();
    }
    final fields = <String, JsonValue>{};
    for (final MapEntry(:key, :value) in map.entries) {
      if (key is! String) {
        return DecodeFailure('the key $key is not a string');
      }
      switch (_read(value, depth).inside(PathKey(key))) {
        case DecodeSuccess(:final value):
          fields[key] = value;
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonObject(fields));
  }

  DecodeFailure _tooDeep() =>
      DecodeFailure('arrays and objects are nested deeper than $maxDepth');
}

/// Measures how deeply arrays and objects nest in JSON text without
/// parsing it: brackets inside strings do not count.
final class _NestingScanner(final String text) {
  static const int _quote = 0x22;
  static const int _backslash = 0x5C;
  static const int _openBracket = 0x5B;
  static const int _closeBracket = 0x5D;
  static const int _openBrace = 0x7B;
  static const int _closeBrace = 0x7D;

  /// Whether some array or object in [text] is nested deeper than [limit].
  bool isDeeperThan(int limit) {
    var depth = 0;
    var inString = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (inString) {
        i += unit == _backslash ? 1 : 0;
        inString = unit != _quote;
        continue;
      }
      inString = unit == _quote;
      depth += _change(unit);
      if (depth > limit) {
        return true;
      }
    }
    return false;
  }

  /// How [unit] changes the depth outside a string.
  int _change(int unit) => switch (unit) {
    _openBracket || _openBrace => 1,
    _closeBracket || _closeBrace => -1,
    _ => 0,
  };
}
