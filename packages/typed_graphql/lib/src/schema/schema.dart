import '../diagnostics/source_span.dart';
import '../language/ast/operation_type.dart';
import '../language/ast/schema_coordinate.dart';
import '../language/ast/type_ref.dart';
import '../protocol/json_value.dart';
import 'build/built_ins.dart';
import 'coordinates/coordinate_resolver.dart';
import 'coordinates/coordinate_target.dart';
import 'introspection/introspection_query.dart';
import 'introspection/introspection_writer.dart';
import 'model/applied_directive.dart';
import 'model/schema_directive.dart';
import 'model/schema_type.dart';
import 'relations/implementation_index.dart';
import 'relations/type_comparator.dart';

/// A GraphQL schema (spec §3.3; R2.1): its named types, its directive
/// definitions and its root operation types, immutable.
///
/// It holds what was declared, in declaration order; the built-in scalars,
/// directives and introspection types of [BuiltIns] exist in every schema
/// and are found by [typeNamed] and [directiveNamed] without being listed.
/// Building does not validate: a reference may name a type that does not
/// exist, and a root may name a type of the wrong kind.
///
/// {@category schema}
final class Schema({
  List<SchemaType> types = const [],
  List<SchemaDirective> directives = const [],

  /// The name of the query root type; null when there is none.
  final String? queryTypeName,

  /// The name of the mutation root type; null when there is none.
  final String? mutationTypeName,

  /// The name of the subscription root type; null when there is none.
  final String? subscriptionTypeName,

  /// The description of the schema definition, if any.
  final String? description,
  List<AppliedDirective> appliedDirectives = const [],

  Map<OperationType, SourceSpan> rootTypeSpans = const {},

  /// Whether `@defer` and `@stream` exist in this schema (an opt-in, as
  /// graphql-js defines them; R2.6).
  final bool includesDeferAndStream = false,

  /// Where the schema definition was; null without one.
  final SourceSpan? span,
}) {
  /// Creates a schema.
  this;

  /// The declared named types, in declaration order; built-ins are not
  /// listed.
  final List<SchemaType> types = List.unmodifiable(types);

  /// The declared directive definitions, in declaration order; built-ins
  /// are not listed.
  final List<SchemaDirective> directives = List.unmodifiable(directives);

  /// The directives applied to the schema definition and its extensions.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  // Only for lookups, never iterated.
  final Map<OperationType, SourceSpan> _rootTypeSpans = Map.unmodifiable(
    rootTypeSpans,
  );

  // Only for lookups, never iterated. Built from the end, so the first of
  // two types with one name wins, as the builder keeps the first.
  final Map<String, SchemaType> _typesByName = {
    for (final type in types.reversed) type.name: type,
  };

  // Same rule as _typesByName: the first declared directive wins.
  final Map<String, SchemaDirective> _directivesByName = {
    for (final directive in directives.reversed) directive.name: directive,
  };

  // Late: built on the first question about implementations, from the
  // final list of types, which never changes after construction.
  late final ImplementationIndex _implementations = ImplementationIndex(
    types,
  );

  /// The declared type named [name], else the built-in scalar or
  /// introspection type; null when there is none.
  SchemaType? typeNamed(String name) {
    if (_typesByName[name] case final type?) {
      return type;
    }
    return const BuiltIns().typeNamed(name);
  }

  /// The declared directive named [name], else the built-in one; null
  /// when there is none.
  SchemaDirective? directiveNamed(String name) {
    if (_directivesByName[name] case final directive?) {
      return directive;
    }
    const builtIns = BuiltIns();
    return switch (name) {
      'defer' when includesDeferAndStream => builtIns.defer,
      'stream' when includesDeferAndStream => builtIns.stream,
      _ => builtIns.directiveNamed(name),
    };
  }

  /// Where the root type of [operation] was named, as `query: Query` in a
  /// schema definition or extension; null when it was not named in SDL.
  SourceSpan? rootTypeSpan(OperationType operation) =>
      _rootTypeSpans[operation];

  /// The name of the root type of [operation]; null when there is none.
  String? rootTypeName(OperationType operation) => switch (operation) {
    .query => queryTypeName,
    .mutation => mutationTypeName,
    .subscription => subscriptionTypeName,
  };

  /// This schema as the `data` of its answer to [query] (graphql-js's
  /// `introspectionFromSchema`; spec §4), which `SchemaBuilder`'s
  /// `fromIntrospection` reads back.
  ///
  /// It describes a schema that validation accepts: a reference to a type
  /// the schema lacks is an [ArgumentError].
  JsonObject toIntrospection([
    IntrospectionQuery query = IntrospectionQuery.full,
  ]) => IntrospectionWriter(this, query).write();

  /// The element [coordinate] names (spec §9); null when the schema has
  /// none, also when an element that contains it is missing or of the
  /// wrong kind. Meta-fields and introspection types have no coordinate.
  CoordinateTarget? resolve(SchemaCoordinate coordinate) =>
      CoordinateResolver(this).resolve(coordinate);

  /// The named type inside [type]'s wrappers; null when no type has its
  /// name.
  SchemaType? namedTypeOf(TypeRef type) =>
      typeNamed(const TypeComparator().namedTypeName(type));

  /// Whether [type] names an input type (spec §3.4.2); false when its
  /// named type does not exist.
  bool isInputType(TypeRef type) => namedTypeOf(type)?.isInputType ?? false;

  /// Whether [type] names an output type (spec §3.4.2); false when its
  /// named type does not exist.
  bool isOutputType(TypeRef type) => namedTypeOf(type)?.isOutputType ?? false;

  /// The object and interface types that declare [interfaceType] in their
  /// `implements` list, in declaration order.
  List<SchemaType> implementations(InterfaceType interfaceType) =>
      _implementations.of(interfaceType.name);

  /// The object types a value of [type] can be at run time, in
  /// declaration order: the object itself, the members of a union that
  /// are objects, or the objects that implement an interface.
  List<ObjectType> possibleTypes(SchemaType type) => switch (type) {
    ObjectType() => [type],
    InterfaceType() => implementations(type).whereType<ObjectType>().toList(),
    UnionType(:final memberTypes) => [
      for (final member in memberTypes)
        if (typeNamed(member.name) case final ObjectType object) object,
    ],
    ScalarType() || EnumType() || InputObjectType() => const [],
  };

  /// Whether [maybeSubType] is a member of the union [abstractType] or
  /// declares the interface [abstractType] (graphql-js's `isSubType`).
  bool isSubType(SchemaType abstractType, SchemaType maybeSubType) =>
      switch (abstractType) {
        UnionType(:final memberTypes) => memberTypes.any(
          (member) => member.name == maybeSubType.name,
        ),
        InterfaceType() => implementations(abstractType).contains(maybeSubType),
        _ => false,
      };

  /// Whether a value of type [subType] is always a value of [superType]
  /// (graphql-js's `isTypeSubTypeOf`): the same type, or narrower by
  /// non-null, or an implementation or member of an abstract type.
  bool isTypeSubTypeOf(TypeRef subType, TypeRef superType) =>
      const TypeComparator().isSubType(subType, superType, (sub, sup) {
        final (subNamed, superNamed) = (typeNamed(sub), typeNamed(sup));
        return subNamed != null &&
            superNamed != null &&
            (subNamed is ObjectType || subNamed is InterfaceType) &&
            isSubType(superNamed, subNamed);
      });

  /// Whether some object type is possible for both [a] and [b]
  /// (graphql-js's `doTypesOverlap`).
  bool typesOverlap(SchemaType a, SchemaType b) {
    if (identical(a, b)) {
      return true;
    }
    final possible = possibleTypes(b);
    return possibleTypes(a).any(possible.contains);
  }
}
