import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import '../../protocol/path_segment.dart';

/// One object of an introspection result, read member by member; every
/// problem is reported into [sink] with the JSON path, never thrown.
///
/// A message is the path as JSONPath and graphql-js's message, as a
/// [DecodeFailure] writes it: `$.__schema.types[0]: Introspection result
/// missing fields.` An object keeps only its [parent] and the [steps] from
/// it, so a deep `ofType` chain costs linear memory; the path is built
/// only for a report.
final class IntrospectionObject(
  /// The object.
  final JsonObject json,

  /// Where problems are reported.
  final DiagnosticSink sink, {

  /// The object [json] is inside; null for `__schema`.
  final IntrospectionObject? parent,

  /// The keys and indexes from [parent] (or the root) to [json].
  final List<PathSegment> steps = const [],
}) {
  /// Creates a reader of [json].
  this;

  /// The keys and indexes from the root of the result to [json].
  List<PathSegment> get path {
    final reversed = <PathSegment>[];
    for (IntrospectionObject? at = this; at != null; at = at.parent) {
      reversed.addAll(at.steps.reversed);
    }
    return reversed.reversed.toList();
  }

  /// The string at [key]; null, after a report, when it is absent, null
  /// or not a string. [what] names the member in graphql-js's message.
  String? string(String key, {String? what}) => switch (json[key]) {
    null || JsonNull() => _missing(what ?? key),
    JsonString(:final value) => value,
    _ => _malformed(key, 'expected a string'),
  };

  /// The string at [key]; null when it is absent or null, and, after a
  /// report, when it is not a string.
  String? optionalString(String key) => switch (json[key]) {
    null || JsonNull() => null,
    JsonString(:final value) => value,
    _ => _malformed(key, 'expected a string'),
  };

  /// The boolean at [key]; false when it is absent or null, and, after a
  /// report, when it is not a boolean.
  bool flag(String key) => switch (json[key]) {
    null || JsonNull() => false,
    JsonBool(:final value) => value,
    _ => _malformed<bool>(key, 'expected a boolean') ?? false,
  };

  /// The object at [key]; null when it is absent or null, and, after a
  /// report, when it is not an object.
  IntrospectionObject? optionalObject(String key) => switch (json[key]) {
    null || JsonNull() => null,
    final JsonObject value => IntrospectionObject(
      value,
      sink,
      parent: this,
      steps: [PathKey(key)],
    ),
    _ => _malformed(key, 'expected an object'),
  };

  /// The objects of the array at [key]; null, after a report, when it is
  /// absent, null or not an array. An item that is not an object is
  /// reported and left out. [what] names the member in graphql-js's
  /// message.
  List<IntrospectionObject>? list(String key, {String? what}) {
    if (json[key] case null || JsonNull()) {
      return _missing(what ?? key);
    }
    return optionalList(key);
  }

  /// The objects of the array at [key], as [list] reads them; null when it
  /// is absent or null.
  List<IntrospectionObject>? optionalList(String key) {
    final items = switch (json[key]) {
      null || JsonNull() => null,
      JsonArray(:final items) => items,
      _ => _malformed<List<JsonValue>>(key, 'expected an array'),
    };
    if (items == null) {
      return null;
    }
    final objects = <IntrospectionObject>[];
    for (final (index, item) in items.indexed) {
      final steps = [PathKey(key), PathIndex(index)];
      if (item case final JsonObject object) {
        objects.add(
          IntrospectionObject(object, sink, parent: this, steps: steps),
        );
      } else {
        report(
          .malformedIntrospectionMember,
          'expected an object',
          inside: steps,
        );
      }
    }
    return objects;
  }

  /// The strings of the array at [key], each with its index; null, after
  /// a report, when it is absent, null or not an array. An item that is
  /// not a string is reported and left out. [what] names the member in
  /// graphql-js's message.
  List<(int, String)>? strings(String key, {String? what}) {
    final items = switch (json[key]) {
      null || JsonNull() => _missing<List<JsonValue>>(what ?? key),
      JsonArray(:final items) => items,
      _ => _malformed<List<JsonValue>>(key, 'expected an array'),
    };
    if (items == null) {
      return null;
    }
    final strings = <(int, String)>[];
    for (final (index, item) in items.indexed) {
      if (item case JsonString(:final value)) {
        strings.add((index, value));
      } else {
        report(
          .malformedIntrospectionMember,
          'expected a string',
          inside: [PathKey(key), PathIndex(index)],
        );
      }
    }
    return strings;
  }

  /// Reports [message] with [code] at this object, or [inside] it.
  void report(
    DiagnosticCode code,
    String message, {
    List<PathSegment> inside = const [],
  }) {
    final where = [...path, ...inside];
    final text = DecodeFailure(message, path: where).toString();
    sink.report(Diagnostic(code, .error, text));
  }

  // Each returns null, so a reader can report and give no value in one
  // step.
  T? _missing<T>(String what) {
    report(.missingIntrospectionMember, 'Introspection result missing $what.');
    return null;
  }

  T? _malformed<T>(String key, String message) {
    report(.malformedIntrospectionMember, message, inside: [PathKey(key)]);
    return null;
  }
}
