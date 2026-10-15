import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

/// The completed values of an object's fields or a list's items, some of
/// them still pending (R4.9).
///
/// A value is a [JsonValue], Dart `null` (a failure that propagates) or a
/// `Future` of one of those. A `Future` here never fails: errors are handled
/// where they happen. With no pending value the result is built at once;
/// with one it chains `then`; with several it waits for all of them once.
final class PendingValues {
  final List<FutureOr<JsonValue?>> _values = [];

  /// How many values were added.
  int get length => _values.length;

  /// Adds the next value.
  void add(FutureOr<JsonValue?> value) => _values.add(value);

  /// [build] applied to the values once every one has completed, or null
  /// when any of them is a propagating failure.
  FutureOr<R?> finishWith<R extends JsonValue>(
    R Function(List<JsonValue> values) build,
  ) {
    final positions = <int>[];
    final futures = <Future<JsonValue?>>[];
    for (var i = 0; i < _values.length; i++) {
      if (_values[i] case final Future<JsonValue?> future) {
        positions.add(i);
        futures.add(future);
      }
    }
    if (futures.isEmpty) {
      return _build(build);
    }
    if (futures.length == 1) {
      return futures.first.then((value) {
        _values[positions.first] = value;
        return _build(build);
      });
    }
    return Future.wait(futures).then((results) {
      for (var i = 0; i < results.length; i++) {
        _values[positions[i]] = results[i];
      }
      return _build(build);
    });
  }

  /// Null once every pending value has completed: the result of a
  /// propagating failure, which still lets started work finish so that the
  /// errors it records are in the response.
  FutureOr<R?> abandon<R extends JsonValue>() {
    final futures = <Future<JsonValue?>>[
      for (final value in _values)
        if (value is Future<JsonValue?>) value,
    ];
    if (futures.isEmpty) {
      return null;
    }
    return Future.wait(futures).then<R?>((_) => null);
  }

  R? _build<R extends JsonValue>(R Function(List<JsonValue> values) build) {
    final values = <JsonValue>[];
    for (final value in _values) {
      if (value == null) {
        return null;
      }
      values.add(value as JsonValue);
    }
    return build(values);
  }
}
