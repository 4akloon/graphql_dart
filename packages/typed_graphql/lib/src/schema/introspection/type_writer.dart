import '../../language/printer/printer.dart';
import '../../protocol/json_value.dart';
import '../model/input_value.dart';
import '../model/named_type_reference.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'introspection_query.dart';
import 'type_ref_writer.dart';

/// Writes named types as the introspection query's `FullType` fragment
/// reads them, and arguments and input fields as its `InputValue`
/// fragment does (spec §4.2).
///
/// Only the fields [query] reads are written, in the query's order; a
/// field that does not apply to a kind is `null`, as introspection
/// answers.
final class TypeWriter(
  /// The schema the types belong to.
  final Schema schema,

  /// The query whose answer is written.
  final IntrospectionQuery query,
) {
  /// Creates a writer.
  this;

  /// The writer of the type references inside a type.
  final TypeRefWriter references = TypeRefWriter(schema, query.typeDepth);

  /// [type] as `FullType`.
  JsonObject type(SchemaType type) => JsonObject({
    'kind': JsonString(references.kindOf(type)),
    'name': JsonString(type.name),
    if (query.includesDescriptions) 'description': _text(type.description),
    if (query.includesSpecifiedByUrl)
      'specifiedByURL': _text(type is ScalarType ? type.specifiedByUrl : null),
    if (query.includesOneOf)
      'isOneOf': type is InputObjectType
          ? JsonBool(type.isOneOf)
          : const JsonNull(),
    ..._members(type),
  });

  // The members of each kind; null for the kinds without them.
  Map<String, JsonValue> _members(SchemaType type) => {
    'fields': switch (type) {
      ObjectType(:final fields) || InterfaceType(:final fields) => JsonArray([
        for (final field in fields) _field(field),
      ]),
      _ => const JsonNull(),
    },
    'inputFields': switch (type) {
      InputObjectType(:final fields) => inputValues(fields),
      _ => const JsonNull(),
    },
    'interfaces': switch (type) {
      ObjectType(:final interfaces) ||
      InterfaceType(:final interfaces) => _named(interfaces),
      _ => const JsonNull(),
    },
    'enumValues': switch (type) {
      EnumType(:final values) => JsonArray(values.map(_enumValue).toList()),
      _ => const JsonNull(),
    },
    'possibleTypes': switch (type) {
      InterfaceType() || UnionType() => JsonArray([
        for (final possible in schema.possibleTypes(type))
          references.named(possible.name),
      ]),
      _ => const JsonNull(),
    },
  };

  /// [values] as `InputValue`s; without input value deprecation in the
  /// query, the deprecated ones are left out, as `includeDeprecated: false`
  /// leaves them out.
  JsonArray inputValues(List<InputValue> values) => JsonArray([
    for (final value in values)
      if (query.includesInputValueDeprecation ||
          value.deprecationReason == null)
        _inputValue(value),
  ]);

  JsonObject _inputValue(InputValue value) => JsonObject({
    'name': JsonString(value.name),
    if (query.includesDescriptions) 'description': _text(value.description),
    'type': references.reference(value.type),
    'defaultValue': _text(switch (value.defaultValue) {
      final defaultValue? => const Printer().print(defaultValue),
      null => null,
    }),
    if (query.includesInputValueDeprecation)
      ...deprecation(
        value.deprecationReason,
      ),
  });

  JsonObject _field(SchemaField field) => JsonObject({
    'name': JsonString(field.name),
    if (query.includesDescriptions) 'description': _text(field.description),
    'args': inputValues(field.arguments),
    'type': references.reference(field.type),
    ...deprecation(field.deprecationReason),
  });

  JsonObject _enumValue(SchemaEnumValue value) => JsonObject({
    'name': JsonString(value.name),
    if (query.includesDescriptions) 'description': _text(value.description),
    ...deprecation(value.deprecationReason),
  });

  /// `isDeprecated` and `deprecationReason` of an element deprecated for
  /// [reason], or not deprecated when [reason] is null.
  Map<String, JsonValue> deprecation(String? reason) => {
    'isDeprecated': JsonBool(reason != null),
    'deprecationReason': _text(reason),
  };

  JsonArray _named(List<NamedTypeReference> references) => JsonArray([
    for (final reference in references) this.references.named(reference.name),
  ]);

  JsonValue _text(String? text) =>
      text == null ? const JsonNull() : JsonString(text);
}
