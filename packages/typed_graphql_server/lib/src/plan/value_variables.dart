import 'package:typed_graphql/typed_graphql.dart';

/// Whether written arguments mention a variable, so whether their coerced
/// values can be computed once for every request.
final class ValueVariables {
  /// Inspects without state.
  const ValueVariables();

  /// Whether any of [arguments] holds a variable, at any depth.
  bool occursIn(List<Argument> arguments) {
    final pending = <Value>[for (final argument in arguments) argument.value];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case Variable():
          return true;
        case ListValue(:final values):
          pending.addAll(values);
        case ObjectValue(:final fields):
          pending.addAll([for (final field in fields) field.value]);
        default:
          break;
      }
    }
    return false;
  }
}
