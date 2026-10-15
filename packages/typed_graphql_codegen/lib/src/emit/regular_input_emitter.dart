import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'input_field.dart';
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
        _writeConstructor(name, fields, writer);
        writer.line();
        _writeReader(name, fields, writer);
        _writeDeclarations(type, name, fields, writer);
        _writeToJson(fields, writer);
        writer.line();
        _writeEquality(name, fields, writer);
        writer.line();
        _writeToString(name, fields, writer);
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
    for (final InputField field in fields) {
      writer
        ..assign(
          'static const client.DataCodec<${field.value.type}> '
          '${field.codecName}',
          field.value.codec,
        )
        ..line();
    }
    for (final InputField field in fields) {
      writer
        ..doc(field.docText)
        ..line('final ${field.fieldType} ${field.dartName};')
        ..line();
    }
  }

  void _writeConstructor(
    String name,
    List<InputField> fields,
    DartWriter writer,
  ) {
    final List<String> parameters = <String>[
      for (final InputField field in fields)
        if (!field.isOptional) 'required this.${field.dartName}',
      for (final InputField field in fields)
        if (field.isOptional)
          'this.${field.dartName} = const graphql.Optional.absent()',
    ];
    writer
      ..doc('Creates the input object.')
      ..items('const $name({', parameters, '});');
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

  void _writeToJson(List<InputField> fields, DartWriter writer) {
    writer
      ..line('@override')
      ..line('graphql.JsonObject toJson() => graphql.JsonObject({')
      ..indented(() {
        for (final InputField field in fields) {
          final String key = _literal.of(field.graphQLName);
          final String write = '$key: ${field.codecName}.write';
          if (!field.isOptional) {
            writer.line('$write(${field.dartName}),');
            continue;
          }
          final String test =
              'if (${field.dartName} case '
              'graphql.Present(:final value))';
          final String entry = '$write(value),';
          if (writer.fits('$test $entry')) {
            writer.line('$test $entry');
          } else {
            writer.line(test);
            writer.indented(() => writer.line(entry));
          }
        }
      })
      ..line('});');
  }

  void _writeEquality(String name, List<InputField> fields, DartWriter writer) {
    final String other = const DartNames().freeName('other', <String>[
      for (final InputField field in fields) field.dartName,
    ]);
    writer
      ..line('@override')
      ..arrowJoined('bool operator ==(Object $other)', <String>[
        '$other is $name',
        for (final InputField field in fields)
          if (field.holdsList)
            'const client.DataEquality().equals($other.${field.dartName}, '
                '${field.dartName})'
          else
            '$other.${field.dartName} == ${field.dartName}',
      ], '&&')
      ..line()
      ..line('@override');
    final List<String> hashes = <String>[
      for (final InputField field in fields)
        if (field.holdsList)
          'const client.DataEquality().hash(${field.dartName})'
        else
          '${field.dartName}.hashCode',
    ];
    if (hashes.length == 1) {
      writer.arrow('int get hashCode', hashes.single);
    } else {
      writer.items('int get hashCode => Object.hashAll([', hashes, ']);');
    }
  }

  void _writeToString(String name, List<InputField> fields, DartWriter writer) {
    final String escaped = name.replaceAll(r'$', r'\$');
    final List<String> tokens = <String>[
      for (final InputField field in fields)
        '${field.dartName.replaceAll(r'$', r'\$')}: ${field.interpolation}',
    ];
    writer.line('@override');
    final String single = "'$escaped(${tokens.join(', ')})'";
    if (writer.fits('String toString() => $single;')) {
      writer.line('String toString() => $single;');
      return;
    }
    writer.line('String toString() =>');
    writer.indented(() {
      writer.indented(() => _writeSplitLiteral(escaped, tokens, writer));
    });
  }

  void _writeSplitLiteral(String name, List<String> tokens, DartWriter writer) {
    StringBuffer current = StringBuffer('$name(');
    final List<String> lines = <String>[];
    for (final (int index, String token) in tokens.indexed) {
      final String piece = '$token${index == tokens.length - 1 ? ')' : ', '}';
      if (!writer.fits("'$current$piece';") && current.isNotEmpty) {
        lines.add('$current');
        current = StringBuffer();
      }
      current.write(piece);
    }
    lines.add('$current');
    for (final (int index, String text) in lines.indexed) {
      writer.line("'$text'${index == lines.length - 1 ? ';' : ''}");
    }
  }
}
