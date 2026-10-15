import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';

/// Writes the Dart declarations of a GraphQL enum (spec §7 "Enums"): a sealed
/// class, the enum of the known values and the class of an unknown one.
///
/// {@category codegen}
final class EnumEmitter {
  /// Creates the emitter.
  const EnumEmitter();

  static const DartNames _names = DartNames();
  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the three declarations of [type] to [writer].
  void emit(EnumType type, DartWriter writer) {
    final String name = _names.typeName(type.name);
    _writeSealed(type, name, writer);
    writer.line();
    _writeKnown(type, name, writer);
    writer.line();
    _writeUnknown(name, writer);
  }

  void _writeSealed(EnumType type, String name, DartWriter writer) {
    writer
      ..doc(type.description ?? 'The enum `${type.name}`.')
      ..block('sealed class $name implements client.DataEnum', () {
        writer
          ..doc(
            'The value named [raw]: a [${name}Known], or a [${name}Unknown] '
            'for a name\nthis code does not know.',
          )
          ..block('factory $name.parse(String raw)', () {
            writer
              ..block('for (final value in ${name}Known.values)', () {
                writer.line('if (value.raw == raw) return value;');
              })
              ..line('return ${name}Unknown(raw);');
          })
          ..line()
          ..doc('Reads and writes the values of `${type.name}`.')
          ..line(
            'static const client.DataCodec<$name> codec = '
            'client.EnumDataCodec($name.parse);',
          );
      });
  }

  void _writeKnown(EnumType type, String name, DartWriter writer) {
    writer
      ..doc('The values of [$name] this code knows.')
      ..block('enum ${name}Known implements $name', () {
        for (final (int index, SchemaEnumValue value) in type.values.indexed) {
          _writeValue(value, index == type.values.length - 1, writer);
          writer.line();
        }
        writer
          ..line('const ${name}Known(this.raw);')
          ..line()
          ..line('@override')
          ..line('final String raw;');
      });
  }

  void _writeValue(SchemaEnumValue value, bool isLast, DartWriter writer) {
    writer.doc(value.description ?? '`${value.name}`.');
    final String? reason = value.deprecationReason;
    if (reason != null) {
      writer.line('@Deprecated(${_literal.of(reason)})');
    }
    final String member = _names.memberName(
      value.name,
      reservedMembers: DartNames.enumMembers,
    );
    writer.line("$member(${_literal.of(value.name)})${isLast ? ';' : ','}");
  }

  void _writeUnknown(String name, DartWriter writer) {
    final String interpolated = '${name}Unknown'.replaceAll(r'$', r'\$');
    writer
      ..doc(
        'A value of [$name] this code does not know, such as one added to '
        'the\nschema after the code was generated.',
      )
      ..block('final class ${name}Unknown implements $name', () {
        writer
          ..doc('Creates the value named [raw].')
          ..line('const ${name}Unknown(this.raw);')
          ..line()
          ..line('@override')
          ..line('final String raw;')
          ..line()
          ..line('@override')
          ..line(
            'bool operator ==(Object other) => '
            'other is ${name}Unknown && other.raw == raw;',
          )
          ..line()
          ..line('@override')
          ..line('int get hashCode => raw.hashCode;')
          ..line()
          ..line('@override')
          ..line("String toString() => '$interpolated(\$raw)';");
      });
  }
}
