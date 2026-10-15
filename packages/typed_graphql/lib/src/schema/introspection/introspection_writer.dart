import '../../protocol/json_value.dart';
import '../model/schema_directive.dart';
import '../schema.dart';
import 'introspection_listing.dart';
import 'introspection_query.dart';
import 'type_writer.dart';

/// Writes a schema as the `data` of its answer to an [IntrospectionQuery]
/// (graphql-js's `introspectionFromSchema`), without executing the query.
///
/// Types are listed in declaration order, then the built-in scalars the
/// schema references (`String` and `Boolean` always, as introspection
/// does; spec §3.5), then the introspection types. Directives are listed
/// in declaration order, then the built-in ones the schema did not
/// redefine.
final class IntrospectionWriter(
  /// The schema written.
  final Schema schema,

  /// The query whose answer is written.
  final IntrospectionQuery query,
) {
  /// Creates a writer.
  this;

  final TypeWriter _types = TypeWriter(schema, query);
  final IntrospectionListing _listing = IntrospectionListing(schema);

  /// `{"__schema": {...}}`.
  ///
  /// A reference to a type the schema lacks is an [ArgumentError]:
  /// introspection describes a schema that validation accepts. A
  /// [IntrospectionQuery.typeDepth] outside 0 to 100 is a [RangeError].
  JsonObject write() {
    query.checkTypeDepth();
    return _schemaObject();
  }

  JsonObject _schemaObject() => JsonObject({
    '__schema': JsonObject({
      if (query.includesSchemaDescription && query.includesDescriptions)
        'description': switch (schema.description) {
          final description? => JsonString(description),
          null => const JsonNull(),
        },
      'queryType': _root(schema.queryTypeName),
      'mutationType': _root(schema.mutationTypeName),
      'subscriptionType': _root(schema.subscriptionTypeName),
      'types': JsonArray([
        for (final type in _listing.types) _types.type(type),
      ]),
      'directives': JsonArray([
        for (final directive in _listing.directives) _directive(directive),
      ]),
    }),
  });

  JsonValue _root(String? name) => switch (name) {
    final name? => JsonObject({
      'name': JsonString(name),
      'kind': JsonString(_types.references.kindNamed(name)),
    }),
    null => const JsonNull(),
  };

  JsonObject _directive(SchemaDirective directive) => JsonObject({
    'name': JsonString(directive.name),
    if (query.includesDescriptions)
      'description': switch (directive.description) {
        final description? => JsonString(description),
        null => const JsonNull(),
      },
    if (query.includesDirectiveIsRepeatable)
      'isRepeatable': JsonBool(directive.isRepeatable),
    if (query.includesDirectiveDeprecation)
      ..._types.deprecation(directive.deprecationReason),
    'locations': JsonArray([
      for (final location in directive.locations) JsonString(location.spelling),
    ]),
    'args': _types.inputValues(directive.arguments),
  });
}
