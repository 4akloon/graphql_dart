import '../../language/ast/type_ref.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'validation_report.dart';

/// The rule that a directive definition does not reference itself, directly
/// (`directive @d(a: Int @d)`) or through the types and directives it
/// references (spec §3.13 "Type Validation", rules 2 and 3).
///
/// The references form a graph of `@name` (a directive) and `Name` (a
/// type) keys, walked with a stack and a visited set, so a cycle that does
/// not pass through the directive checked ends the walk.
final class DirectiveReferenceRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rule for [schema].
  this;

  /// Reports [directive] when it references itself.
  void check(SchemaDirective directive) {
    final self = '@${directive.name}';
    final visited = <String>{};
    final pending = _ofDirective(directive);
    while (pending.isNotEmpty) {
      final reference = pending.removeLast();
      if (reference == self) {
        report.error(
          .directiveSelfReference,
          'Directive "$self" must not reference itself directly or '
          'indirectly.',
          [directive.span],
        );
        return;
      }
      if (visited.add(reference)) {
        pending.addAll(_of(reference));
      }
    }
  }

  List<String> _of(String reference) {
    if (reference.startsWith('@')) {
      return switch (schema.directiveNamed(reference.substring(1))) {
        final directive? => _ofDirective(directive),
        null => const [],
      };
    }
    return switch (schema.typeNamed(reference)) {
      final type? => _ofType(type),
      null => const [],
    };
  }

  List<String> _ofDirective(SchemaDirective directive) => [
    ..._applied(directive.appliedDirectives),
    for (final argument in directive.arguments) ..._ofInput(argument),
  ];

  List<String> _ofType(SchemaType type) => [
    ..._applied(type.appliedDirectives),
    ...switch (type) {
      ObjectType(:final interfaces, :final fields) ||
      InterfaceType(:final interfaces, :final fields) => [
        for (final interface in interfaces) interface.name,
        for (final field in fields) ..._ofField(field),
      ],
      UnionType(:final memberTypes) => [
        for (final member in memberTypes) member.name,
      ],
      EnumType(:final values) => [
        for (final value in values) ..._applied(value.appliedDirectives),
      ],
      InputObjectType(:final fields) => [
        for (final field in fields) ..._ofInput(field),
      ],
      ScalarType() => const <String>[],
    },
  ];

  List<String> _ofField(SchemaField field) => [
    ..._applied(field.appliedDirectives),
    _named(field.type),
    for (final argument in field.arguments) ..._ofInput(argument),
  ];

  List<String> _ofInput(InputValue input) => [
    ..._applied(input.appliedDirectives),
    _named(input.type),
  ];

  static List<String> _applied(List<AppliedDirective> directives) => [
    for (final directive in directives) '@${directive.name}',
  ];

  static String _named(TypeRef type) =>
      const TypeComparator().namedTypeName(type);
}
