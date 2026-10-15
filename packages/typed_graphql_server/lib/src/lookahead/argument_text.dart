import '../builder/arg.dart';
import '../builder/arguments.dart';
import 'canonical_json.dart';

/// Writes the coerced arguments of a field call as one canonical text, for
/// a fingerprint: arguments by name, values as [CanonicalJson], so the order
/// the request wrote them in does not show.
final class ArgumentText {
  /// Creates the writer.
  const ArgumentText();

  /// `(a:1,b:"x")` for the arguments the request gave (defaults included),
  /// and an empty text when there are none.
  String of(Arguments arguments) {
    final parts = <String>[];
    for (final arg in arguments.declared) {
      if (!arguments.coerced.containsKey(arg.name)) {
        continue;
      }
      parts.add('${arg.name}:${_json(arg, arguments.coerced[arg.name])}');
    }
    if (parts.isEmpty) {
      return '';
    }
    parts.sort();
    return '(${parts.join(',')})';
  }

  // A value the argument's type cannot write (a codec refusing it) is
  // replaced by a marker: a fingerprint is a key, not a response.
  String _json(Arg<Object?> arg, Object? coerced) {
    try {
      return const CanonicalJson().write(
        arg.type.jsonOf(arg.type.adapt(coerced)),
      );
    } on Object {
      return '?';
    }
  }
}
