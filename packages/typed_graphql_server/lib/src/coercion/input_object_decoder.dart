import 'package:typed_graphql/typed_graphql.dart';

import '../builder/arguments.dart';
import '../execution/graphql_exception.dart';
import '../execution/masked_message.dart';
import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';

/// Builds the Dart value of an input object from its coerced fields with the
/// definition's `decode`, turning what it throws into problems: a
/// `GraphQLException` keeps its message and extensions, anything else is an
/// "Unexpected error." (`GQL314`) that the caller reports to `onError`.
final class InputObjectDecoder {
  /// Decodes into [problems].
  InputObjectDecoder(this.environment, this.problems);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The Dart value of [type] with the [coerced] fields, at [path].
  Object? decode(
    Map<String, Object?> coerced,
    InputObjectType type,
    InputPath path,
  ) {
    final definition = environment.bindings.inputObjects[type.name];
    if (definition == null) {
      problems.add('Input object "${type.name}" has no definition.', path);
      return InvalidValue.instance;
    }
    try {
      return definition.decode(
        Arguments(definition.fields, Map.unmodifiable(coerced)),
      );
    } on GraphQLException catch (exception) {
      problems.add(exception.message, path, extensions: exception.extensions);
    } on Object catch (error, stackTrace) {
      problems.add(
        const MaskedMessage().text,
        path,
        code: DiagnosticCode.inputDecodeFailed,
        thrown: (error: error, stackTrace: stackTrace),
      );
    }
    return InvalidValue.instance;
  }
}
