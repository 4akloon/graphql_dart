import 'arg.dart';

/// The coerced values of one field call, or of one input object, read
/// through the [Arg]s the field or object declared (R4.3).
///
/// {@category builder}
final class Arguments {
  /// Reads [coerced], keyed by name, for the [declared] arguments. A key the
  /// request did not give is absent from the map.
  const Arguments(this.declared, this.coerced);

  /// No arguments.
  static const Arguments empty = Arguments(
    <Arg<Object?>>[],
    <String, Object?>{},
  );

  /// The arguments the field or input object declares.
  final List<Arg<Object?>> declared;

  /// The coerced values by argument name.
  final Map<String, Object?> coerced;

  /// The typed value of [arg].
  ///
  /// A [StateError] when [arg] is not one of the [declared] arguments (the
  /// same object, not only the same name).
  T get<T>(Arg<T> arg) {
    for (final candidate in declared) {
      if (identical(candidate, arg)) {
        return arg.read(coerced);
      }
    }
    throw StateError('Argument "${arg.name}" is not declared by this field.');
  }
}
