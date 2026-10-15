import 'package:typed_graphql/typed_graphql.dart';

/// Equality of the values of generated classes: lists item by item and
/// present [Optional]s by their values, at any depth (R7.3: equal data
/// compares equal, so a cache update that yields equal data rebuilds
/// nothing).
///
/// Generated `==` and `hashCode` use it for every member whose type holds a
/// list; other members compare with `==`.
///
/// {@category operations}
final class const DataEquality() {
  /// Creates the equality.
  this;

  /// Whether [a] and [b] are equal: lists item by item, present optionals
  /// by their values, anything else with `==`.
  bool equals(Object? a, Object? b) => switch ((a, b)) {
    (final List<Object?> a, final List<Object?> b) => _equalLists(a, b),
    (Present(value: final Object? a), Present(value: final Object? b)) =>
      equals(a, b),
    _ => a == b,
  };

  bool _equalLists(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!equals(a[index], b[index])) return false;
    }
    return true;
  }

  /// A hash code of [value] consistent with [equals].
  int hash(Object? value) => switch (value) {
    final List<Object?> items => Object.hashAll(items.map(hash)),
    Present(value: final Object? present) => Object.hash(
      Present,
      hash(present),
    ),
    _ => value.hashCode,
  };
}
