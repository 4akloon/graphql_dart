import 'package:typed_graphql/typed_graphql.dart';

import '../config/dart_reference.dart';
import '../config/scalar_mapping.dart';
import 'dart_names.dart';
import 'dart_type.dart';
import 'imports.dart';

/// Maps GraphQL types to the Dart types of generated code and their codecs
/// (spec §7 "Scalars", R7.6, R7.8).
///
/// {@category codegen}
final class TypeMapper {
  /// Creates a mapper over [schema] with the configured custom [scalars].
  const TypeMapper(this.schema, this.scalars);

  /// The schema the type names belong to.
  final Schema schema;

  /// The custom scalar mappings, by scalar name.
  final Map<String, ScalarMapping> scalars;

  static const Map<String, (String, String)> _builtIns =
      <String, (String, String)>{
        'String': ('String', 'StringCodec'),
        'ID': ('String', 'IdCodec'),
        'Int': ('int', 'IntCodec'),
        'Float': ('double', 'FloatCodec'),
        'Boolean': ('bool', 'BooleanCodec'),
      };

  /// The non-null Dart type of the named type [typeName].
  ///
  /// [objectClass] is the generated class an object, interface or union type
  /// maps to; omitting it for one of those is an [ArgumentError].
  DartType named(String typeName, Imports imports, {String? objectClass}) {
    final (String, String)? builtIn = _builtIns[typeName];
    if (builtIn != null) {
      return DartType(
        builtIn.$1,
        'client.ScalarDataCodec(graphql.${builtIn.$2}())',
      );
    }
    return switch (schema.typeNamed(typeName)) {
      ScalarType() => _customScalar(typeName, imports),
      EnumType() || InputObjectType() => _generated(
        const DartNames().typeName(typeName),
      ),
      ObjectType() || InterfaceType() || UnionType() => _generated(
        objectClass ??
            (throw ArgumentError.value(
              objectClass,
              'objectClass',
              'is required for the composite type $typeName',
            )),
      ),
      null => throw ArgumentError.value(
        typeName,
        'typeName',
        'is not a type of the schema',
      ),
    };
  }

  /// The full Dart type of [type], nullable unless wrapped in a non-null.
  DartType of(TypeRef type, Imports imports, {String? objectClass}) =>
      _build(type, imports, objectClass, isOuterNullable: null);

  /// [of] with the outermost nullability removed.
  DartType ofNonNull(TypeRef type, Imports imports, {String? objectClass}) =>
      _build(type, imports, objectClass, isOuterNullable: false);

  DartType _build(
    TypeRef type,
    Imports imports,
    String? objectClass, {
    required bool? isOuterNullable,
  }) {
    // Nullability of each level, outside in: every list, then the named type.
    final List<bool> levels = <bool>[];
    bool isNullable = true;
    TypeRef current = type;
    while (true) {
      switch (current) {
        case NonNullType(type: final inner):
          isNullable = false;
          current = inner;
        case ListType(type: final inner):
          levels.add(isNullable);
          isNullable = true;
          current = inner;
        case NamedType(:final name):
          levels.add(isNullable);
          if (isOuterNullable != null) {
            levels[0] = isOuterNullable;
          }
          return _wrap(
            named(name.value, imports, objectClass: objectClass),
            levels,
          );
      }
    }
  }

  DartType _wrap(DartType base, List<bool> levels) {
    String type = base.type;
    String codec = base.codec;
    for (int index = levels.length - 1; index >= 0; index--) {
      if (levels[index]) {
        type = '$type?';
        codec = 'client.NullableDataCodec($codec)';
      }
      if (index > 0) {
        type = 'List<$type>';
        codec = 'client.ListDataCodec($codec)';
      }
    }
    return DartType(type, codec);
  }

  DartType _generated(String className) =>
      DartType(className, '$className.codec');

  DartType _customScalar(String name, Imports imports) {
    final ScalarMapping? mapping = scalars[name];
    if (mapping == null) {
      return const DartType('graphql.JsonValue', 'client.JsonDataCodec()');
    }
    return DartType(
      _reference(mapping.type, imports),
      'client.ScalarDataCodec(${_reference(mapping.codec, imports)}())',
    );
  }

  String _reference(DartReference reference, Imports imports) =>
      switch (reference.library) {
        final String library =>
          '${imports.prefixFor(library)}.${reference.name}',
        null => reference.name,
      };
}
