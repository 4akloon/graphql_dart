import '../../language/ast/name.dart';
import '../../language/ast/type_ref.dart';
import '../../protocol/json_value.dart';
import 'introspection_object.dart';

/// Reads the `TypeRef` objects of an introspection result into type
/// references (graphql-js's `getType` in `buildClientSchema`).
///
/// The `ofType` chain is walked with a loop, so a hostile chain cannot
/// overflow the stack, and it may hold at most [maxWrappers] wrappers: the
/// most `IntrospectionQuery` can ask for. A longer chain is reported, so
/// the type built from a result stays shallow enough for the printers.
final class TypeRefReader(
  /// The names the result's `types` list; a reference to another name is
  /// reported, as graphql-js reports it.
  final Set<String> knownNames,
) {
  /// Creates a reader.
  this;

  /// The most list and non-null wrappers around a named type: an
  /// `IntrospectionQuery` reads `typeDepth` (at most 100) `ofType` levels
  /// below the type.
  static const int maxWrappers = 100;

  /// The type at [key] of [owner]; null, after a report, when it is
  /// absent, malformed, deeper than the query read or names an unknown
  /// type.
  TypeRef? read(IntrospectionObject owner, String key) {
    if (owner.json[key] case null || JsonNull()) {
      owner.report(
        .missingIntrospectionMember,
        'Introspection result missing $key.',
      );
      return null;
    }
    final outer = owner.optionalObject(key);
    return outer == null ? null : _build(outer);
  }

  /// The name of the named type [reference] refers to; null, after a
  /// report, when it has none or the result does not list it.
  String? named(IntrospectionObject reference) {
    final name = reference.string('name');
    if (name == null || knownNames.contains(name)) {
      return name;
    }
    reference.report(
      .unknownIntrospectionType,
      'Invalid or incomplete schema, unknown type: $name. Ensure that a '
      'full introspection query is used in order to build a client schema.',
    );
    return null;
  }

  TypeRef? _build(IntrospectionObject outer) {
    final wrappers = <IntrospectionObject>[];
    var level = outer;
    while (_isWrapper(level)) {
      wrappers.add(level);
      if (wrappers.length > maxWrappers || _isUnwrapped(level)) {
        level.report(
          .introspectionTypeTooDeep,
          'Decorated type deeper than introspection query.',
        );
        return null;
      }
      if (level.optionalObject('ofType') case final inner?) {
        level = inner;
      } else {
        return null;
      }
    }
    final name = named(level);
    return name == null ? null : _wrap(NamedType(Name(name)), wrappers);
  }

  bool _isUnwrapped(IntrospectionObject level) =>
      switch (level.json['ofType']) {
        null || JsonNull() => true,
        _ => false,
      };

  bool _isWrapper(IntrospectionObject level) =>
      switch (level.optionalString('kind')) {
        'LIST' || 'NON_NULL' => true,
        _ => false,
      };

  // Wraps from the innermost wrapper out.
  TypeRef? _wrap(TypeRef named, List<IntrospectionObject> wrappers) {
    var type = named;
    for (final wrapper in wrappers.reversed) {
      if (wrapper.optionalString('kind') == 'LIST') {
        type = ListType(type);
      } else if (type is NonNullType) {
        wrapper.report(
          .malformedIntrospectionMember,
          'Expected a nullable type inside NON_NULL.',
        );
        return null;
      } else {
        type = NonNullType(type);
      }
    }
    return type;
  }
}
