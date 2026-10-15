import '../plan/data_class_role.dart';
import '../plan/planned_class.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'data_class_field.dart';
import 'fragment_decode_writer.dart';
import 'imports.dart';
import 'type_mapper.dart';

/// Writes the sealed base of a selection on an abstract type (spec §7 "Data
/// classes", R7.5): it reads the `__typename` and hands the JSON to the
/// class of that type.
///
/// {@category codegen}
final class PolymorphicBaseEmitter {
  /// Creates the emitter; [mapper] maps the shared field types.
  const PolymorphicBaseEmitter(this.mapper);

  static const String _switchHead =
      "switch (_typenameCodec.field(json, '__typename', context)) {";

  /// The mapper of field types.
  final TypeMapper mapper;

  /// Writes [plan] with the class doc comment [doc].
  void emit(
    PolymorphicBasePlan plan,
    String doc,
    DartWriter writer,
    Imports imports,
  ) {
    final fields = [
      for (final field in plan.sharedFields)
        DataClassField.of(field, mapper, imports),
    ];
    writer.doc(doc);
    writer.block('sealed class ${plan.name} implements client.DataObject', () {
      _reader(writer, plan);
      writer.line();
      _codecs(writer, plan);
      writer.line();
      writer.doc("The name of the value's type, `__typename`.");
      writer.line('String get typename;');
      for (final field in fields) {
        writer.line();
        writer.doc(field.doc);
        writer.line('${field.type.type} get ${field.member};');
      }
      if (plan.holderName case final holder?) {
        writer.line();
        writer.doc('The fragments spread on this value.');
        writer.line('$holder get fragments;');
      }
    });
  }

  void _reader(DartWriter writer, PolymorphicBasePlan plan) {
    final String name = plan.name;
    final List<String> parameters = [
      'graphql.JsonObject json',
      'client.DataContext context',
    ];
    final String head = 'factory $name._read(${parameters.join(', ')})';
    if (writer.fits('$head => $_switchHead')) {
      writer.line('$head => $_switchHead');
    } else {
      writer.line('factory $name._read(');
      writer.indented(() {
        for (final String parameter in parameters) {
          writer.line('$parameter,');
        }
      });
      writer.line(') => $_switchHead');
    }
    writer.indented(() {
      for (final variant in plan.variants) {
        _case(
          writer,
          const DartStringLiteral().of(variant.typeName),
          variant.className,
        );
      }
      _case(writer, '_', plan.unknownName);
    });
    writer.line('};');
  }

  void _case(DartWriter writer, String pattern, String className) {
    final String call = '$className._read(json, context),';
    if (writer.fits('$pattern => $call')) {
      writer.line('$pattern => $call');
      return;
    }
    writer.line('$pattern =>');
    writer.indented(() => writer.indented(() => writer.line(call)));
  }

  void _codecs(DartWriter writer, PolymorphicBasePlan plan) {
    final String noun = plan.role == DataClassRole.fragment
        ? 'fragment'
        : 'value';
    writer.doc('Reads and writes the $noun.');
    writer.assign(
      'static const client.DataCodec<${plan.name}> codec',
      'client.ObjectDataCodec(${plan.name}._read)',
    );
    writer.line();
    writer.assign(
      'static const client.DataCodec<String> _typenameCodec',
      'client.ScalarDataCodec(graphql.StringCodec())',
    );
    if (plan.role == DataClassRole.fragment) {
      writer.line();
      const FragmentDecodeWriter().write(writer, plan.name);
    }
  }
}
