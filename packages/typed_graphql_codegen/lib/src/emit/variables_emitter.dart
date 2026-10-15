import 'package:typed_graphql/typed_graphql.dart';

import '../plan/class_names.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'input_field.dart';
import 'input_field_members.dart';
import 'type_mapper.dart';

/// Writes the variables class of an operation (spec §7 "Input objects and
/// variables", R7.7): only written, never read.
///
/// {@category codegen}
final class VariablesEmitter {
  /// Creates the emitter; [mapper] maps the variable types.
  const VariablesEmitter(this.mapper);

  /// The mapper of variable types.
  final TypeMapper mapper;

  /// Writes the variables class of [operation] to [writer].
  void emit(OperationDefinition operation, DartWriter writer, Imports imports) {
    final String operationName = operation.name?.value ?? '';
    final String name = const ClassNames().variables(operationName);
    final fields = [
      for (final definition in operation.variableDefinitions)
        InputField.variable(definition, mapper, imports),
    ];
    const members = InputFieldMembers();
    writer.doc(
      'The variables of the ${operation.operation.name} `$operationName`.',
    );
    writer.block('final class $name implements client.DataObject', () {
      members.constructor('Creates the variables.', name, fields, writer);
      writer.line();
      members.codecs(fields, writer);
      members.declarations(fields, writer);
      members.valueMembers(name, fields, writer);
    });
  }
}
