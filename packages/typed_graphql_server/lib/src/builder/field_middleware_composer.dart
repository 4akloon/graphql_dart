import 'package:typed_graphql/typed_graphql.dart';

import '../execution/field_middleware.dart';
import '../execution/field_resolver.dart';
import '../execution/field_site.dart';
import '../execution/schema_bindings.dart';
import 'build_options.dart';
import 'field_def.dart';
import 'field_lane.dart';

/// Composes the middleware chain of every resolver field once, when the
/// schema is built (spec 8), so the executor calls a single function.
final class FieldMiddlewareComposer<C> {
  /// Composes over [_schema] with the middleware in [_options].
  ///
  /// A directive slot for a directive the schema does not define is an
  /// [ArgumentError]: it is a programmer error, not input.
  FieldMiddlewareComposer(this._schema, this._options) {
    for (final name in _options.directiveMiddleware.keys) {
      if (_schema.directiveNamed(name) == null) {
        throw ArgumentError.value(
          name,
          'directiveMiddleware',
          'the schema defines no directive with this name',
        );
      }
    }
  }

  final Schema _schema;
  final BuildOptions<C> _options;

  /// [bindings] with each field replaced by its composed form. A field with
  /// an empty chain, or whose middleware all returned `next`, stays the
  /// very same definition.
  SchemaBindings compose(SchemaBindings bindings) => bindings.withFields({
    for (final MapEntry(key: typeName, value: fields)
        in bindings.fields.entries)
      typeName: _composeType(typeName, fields),
  });

  Map<String, FieldDef<Object?, Object?>> _composeType(
    String typeName,
    Map<String, FieldDef<Object?, Object?>> fields,
  ) {
    final parent = _schema.typeNamed(typeName);
    if (parent is! ObjectType) return fields;
    return {
      for (final MapEntry(key: name, value: field) in fields.entries)
        name: _composeField(parent, field),
    };
  }

  FieldDef<Object?, Object?> _composeField(
    ObjectType parent,
    FieldDef<Object?, Object?> definition,
  ) {
    final lane = definition.lane;
    final schemaField = parent.fieldNamed(definition.name);
    if (lane is! ResolverLane || schemaField == null) return definition;
    final site = FieldSite(parent, schemaField);
    final FieldResolver<C> base = lane.resolve;
    var resolver = base;
    for (final middleware in _chainOf(definition, schemaField).reversed) {
      resolver = middleware(resolver, site);
    }
    if (identical(resolver, base)) return definition;
    final composed = resolver;
    return definition.withLane(
      ResolverLane(
        (parent, arguments, context, info) =>
            composed(parent, arguments, context as C, info),
      ),
    );
  }

  // Global, then the field's own, then the directive slots in the order the
  // directives are applied; the first is outermost.
  List<FieldMiddleware<C>> _chainOf(
    FieldDef<Object?, Object?> definition,
    SchemaField schemaField,
  ) => [
    ..._options.middleware,
    for (final middleware in definition.middleware)
      middleware as FieldMiddleware<C>,
    for (final directive in schemaField.appliedDirectives)
      if (_options.directiveMiddleware[directive.name] case final slot?)
        (next, site) => slot(next, directive),
  ];
}
