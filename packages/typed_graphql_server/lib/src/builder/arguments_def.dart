import 'arg.dart';
import 'arguments.dart';

/// A list of arguments and how to decode them into the class [A] (R4.3).
///
/// {@category builder}
final class ArgumentsDef<A> {
  /// Declares [args] and the [decode] function that builds [A] from them.
  ArgumentsDef(List<Arg<Object?>> args, this.decode)
    : args = List.unmodifiable(args);

  /// The arguments, in declaration order.
  final List<Arg<Object?>> args;

  /// Builds the arguments class from the coerced values.
  final A Function(Arguments arguments) decode;
}
