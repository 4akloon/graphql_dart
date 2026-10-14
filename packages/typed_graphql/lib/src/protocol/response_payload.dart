import 'decode_result.dart';
import 'graphql_error.dart';
import 'json_field_reader.dart';
import 'json_value.dart';

/// The body of a GraphQL response (spec §7.1, "Response Format"): an
/// [ExecutionResult] when the operation ran, a [RequestErrorResult] when
/// it did not.
///
/// It is the payload on the wire. The client's `GraphQLResponse` is a
/// different, typed thing built from it.
///
/// {@category protocol}
sealed class ResponsePayload({
  List<GraphQLError> errors = const [],

  /// Extra data for the client, such as tracing; null when there is none.
  final JsonObject? extensions,
}) {
  /// Creates a payload; [errors] is copied.
  this;

  /// The errors, in the order they were raised.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  /// Reads a payload from [json]: with a `data` key it is an
  /// [ExecutionResult], without one a [RequestErrorResult].
  static DecodeResult<ResponsePayload> decode(JsonValue json) => switch (json) {
    JsonObject(:final fields) when fields.containsKey('data') =>
      ExecutionResult._decode(JsonFieldReader(json)),
    JsonObject() => RequestErrorResult._decode(JsonFieldReader(json)),
    _ => const DecodeFailure('expected an object'),
  };

  /// This payload as JSON: `errors` first, as spec §7.1 suggests.
  JsonObject toJson();

  /// [errors] as a JSON array.
  JsonArray get _errorsJson =>
      JsonArray([for (final error in errors) error.toJson()]);
}

/// The result of running an operation: [data], and the [errors] raised on
/// the way (partial data when both are there).
///
/// {@category protocol}
final class ExecutionResult(
  /// The data; null when an error left none (`"data": null`).
  final JsonObject? data, {
  super.errors,
  super.extensions,
}) extends ResponsePayload {
  /// Creates an execution result.
  this;

  @override
  JsonObject toJson() => JsonObject({
    if (errors.isNotEmpty) 'errors': _errorsJson,
    'data': data ?? const JsonNull(),
    'extensions': ?extensions,
  });

  @override
  bool operator ==(Object other) =>
      other is ExecutionResult && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'ExecutionResult(${toJson()})';

  static DecodeResult<ResponsePayload> _decode(JsonFieldReader fields) =>
      switch ((
        fields.optionalObject('data'),
        fields.optionalList('errors', GraphQLError.decode),
        fields.optionalObject('extensions'),
      )) {
        (
          DecodeSuccess(value: final data),
          DecodeSuccess(value: final errors),
          DecodeSuccess(value: final extensions),
        ) =>
          DecodeSuccess(
            ExecutionResult(
              data,
              errors: errors ?? const [],
              extensions: extensions,
            ),
          ),
        (final DecodeFailure failure, _, _) ||
        (_, final DecodeFailure failure, _) ||
        (_, _, final DecodeFailure failure) => failure,
      };
}

/// A request that failed before the operation ran, such as a syntax or
/// validation error: no `data`, at least one error.
///
/// {@category protocol}
final class RequestErrorResult({required super.errors, super.extensions})
    extends ResponsePayload {
  /// Creates a request error result; an empty [errors] is an
  /// [ArgumentError].
  this {
    if (errors.isEmpty) {
      throw ArgumentError.value(errors, 'errors', 'is empty');
    }
  }

  @override
  JsonObject toJson() =>
      JsonObject({'errors': _errorsJson, 'extensions': ?extensions});

  @override
  bool operator ==(Object other) =>
      other is RequestErrorResult && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'RequestErrorResult(${toJson()})';

  static DecodeResult<ResponsePayload> _decode(JsonFieldReader fields) =>
      switch ((
        fields.optionalList('errors', GraphQLError.decode),
        fields.optionalObject('extensions'),
      )) {
        (
          DecodeSuccess(value: final errors?),
          DecodeSuccess(value: final extensions),
        )
            when errors.isNotEmpty =>
          DecodeSuccess(
            RequestErrorResult(errors: errors, extensions: extensions),
          ),
        (final DecodeFailure failure, _) ||
        (_, final DecodeFailure failure) => failure,
        _ => const DecodeFailure(
          'expected "data", or a non-empty "errors" when "data" is absent',
        ),
      };
}
