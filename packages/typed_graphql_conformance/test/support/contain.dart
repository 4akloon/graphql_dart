import 'package:test/test.dart';

/// chai's `.to.contain({...})` on an object: every given key has the given
/// value; other keys are ignored.
final class Contain {
  /// Creates the matcher factory.
  const Contain();

  /// A matcher for a map that holds every entry of [expected].
  Matcher call(Map<String, Object?> expected) => allOf([
    for (final MapEntry(:key, :value) in expected.entries)
      containsPair(key, value),
  ]);
}
