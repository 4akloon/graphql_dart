import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'input_field.dart';

/// Writes the members that input objects and operation variables share: the
/// constructor, the codecs, the fields, `toJson`, `==`, `hashCode` and
/// `toString` (spec §7 "Input objects and variables", R7.7).
///
/// {@category codegen}
final class InputFieldMembers {
  /// Creates the writer.
  const InputFieldMembers();

  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the constructor of [name], documented with [doc]: required
  /// fields first, then the optional ones, absent by default.
  void constructor(
    String doc,
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
      ..doc(doc)
      ..items('const $name({', parameters, '});');
  }

  /// Writes the private codec of each of [fields], each followed by a blank
  /// line.
  void codecs(List<InputField> fields, DartWriter writer) {
    for (final InputField field in fields) {
      writer
        ..assign(
          'static const client.DataCodec<${field.value.type}> '
          '${field.codecName}',
          field.value.codec,
        )
        ..line();
    }
  }

  /// Writes the documented declaration of each of [fields], each followed by
  /// a blank line.
  void declarations(List<InputField> fields, DartWriter writer) {
    for (final InputField field in fields) {
      writer
        ..doc(field.docText)
        ..line('final ${field.fieldType} ${field.dartName};')
        ..line();
    }
  }

  /// Writes `toJson`, `==`, `hashCode` and `toString`, apart by blank lines.
  void valueMembers(String name, List<InputField> fields, DartWriter writer) {
    toJson(fields, writer);
    writer.line();
    equality(name, fields, writer);
    writer.line();
    toStringMember(name, fields, writer);
  }

  /// Writes `toJson`, which writes only the optional values that are present.
  void toJson(List<InputField> fields, DartWriter writer) {
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

  /// Writes `==` and `hashCode`; lists compare by item.
  void equality(String name, List<InputField> fields, DartWriter writer) {
    // The parameter keeps the name `other` (avoid_renaming_method_parameters);
    // a field of that name is read through `this`.
    String own(InputField field) =>
        field.dartName == 'other' ? 'this.other' : field.dartName;
    writer
      ..line('@override')
      ..arrowJoined('bool operator ==(Object other)', <String>[
        'other is $name',
        for (final InputField field in fields)
          if (field.holdsList)
            'const client.DataEquality().equals(other.${field.dartName}, '
                '${own(field)})'
          else
            'other.${field.dartName} == ${own(field)}',
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

  /// Writes `toString`, wrapped at 80 columns.
  void toStringMember(String name, List<InputField> fields, DartWriter writer) {
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
