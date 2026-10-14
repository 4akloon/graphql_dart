import '../diagnostics/source_location.dart';
import 'decode_result.dart';
import 'json_field_reader.dart';
import 'json_value.dart';
import 'path_segment.dart';

/// An error of a GraphQL response, in the format of spec §7.1.2 ("Errors").
///
/// Both sides use it: a server writes it with [toJson], a client reads it
/// with [decode]. Two errors are equal when their JSON is equal.
///
/// {@category protocol}
final class GraphQLError(
  /// What went wrong, for the developer reading it.
  final String message, {
  List<SourceLocation> locations = const [],
  List<PathSegment>? path,

  /// Extra data the server attached, such as an error code; null when the
  /// error has none.
  final JsonObject? extensions,
}) {
  /// Creates an error; the lists are copied.
  this;

  /// The places in the document the error is about; empty when it is
  /// about none.
  final List<SourceLocation> locations = List.unmodifiable(locations);

  /// The response path of the field the error is about: response names
  /// and list indexes from the root of `data`. Null when the error is not
  /// about a field.
  final List<PathSegment>? path = path == null ? null : List.unmodifiable(path);

  /// Reads an error from [json]; a missing or mistyped `message`,
  /// `locations`, `path` or `extensions` is a failure, other keys are
  /// ignored.
  static DecodeResult<GraphQLError> decode(JsonValue json) {
    if (json is! JsonObject) {
      return const DecodeFailure('expected an object');
    }
    final fields = JsonFieldReader(json);
    return switch ((
      fields.string('message'),
      fields.optionalList('locations', _location),
      fields.optionalList('path', _segment),
      fields.optionalObject('extensions'),
    )) {
      (
        DecodeSuccess(value: final message),
        DecodeSuccess(value: final locations),
        DecodeSuccess(value: final path),
        DecodeSuccess(value: final extensions),
      ) =>
        DecodeSuccess(
          GraphQLError(
            message,
            locations: locations ?? const [],
            path: path,
            extensions: extensions,
          ),
        ),
      (final DecodeFailure failure, _, _, _) ||
      (_, final DecodeFailure failure, _, _) ||
      (_, _, final DecodeFailure failure, _) ||
      (_, _, _, final DecodeFailure failure) => failure,
    };
  }

  /// This error as JSON: `message` first, then `locations` when there are
  /// any, `path` and `extensions` when they are set.
  JsonObject toJson() => JsonObject({
    'message': JsonString(message),
    if (locations.isNotEmpty)
      'locations': JsonArray([
        for (final SourceLocation(:line, :column) in locations)
          JsonObject({'line': JsonNumber(line), 'column': JsonNumber(column)}),
      ]),
    if (path case final path?)
      'path': JsonArray([
        for (final segment in path)
          switch (segment) {
            PathKey(:final name) => JsonString(name),
            PathIndex(:final index) => JsonNumber(index),
          },
      ]),
    'extensions': ?extensions,
  });

  @override
  bool operator ==(Object other) =>
      other is GraphQLError && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'GraphQLError(${toJson()})';

  /// One entry of `locations`: `{"line": 1, "column": 2}`, both 1 or more.
  static DecodeResult<SourceLocation> _location(JsonValue json) =>
      switch (json) {
        JsonObject(
          fields: {
            'line': JsonNumber(asInt: final int line),
            'column': JsonNumber(asInt: final int column),
          },
        )
            when line >= 1 && column >= 1 =>
          DecodeSuccess(SourceLocation(line, column)),
        _ => const DecodeFailure(
          'expected {"line": n, "column": n} with whole numbers from 1',
        ),
      };

  /// One entry of `path`: a response name or a list index.
  static DecodeResult<PathSegment> _segment(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(PathKey(value)),
    JsonNumber(asInt: final int index) when index >= 0 => DecodeSuccess(
      PathIndex(index),
    ),
    _ => const DecodeFailure('expected a string or an index from 0'),
  };
}
