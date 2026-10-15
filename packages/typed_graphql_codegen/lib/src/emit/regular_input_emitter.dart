import 'package:typed_graphql/typed_graphql.dart';

import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'input_field.dart';
import 'input_field_members.dart';
import 'type_mapper.dart';

/// Writes the class of an input object that is not `@oneOf`.
///
/// {@category codegen}
final class RegularInputEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const RegularInputEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the class [name] for [type] to [writer].
  void emit(
    InputObjectType type,
    String name,
    DartWriter writer,
    Imports imports,
  ) {
    final List<InputField> fields = <InputField>[
      for (final InputValue field in type.fields)
        InputField.of(field, mapper, imports),
    ];
    writer
      ..doc(type.description ?? 'The input object `${type.name}`.')
      ..block('final class $name implements client.DataObject', () {
        const InputFieldMembers().constructor(
          'Creates the input object.',
          name,
          fields,
          writer,
        );
        writer.line();
        _writeReader(name, fields, writer);
        _writeDeclarations(type, name, fields, writer);
        const InputFieldMembers().valueMembers(name, fields, writer);
      });
  }

  void _writeDeclarations(
    InputObjectType type,
    String name,
    List<InputField> fields,
    DartWriter writer,
  ) {
    writer
      ..line()
      ..doc('Reads and writes the values of `${type.name}`.')
      ..assign(
        'static const client.DataCodec<$name> codec',
        'client.ObjectDataCodec($name._read)',
      )
      ..line();
    const InputFieldMembers()
      ..codecs(fields, writer)
      ..declarations(fields, writer);
  }

  void _writeReader(String name, List<InputField> fields, DartWriter writer) {
    final List<String> arguments = <String>[
      for (final InputField field in fields)
        '${field.dartName}: ${field.codecName}.'
            '${field.isOptional ? 'optionalField' : 'field'}'
            '(json, ${_literal.of(field.graphQLName)}, context)',
    ];
    const String parameters =
        'graphql.JsonObject json, client.DataContext context';
    if (writer.fits('factory $name._read($parameters) =>')) {
      writer.line('factory $name._read($parameters) =>');
      writer.indented(
        () => writer.indented(
          () => _writeConstruction(name, arguments, writer),
        ),
      );
      return;
    }
    writer
      ..line('factory $name._read(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json,')
          ..line('client.DataContext context,');
      })
      ..line(') => $name(');
    writer
      ..indented(() {
        for (final String argument in arguments) {
          writer.line('$argument,');
        }
      })
      ..line(');');
  }

  void _writeConstruction(
    String name,
    List<String> arguments,
    DartWriter writer,
  ) {
    writer.line('$name(');
    writer.indented(() {
      for (final String argument in arguments) {
        writer.line('$argument,');
      }
    });
    writer.line(');');
  }
}
