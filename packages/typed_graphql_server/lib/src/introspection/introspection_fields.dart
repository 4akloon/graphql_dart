import 'package:typed_graphql/typed_graphql.dart';

import '../builder/field_def.dart';
import '../builder/field_lane.dart';
import '../builder/output_ref.dart';
import '../builder/scalar_type_def.dart';

/// Makes the [FieldDef]s of the introspection objects: pure getters, or
/// resolvers that read their coerced arguments by name.
///
/// The executor reads the field's type from the core schema, which has the
/// introspection types already, so a definition's own [FieldDef.type] is a
/// placeholder nothing reads.
final class IntrospectionFields {
  IntrospectionFields._();

  static final OutputRef<Object?> _placeholder = ScalarTypeDef<String>(
    'String',
    const StringCodec(),
  );

  /// The field [name] that reads its value from the parent `P`.
  static FieldDef<Object?, Object?> pure<P>(
    String name,
    Object? Function(P parent) read,
  ) => FieldDef(
    name: name,
    type: _placeholder,
    args: const [],
    directives: const [],
    lane: PureLane((parent) => read(parent as P)),
  );

  /// The field [name] that reads its value from the parent `P` and the
  /// coerced arguments of the call, by name.
  static FieldDef<Object?, Object?> withArguments<P>(
    String name,
    Object? Function(P parent, Map<String, Object?> arguments) read,
  ) => FieldDef(
    name: name,
    type: _placeholder,
    args: const [],
    directives: const [],
    lane: ResolverLane(
      (parent, arguments, context, info) =>
          read(parent as P, arguments.coerced),
    ),
  );

  /// Whether the call asked for the deprecated elements too
  /// (`includeDeprecated: true`).
  static bool includesDeprecated(Map<String, Object?> arguments) =>
      arguments['includeDeprecated'] == true;

  /// The definitions in a table by field name.
  static Map<String, FieldDef<Object?, Object?>> table(
    List<FieldDef<Object?, Object?>> fields,
  ) => {for (final field in fields) field.name: field};
}
