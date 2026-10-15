import 'package:typed_graphql/typed_graphql.dart';

import '../plan/planned_field.dart';
import 'dart_string_literal.dart';
import 'dart_type.dart';
import 'imports.dart';
import 'type_mapper.dart';
import 'value_member.dart';

/// A field of a generated data class as it is written: its Dart type, codec,
/// doc comment and the expressions that read and write it.
final class DataClassField {
  /// Maps [field] with [mapper], recording the imports its type needs.
  ///
  /// A conditional field is nullable: when its condition leaves it out the
  /// JSON has no key and the codec reads null.
  factory DataClassField.of(
    PlannedField field,
    TypeMapper mapper,
    Imports imports,
  ) {
    final TypeRef declared = field.type;
    final TypeRef shown = field.isConditional && declared is NonNullType
        ? declared.type
        : declared;
    return DataClassField._(
      field,
      mapper.of(shown, imports, objectClass: field.className),
    );
  }

  DataClassField._(this._field, this.type);

  static const String _leftOut = '`@include` or `@skip` left it out.';

  final PlannedField _field;

  /// The Dart type and codec.
  final DartType type;

  /// The Dart member name.
  String get member => _field.memberName;

  /// The key in the JSON response.
  String get responseName => _field.responseName;

  /// Whether the field may be absent because of a variable condition.
  bool get isConditional => _field.isConditional;

  /// Whether the field is declared by the sealed base, which this class
  /// overrides.
  bool get overridesBase => _field.overridesBase;

  /// Whether the Dart type is nullable.
  bool get isNullable => type.type.endsWith('?');

  /// The name of the private codec constant.
  String get codecName => '_${member}Codec';

  /// The field as a part of the class's value.
  ValueMember get valueMember =>
      ValueMember(member, type.type.startsWith('List<'));

  /// The JSON key as a Dart string literal.
  String get keyLiteral => const DartStringLiteral().of(responseName);

  /// The doc comment: the schema description, else a default sentence.
  String get doc {
    final String description = _field.definition?.description?.trim() ?? '';
    if (description.isNotEmpty) {
      return isConditional
          ? '$description\n\nNull when $_leftOut'
          : description;
    }
    return isConditional
        ? 'The field `$responseName`; null when $_leftOut'
        : 'The field `$responseName`.';
  }
}
