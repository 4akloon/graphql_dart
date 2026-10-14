import '../../diagnostics/source_span.dart';
import '../model/named_type_reference.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'implementation_rules.dart';
import 'type_reference_rules.dart';
import 'validation_report.dart';

typedef _Context = ({
  List<NamedTypeReference> interfaces,
  Set<String> declared,
  Set<String> implemented,
  Map<String, SchemaField> fieldsByName,
});

/// The rules of the interfaces an object or interface type implements
/// (spec §3.6, §3.7 "Type Validation"), as graphql-js's
/// `validateInterfaces`: each is a known interface type, other than the
/// type itself, named once; the type also implements the interfaces it
/// inherits, and implements each interface's fields.
final class InterfaceRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of the [interfaces] of [type], whose fields are
  /// [fields].
  void check(
    SchemaType type,
    List<NamedTypeReference> interfaces,
    List<SchemaField> fields,
  ) {
    final context = (
      interfaces: interfaces,
      declared: {for (final reference in interfaces) reference.name},
      implemented: <String>{},
      // The first of two fields with one name counts.
      fieldsByName: {for (final field in fields.reversed) field.name: field},
    );
    for (final reference in interfaces) {
      if (report.isFull) {
        return;
      }
      if (!TypeReferenceRules(
        report,
        schema,
      ).isKnown(reference.name, reference.span)) {
        continue;
      }
      _reference(type, reference, context);
    }
  }

  void _reference(
    SchemaType type,
    NamedTypeReference reference,
    _Context context,
  ) {
    final (:interfaces, :declared, :implemented, :fieldsByName) = context;
    switch (schema.typeNamed(reference.name)) {
      case final InterfaceType interface when interface.name == type.name:
        report.error(
          .circularImplementation,
          'Type ${type.name} cannot implement itself because it would '
          'create a circular reference.',
          _spansOf(interfaces, interface.name),
        );
      case final InterfaceType interface when !implemented.add(interface.name):
        report.error(
          .repeatedInterface,
          'Type ${type.name} can only implement ${interface.name} once.',
          _spansOf(interfaces, interface.name),
        );
      case final InterfaceType interface:
        _ancestors(type, interfaces, declared, interface);
        ImplementationRules(
          report,
          schema,
        ).check(type, fieldsByName, interface);
      case final other?:
        _notInterface(type, interfaces, other);
      case null:
        break;
    }
  }

  void _notInterface(
    SchemaType type,
    List<NamedTypeReference> interfaces,
    SchemaType other,
  ) => report.error(
    .implementsNonInterface,
    'Type ${type.name} must only implement Interface types, it cannot '
    'implement ${other.name}.',
    _spansOf(interfaces, other.name),
  );

  // graphql-js's validateTypeImplementsAncestors (spec §3.7, "the
  // implementing type must also implement the interfaces it inherits").
  void _ancestors(
    SchemaType type,
    List<NamedTypeReference> interfaces,
    Set<String> declared,
    InterfaceType interface,
  ) {
    for (final transitive in interface.interfaces) {
      if (schema.typeNamed(transitive.name) == null ||
          declared.contains(transitive.name)) {
        continue;
      }
      final spans = [
        ..._spansOf(interface.interfaces, transitive.name),
        ..._spansOf(interfaces, interface.name),
      ];
      if (transitive.name == type.name) {
        report.error(
          .circularImplementation,
          'Type ${type.name} cannot implement ${interface.name} because it '
          'would create a circular reference.',
          spans,
        );
      } else {
        report.error(
          .missingTransitiveInterface,
          'Type ${type.name} must implement ${transitive.name} because it is '
          'implemented by ${interface.name}.',
          spans,
        );
      }
    }
  }

  static List<SourceSpan?> _spansOf(
    List<NamedTypeReference> references,
    String name,
  ) => [
    for (final reference in references)
      if (reference.name == name) reference.span,
  ];
}
