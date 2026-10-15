import 'dart_writer.dart';
import 'value_member.dart';

/// Writes `==`, `hashCode` and `toString` of a generated class from its
/// [ValueMember]s.
///
/// {@category codegen}
final class ValueMembers {
  /// Creates the writer.
  const ValueMembers();

  /// Writes the three members for the class [className], separated by blank
  /// lines.
  void write(
    DartWriter writer,
    String className,
    List<ValueMember> members,
  ) {
    _equality(writer, className, members);
    writer.line();
    _hashCode(writer, members);
    writer.line();
    _toString(writer, className, members);
  }

  void _equality(
    DartWriter writer,
    String className,
    List<ValueMember> members,
  ) {
    writer.line('@override');
    const String head = 'bool operator ==(Object other)';
    final List<String> operands = [
      'other is $className',
      for (final member in members) _comparison(member),
    ];
    final String joined = operands.join(' && ');
    var isOneLineAfterBreak = false;
    writer.indented(
      () => writer.indented(
        () => isOneLineAfterBreak = writer.fits('$joined;'),
      ),
    );
    if (!writer.fits('$head => $joined;') && isOneLineAfterBreak) {
      writer.line('$head =>');
      writer.indented(() => writer.indented(() => writer.line('$joined;')));
      return;
    }
    writer.arrowJoined(head, operands, '&&');
  }

  String _comparison(ValueMember member) => member.isList
      ? 'const client.DataEquality().equals('
            '${member.otherRead}, ${member.ownRead})'
      : '${member.otherRead} == ${member.ownRead}';

  String _hashOf(ValueMember member) => member.isList
      ? 'const client.DataEquality().hash(${member.name})'
      : member.name;

  // The label is text, so its `$` is escaped; the value is read.
  String _label(ValueMember member) =>
      '${_escaped(member.name)}: ${member.interpolation}';

  String _escaped(String text) => text.replaceAll(r'$', r'\$');

  void _hashCode(DartWriter writer, List<ValueMember> members) {
    writer.line('@override');
    final List<String> parts = [for (final member in members) _hashOf(member)];
    switch (members) {
      case []:
        writer.line('int get hashCode => 0;');
      case [ValueMember(isList: false)]:
        writer.line('int get hashCode => ${members.single.name}.hashCode;');
      case [ValueMember(isList: true)]:
        writer.line('int get hashCode => ${parts.single};');
      case _:
        writer.items('int get hashCode => Object.hashAll([', parts, ']);');
    }
  }

  void _toString(
    DartWriter writer,
    String className,
    List<ValueMember> members,
  ) {
    final String parts = [for (final member in members) _label(member)]
        .join(', ');
    writer
      ..line('@override')
      ..arrow('String toString()', "'${_escaped(className)}($parts)'");
  }
}
