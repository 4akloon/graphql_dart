import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/enum_emitter.dart';

void main() {
  String emit(String sdl, String name) {
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    final DartWriter writer = DartWriter();
    const EnumEmitter().emit(schema.typeNamed(name)! as EnumType, writer);
    return writer.text;
  }

  test('an enum with descriptions and deprecations', () {
    expect(
      emit('''
"A user role."
enum Role {
  ADMIN
  EDITOR
  "Old."
  VIEWER @deprecated(reason: "Use EDITOR.")
  GUEST @deprecated
}
''', 'Role'),
      r'''
/// A user role.
sealed class Role implements client.DataEnum {
  /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
  /// this code does not know.
  factory Role.parse(String raw) {
    for (final value in RoleKnown.values) {
      if (value.raw == raw) return value;
    }
    return RoleUnknown(raw);
  }

  /// Reads and writes the values of `Role`.
  static const client.DataCodec<Role> codec = client.EnumDataCodec(Role.parse);
}

/// The values of [Role] this code knows.
enum RoleKnown implements Role {
  /// `ADMIN`.
  admin('ADMIN'),

  /// `EDITOR`.
  editor('EDITOR'),

  /// Old.
  @Deprecated('Use EDITOR.')
  viewer('VIEWER'),

  /// `GUEST`.
  @Deprecated('No longer supported')
  guest('GUEST');

  const RoleKnown(this.raw);

  @override
  final String raw;
}

/// A value of [Role] this code does not know, such as one added to the
/// schema after the code was generated.
final class RoleUnknown implements Role {
  /// Creates the value named [raw].
  const RoleUnknown(this.raw);

  @override
  final String raw;

  @override
  bool operator ==(Object other) => other is RoleUnknown && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'RoleUnknown($raw)';
}
''',
    );
  });

  test('values that clash with Dart get a suffix or are camel-cased', () {
    final String text = emit(
      'enum Odd { values NOT_FOUND default }',
      'Odd',
    );
    expect(
      text.split('\n').where(RegExp(r"^  \S+\('").hasMatch),
      [
        r"  values$('values'),",
        "  notFound('NOT_FOUND'),",
        r"  default$('default');",
      ],
    );
  });

  test('the type without a description is documented by its name', () {
    expect(
      emit('enum Odd { A }', 'Odd').startsWith('/// The enum `Odd`.\n'),
      isTrue,
    );
  });

  test('the unknown class escapes a dollar in its name', () {
    expect(
      emit('enum _Odd { A }', '_Odd'),
      contains(r"String toString() => '\$OddUnknown($raw)';"),
    );
  });
}
