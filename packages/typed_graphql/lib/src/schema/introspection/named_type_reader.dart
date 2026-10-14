import '../model/named_type_reference.dart';
import '../model/schema_type.dart';
import 'introspection_annotations.dart';
import 'introspection_object.dart';
import 'member_reader.dart';

/// Reads one type of an introspection result's `types` by its `kind`
/// (graphql-js's `buildType`).
///
/// A type without a member its kind needs is reported and kept with no
/// such members, so references to it still resolve. Kinds are not checked
/// against their uses (a field of an input type, a union member that is
/// not an object): schema validation reports those, as for SDL.
final class NamedTypeReader(
  /// Reads the members of the types.
  final MemberReader members,
) {
  /// Creates a reader.
  this;

  static const IntrospectionAnnotations _annotations =
      IntrospectionAnnotations();

  /// The type [type] describes; null, after a report, without a name or
  /// with a kind that is not a named type kind.
  SchemaType? read(IntrospectionObject type) {
    final name = type.string('name');
    if (name == null) {
      return null;
    }
    final description = type.optionalString('description');
    final kind = type.optionalString('kind');
    switch (kind) {
      case 'SCALAR':
        final directives = _annotations.specifiedBy(type);
        return ScalarType(
          name,
          description: description,
          appliedDirectives: directives,
        );
      case 'OBJECT':
        return ObjectType(
          name,
          description: description,
          interfaces: _references(type.list('interfaces')),
          fields: members.fields(type),
        );
      case 'INTERFACE':
        // graphql-js reads a null `interfaces` of an interface as none,
        // for servers older than interfaces implementing interfaces.
        return InterfaceType(
          name,
          description: description,
          interfaces: _references(type.optionalList('interfaces')),
          fields: members.fields(type),
        );
      default:
        return _other(type, kind, name, description);
    }
  }

  // The kinds without fields, and the unknown ones.
  SchemaType? _other(
    IntrospectionObject type,
    String? kind,
    String name,
    String? text,
  ) {
    switch (kind) {
      case 'UNION':
        final possible = type.list('possibleTypes');
        return UnionType(
          name,
          description: text,
          memberTypes: _references(possible),
        );
      case 'ENUM':
        return EnumType(
          name,
          description: text,
          values: members.enumValues(type),
        );
      case 'INPUT_OBJECT':
        final fields = type.list('inputFields') ?? const [];
        return InputObjectType(
          name,
          description: text,
          fields: members.inputValues(fields),
          appliedDirectives: _annotations.oneOf(type),
        );
      default:
        type.report(
          .unknownIntrospectionKind,
          'Invalid or incomplete introspection result. Ensure that a full '
          'introspection query is used in order to build a client schema.',
        );
        return null;
    }
  }

  List<NamedTypeReference> _references(List<IntrospectionObject>? objects) => [
    for (final object in objects ?? const <IntrospectionObject>[])
      if (members.types.named(object) case final name?)
        NamedTypeReference(name),
  ];
}
