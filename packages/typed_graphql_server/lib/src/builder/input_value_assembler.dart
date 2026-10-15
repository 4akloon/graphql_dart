import 'package:typed_graphql/typed_graphql.dart';

import 'arg.dart';
import 'directive_nodes.dart';
import 'literal_writer.dart';

/// Turns an [Arg] into a core [InputValue], with its default value written as
/// a literal; a default that cannot be written is a `GQL302` problem.
final class InputValueAssembler {
  /// Creates the assembler; it adds problems to [problems].
  InputValueAssembler(this._literals, this.problems);

  final LiteralWriter _literals;

  // An inherited interface field is assembled once per implementing type
  // with the same Arg; its bad default is reported once.
  final Set<Arg<Object?>> _reported = Set.identity();

  /// The diagnostics found so far; this assembler adds to them.
  final List<Diagnostic> problems;

  /// The input value for [arg]; [coordinate] names it in messages.
  InputValue assemble(Arg<Object?> arg, String coordinate) => InputValue(
    arg.name,
    arg.type.typeRef,
    description: arg.description,
    defaultValue: _defaultOf(arg, coordinate),
    appliedDirectives: const DirectiveNodes().withDeprecation(
      const [],
      arg.deprecationReason,
    ),
  );

  Value? _defaultOf(Arg<Object?> arg, String coordinate) {
    try {
      final json = arg.defaultJson;
      return json == null ? null : _literals.write(json, arg.type.typeRef);
    } on Object catch (error) {
      // The core's codecs and `jsonOf` signal an unwritable value with an
      // ArgumentError or a StateError; `avoid_catching_errors` forbids naming
      // them, so anything else is rethrown.
      if (error is! ArgumentError && error is! StateError) rethrow;
      if (_reported.add(arg)) _report(coordinate, _reasonOf(error));
    }
    return null;
  }

  String _reasonOf(Object error) => switch (error) {
    ArgumentError(:final message, :final name, :final invalidValue) =>
      '$message'
          '${name == null ? '' : ' (argument "$name")'}'
          '${invalidValue == null ? '' : ' (value: $invalidValue)'}',
    StateError(:final message) => message,
    _ => '$error',
  };

  void _report(String coordinate, String reason) {
    problems.add(
      Diagnostic(
        .unencodableDefaultValue,
        .error,
        'The default value of "$coordinate" cannot be written as a '
        'literal: $reason',
      ),
    );
  }
}
