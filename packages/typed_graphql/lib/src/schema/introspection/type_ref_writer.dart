import '../../language/ast/name.dart';
import '../../language/ast/type_ref.dart';
import '../../protocol/json_value.dart';
import '../model/schema_type.dart';
import '../schema.dart';

/// Writes type references as the introspection query's `TypeRef` fragment
/// reads them: `kind`, `name` and `ofType`, [typeDepth] levels deep.
final class TypeRefWriter(
  /// The schema whose types the references name.
  final Schema schema,

  /// How many `ofType` levels a reference has.
  final int typeDepth,
) {
  /// Creates a writer.
  this;

  /// [type] with its wrappers as nested `ofType` objects; a wrapper below
  /// [typeDepth] levels has no `ofType` key, as the query does not read it.
  ///
  /// A named type the schema lacks is an [ArgumentError]: introspection
  /// describes a valid schema.
  JsonObject reference(TypeRef type) {
    final levels = <TypeRef>[];
    for (
      TypeRef? level = type;
      level != null && levels.length <= typeDepth;
      level = _wrapped(level)
    ) {
      levels.add(level);
    }
    // Built from the innermost level out, so nesting needs no recursion.
    var result = _level(levels.last, levels.length - 1, null);
    for (var depth = levels.length - 2; depth >= 0; depth--) {
      result = _level(levels[depth], depth, result);
    }
    return result;
  }

  /// The type named [name] as a reference, as the query reads an
  /// implemented interface or a possible type.
  JsonObject named(String name) => reference(NamedType(Name(name)));

  /// The `__TypeKind` value of [type].
  String kindOf(SchemaType type) => switch (type) {
    ScalarType() => 'SCALAR',
    ObjectType() => 'OBJECT',
    InterfaceType() => 'INTERFACE',
    UnionType() => 'UNION',
    EnumType() => 'ENUM',
    InputObjectType() => 'INPUT_OBJECT',
  };

  /// The kind of the type named [name]; an [ArgumentError] when the schema
  /// has no such type.
  String kindNamed(String name) => switch (schema.typeNamed(name)) {
    final type? => kindOf(type),
    null => throw ArgumentError.value(
      name,
      'name',
      'is not a type of the schema; validate the schema first',
    ),
  };

  // [inner] is the level below, null below a named type or at the cut.
  JsonObject _level(TypeRef type, int depth, JsonObject? inner) {
    final (kind, name) = _kindAndName(type);
    return JsonObject({
      'kind': JsonString(kind),
      'name': name == null ? const JsonNull() : JsonString(name),
      if (depth < typeDepth) 'ofType': inner ?? const JsonNull(),
    });
  }

  TypeRef? _wrapped(TypeRef type) => switch (type) {
    NamedType() => null,
    ListType(:final type) || NonNullType(:final type) => type,
  };

  (String, String?) _kindAndName(TypeRef type) => switch (type) {
    NamedType(:final name) => (kindNamed(name.value), name.value),
    ListType() => ('LIST', null),
    NonNullType() => ('NON_NULL', null),
  };
}
