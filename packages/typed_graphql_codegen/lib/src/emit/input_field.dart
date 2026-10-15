import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_type.dart';
import 'imports.dart';
import 'type_mapper.dart';

/// The plan of one input field, or one operation variable: its names, its
/// Dart type and whether the caller may leave it out (spec §7 "Input objects
/// and variables", R7.7).
///
/// {@category codegen}
final class const InputField({
  /// The name in GraphQL.
  required final String graphQLName,

  /// The Dart member name.
  required final String dartName,

  /// The Dart type of the value, without `Optional`.
  required final DartType value,

  /// Whether the field is an `Optional`, absent unless the caller gives it.
  required final bool isOptional,

  /// The doc comment text; null for the default.
  final String? doc,
}) {
  /// Creates a field plan.
  this;

  /// The plan of [input]: a nullable field, or one with a default, is
  /// optional.
  factory InputField.of(InputValue input, TypeMapper mapper, Imports imports) {
    final DartType type = mapper.of(input.type, imports);
    return InputField(
      graphQLName: input.name,
      dartName: dartNameOf(input.name),
      value: type,
      isOptional: input.type is! NonNullType || input.defaultValue != null,
      doc: _doc(input),
    );
  }

  /// The plan of a field of a `@oneOf` input object: always given, with the
  /// non-null type, because the variant that holds it says which is given.
  factory InputField.exclusive(
    InputValue input,
    TypeMapper mapper,
    Imports imports,
  ) => InputField(
    graphQLName: input.name,
    dartName: dartNameOf(input.name),
    value: mapper.ofNonNull(input.type, imports),
    isOptional: false,
    doc: _doc(input),
  );

  /// The type of the Dart field: `graphql.Optional<T>` or the value type.
  String get fieldType =>
      isOptional ? 'graphql.Optional<${value.type}>' : value.type;

  /// Whether the value type holds a list, so equality must compare items.
  bool get holdsList => _list.hasMatch(value.type);

  /// The member read inside a string literal: `$name`, or `${name}` when the
  /// name has a `$` that would end the short form early.
  String get interpolation =>
      dartName.contains(r'$') ? '\${$dartName}' : '\$$dartName';

  /// The text of [doc], or the default for the field.
  String get docText => doc ?? 'The field `$graphQLName`.';

  /// The private codec field, `_<dartName>Codec`.
  String get codecName => '_${dartName}Codec';

  static final RegExp _list = RegExp(r'(^|[^\w$.])List<');

  /// The Dart member name of the input field named [name].
  static String dartNameOf(String name) => const DartNames().memberName(
    name,
    reservedMembers: DartNames.objectMembers,
  );

  static String _doc(InputValue input) {
    final String base = input.description ?? 'The field `${input.name}`.';
    final StringBuffer out = StringBuffer(base);
    final Value? defaultValue = input.defaultValue;
    if (defaultValue != null) {
      final String printed = const Printer()
          .print(defaultValue)
          .replaceAll(RegExp(r'\s*\n\s*'), ' ');
      out
        ..write(base.contains('\n') ? '\n\n' : ' ')
        ..write('Its default is `$printed`.');
    }
    final String? reason = input.deprecationReason;
    if (reason != null) {
      out.write('\n\nDeprecated: $reason');
    }
    return out.toString();
  }
}
