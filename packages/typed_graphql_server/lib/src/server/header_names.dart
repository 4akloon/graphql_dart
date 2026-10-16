import 'package:meta/meta.dart';

/// Lower-cases header names, because HTTP header names are case-insensitive.
@internal
final class HeaderNames {
  /// Creates the helper.
  const HeaderNames();

  /// An unmodifiable copy of [headers] with lower-case names; a later entry
  /// wins when two names differ only by case.
  Map<String, String> lowerCased(Map<String, String> headers) =>
      Map.unmodifiable({
        for (final MapEntry(:key, :value) in headers.entries)
          key.toLowerCase(): value,
      });

  /// [base] with [name] in its `vary` header, which is created when missing and
  /// left alone when it already lists [name] or `*`.
  Map<String, String> varied(Map<String, String> base, String name) {
    final current = base['vary'];
    if (current == null) return merged(base, {'vary': name});
    final listed = current.split(',').map((item) => item.trim().toLowerCase());
    if (listed.contains('*') || listed.contains(name.toLowerCase())) {
      return base;
    }
    return merged(base, {'vary': '$current, $name'});
  }

  /// [base], whose names are already lower-case, with [additions] on top (names
  /// lower-cased), new values winning.
  Map<String, String> merged(
    Map<String, String> base,
    Map<String, String> additions,
  ) => Map.unmodifiable({...base, ...lowerCased(additions)});
}
