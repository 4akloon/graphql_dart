import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'one_of_input_emitter.dart';
import 'regular_input_emitter.dart';
import 'type_mapper.dart';

/// Writes the Dart class of a GraphQL input object (spec §7 "Input objects
/// and variables", R7.7): a final class, or a sealed class with one variant
/// per field for a `@oneOf` input object.
///
/// {@category codegen}
final class InputObjectEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const InputObjectEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  /// Writes the declarations of [type] to [writer], recording imports.
  void emit(InputObjectType type, DartWriter writer, Imports imports) {
    final String name = const DartNames().typeName(type.name);
    if (type.isOneOf) {
      OneOfInputEmitter(mapper).emit(type, name, writer, imports);
    } else {
      RegularInputEmitter(mapper).emit(type, name, writer, imports);
    }
  }
}
