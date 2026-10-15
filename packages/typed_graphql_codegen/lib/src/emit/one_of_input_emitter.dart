import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'input_field.dart';
import 'type_mapper.dart';

/// Writes the classes of a `@oneOf` input object: a sealed class and one
/// variant per field, so the compiler enforces that exactly one is given.
///
/// {@category codegen}
final class OneOfInputEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const OneOfInputEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the sealed class [name] and its variants for [type] to [writer].
  void emit(
    InputObjectType type,
    String name,
    DartWriter writer,
    Imports imports,
  ) {
    final List<InputField> fields = <InputField>[
      for (final InputValue field in type.fields)
        InputField.exclusive(field, mapper, imports),
    ];
    _writeSealed(type, name, fields, writer);
    for (final InputField field in fields) {
      writer.line();
      _writeVariant(name, field, writer);
    }
  }

  void _writeSealed(
    InputObjectType type,
    String name,
    List<InputField> fields,
    DartWriter writer,
  ) {
    final String? description = type.description;
    writer.doc(
      description == null
          ? 'The input object `${type.name}`: exactly one of its fields is '
                'given.'
          : '$description\n\nExactly one of its fields is given.',
    );
    writer.block('sealed class $name implements client.DataObject', () {
      _writeReader(name, fields, writer);
      writer
        ..line()
        ..doc('Reads and writes the values of `${type.name}`.')
        ..assign(
          'static const client.DataCodec<$name> codec',
          'client.ObjectDataCodec($name._read)',
        );
      for (final InputField field in fields) {
        writer
          ..line()
          ..assign(
            'static const client.DataCodec<${field.value.type}> '
            '${field.codecName}',
            field.value.codec,
          );
      }
    });
  }

  void _writeReader(String name, List<InputField> fields, DartWriter writer) {
    final String names = fields.map((f) => f.graphQLName).join(', ');
    const String parameters =
        'graphql.JsonObject json, client.DataContext context';
    final String header = 'factory $name._read($parameters) =>';
    if (writer.fits(header)) {
      writer.line(header);
    } else {
      writer
        ..line('factory $name._read(')
        ..indented(() {
          writer
            ..line('graphql.JsonObject json,')
            ..line('client.DataContext context,');
        })
        ..line(') =>');
    }
    writer.indented(
      () => writer.indented(() {
        writer.line('switch (json.fields.keys.toList()) {');
        writer.indented(() {
          for (final InputField field in fields) {
            _writeArm(name, field, writer);
          }
          writer
            ..line('_ => throw const client.DataFormatException(')
            ..indented(() {
              writer.line(
                '${_literal.of('Expected exactly one of the fields $names.')},',
              );
            })
            ..line('),');
        });
        writer.line('};');
      }),
    );
  }

  void _writeArm(String name, InputField field, DartWriter writer) {
    final String variant = '$name${_names.capitalized(field.dartName)}';
    final String arm = '[${_literal.of(field.graphQLName)}] =>';
    final String value =
        '$variant(${field.codecName}.field(json, '
        '${_literal.of(field.graphQLName)}, context)),';
    if (writer.fits('$arm $value')) {
      writer.line('$arm $value');
    } else {
      writer.line(arm);
      writer.indented(() => writer.line(value));
    }
  }

  static const DartNames _names = DartNames();

  void _writeVariant(String base, InputField field, DartWriter writer) {
    final String variant = '$base${_names.capitalized(field.dartName)}';
    final String escaped = variant.replaceAll(r'$', r'\$');
    final String name = field.dartName;
    writer
      ..doc('[$base] with its field `${field.graphQLName}`.')
      ..block('final class $variant implements $base', () {
        writer
          ..doc(
            'Creates the input object with its field `${field.graphQLName}`.',
          )
          ..line('const $variant(this.$name);')
          ..line()
          ..doc(field.docText)
          ..line('final ${field.value.type} $name;')
          ..line()
          ..line('@override')
          ..line('graphql.JsonObject toJson() => graphql.JsonObject({')
          ..indented(() {
            writer.line(
              '${_literal.of(field.graphQLName)}: '
              '$base.${field.codecName}.write($name),',
            );
          })
          ..line('});')
          ..line();
        _writeEquality(variant, name, writer);
        writer
          ..line()
          ..line('@override')
          ..arrow('String toString()', "'$escaped(${field.interpolation})'");
      });
  }

  void _writeEquality(String variant, String name, DartWriter writer) {
    // The parameter keeps the name `other` (avoid_renaming_method_parameters);
    // a field of that name is read through `this`.
    final String own = name == 'other' ? 'this.other' : name;
    writer
      ..line('@override')
      ..arrow(
        'bool operator ==(Object other)',
        'other is $variant && other.$name == $own',
      )
      ..line()
      ..line('@override')
      ..line('int get hashCode => $name.hashCode;');
  }
}
