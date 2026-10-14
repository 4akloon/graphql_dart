import '../build/built_ins.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'argument_rules.dart';
import 'directive_reference_rules.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the directive definitions of a schema (spec §3.13), as
/// graphql-js's `validateDirectives`: valid names, at least one location,
/// valid arguments and no reference to itself.
final class DirectiveDefinitionRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every problem of the declared directives of [schema].
  void check() {
    _definitions();
    final references = DirectiveReferenceRules(report, schema);
    for (final directive in schema.directives) {
      NameRules(report).check(directive.name, directive.span);
      AppliedDirectiveRules(
        report,
        schema,
      ).check(directive.appliedDirectives, .directiveDefinition);
      if (directive.locations.isEmpty) {
        report.error(
          .missingDirectiveLocations,
          'Directive @${directive.name} must include 1 or more locations.',
          [directive.span],
        );
      }
      ArgumentRules(
        report,
        schema,
      ).check(
        '@${directive.name}',
        directive.arguments,
        isOfDirective: true,
      );
      references.check(directive);
    }
  }

  // The builder drops these from SDL; a schema built in code may hold
  // them.
  void _definitions() {
    for (final directive in schema.directives) {
      if (const BuiltIns().isBuiltInDirective(
        directive.name,
        includesDeferAndStream: schema.includesDeferAndStream,
      )) {
        report.error(
          .builtInRedefinition,
          'The built-in directive "@${directive.name}" cannot be redefined.',
          [directive.span],
        );
      }
    }
    UniqueNames(report).check(
      [
        for (final directive in schema.directives)
          (directive.name, directive.span),
      ],
      .duplicateDirectiveName,
      (name) => 'There can be only one directive named "@$name".',
    );
  }
}
