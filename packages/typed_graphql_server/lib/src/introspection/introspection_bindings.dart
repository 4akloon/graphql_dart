import 'package:typed_graphql/typed_graphql.dart';

import '../builder/enum_type_def.dart';
import '../builder/enum_value_def.dart';
import '../builder/field_def.dart';
import '../builder/named_type_def.dart';
import '../execution/schema_bindings.dart';
import 'introspected_type.dart';
import 'introspection_fields.dart';
import 'member_lanes.dart';
import 'type_kind.dart';
import 'type_lanes.dart';

/// The run-time side of the introspection types for one schema: object
/// bindings with pure lanes over the core model for `__Schema`, `__Type`,
/// `__Field`, `__InputValue`, `__EnumValue` and `__Directive`, the two
/// enums, and the `__schema` and `__type` fields of the query root. The
/// schema never declares them; the core's `BuiltIns` has the types.
final class IntrospectionBindings(
  /// The schema introspection describes.
  final Schema schema,
) {
  /// Describes [schema].
  this;

  /// [bindings] with the introspection types and the query root's entry
  /// fields added.
  SchemaBindings addTo(SchemaBindings bindings) {
    final members = MemberLanes();
    final fields = {
      ...bindings.fields,
      '__Schema': _schemaFields,
      '__Type': TypeLanes(schema).fields,
      '__Field': members.fieldFields,
      '__InputValue': members.inputValueFields,
      '__EnumValue': members.enumValueFields,
      '__Directive': members.directiveFields,
    };
    final queryName = schema.queryTypeName;
    if (queryName != null) {
      fields[queryName] = {...?fields[queryName], ..._entryFields};
    }
    return bindings.withIntrospection(fields, _leaves);
  }

  Map<String, FieldDef<Object?, Object?>> get _entryFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<Object?>('__schema', (_) => schema),
        IntrospectionFields.withArguments<Object?>(
          '__type',
          (_, arguments) => switch (schema.typeNamed(
            arguments['name'] as String,
          )) {
            final type? => IntrospectedType.named(type.name),
            null => null,
          },
        ),
      ]);

  Map<String, FieldDef<Object?, Object?>> get _schemaFields {
    final listing = IntrospectionListing(schema);
    return IntrospectionFields.table([
      IntrospectionFields.pure<Schema>(
        'description',
        (_) => schema.description,
      ),
      IntrospectionFields.pure<Schema>(
        'types',
        (_) => [
          for (final type in listing.types) IntrospectedType.named(type.name),
        ],
      ),
      IntrospectionFields.pure<Schema>(
        'queryType',
        (_) => _root(schema.queryTypeName),
      ),
      IntrospectionFields.pure<Schema>(
        'mutationType',
        (_) => _root(schema.mutationTypeName),
      ),
      IntrospectionFields.pure<Schema>(
        'subscriptionType',
        (_) => _root(schema.subscriptionTypeName),
      ),
      IntrospectionFields.pure<Schema>('directives', (_) => listing.directives),
    ]);
  }

  IntrospectedType? _root(String? name) =>
      name == null ? null : IntrospectedType.named(name);

  Map<String, NamedTypeDef> get _leaves => {
    '__TypeKind': EnumTypeDef<TypeKind>('__TypeKind', [
      for (final kind in TypeKind.values) EnumValueDef(kind, kind.spelling),
    ]),
    '__DirectiveLocation': EnumTypeDef<DirectiveLocation>(
      '__DirectiveLocation',
      [
        for (final location in DirectiveLocation.values)
          EnumValueDef(location, location.spelling),
      ],
    ),
  };
}
