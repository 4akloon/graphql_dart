import '../../language/ast/directive_location.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../model/applied_directive.dart';
import '../model/schema_directive.dart';
import '../schema.dart';
import 'node_span.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the directives applied to a schema element (spec §3.13,
/// §5.7): the directive is defined, allowed at the element's location and
/// used once unless repeatable; its arguments are defined, unique and
/// every required one is given.
///
/// graphql-js checks these on SDL before building (`KnownDirectivesRule`,
/// `UniqueDirectivesPerLocationRule`, `KnownArgumentNamesOnDirectivesRule`,
/// `UniqueArgumentNamesRule`, `ProvidedRequiredArgumentsOnDirectivesRule`);
/// the messages are theirs.
final class AppliedDirectiveRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema whose directives are defined.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [directives], applied at [location].
  void check(List<AppliedDirective> directives, DirectiveLocation location) {
    // Only for lookups; the errors follow the order of [directives].
    final firstUses = <String, AppliedDirective>{};
    for (final applied in directives) {
      final definition = schema.directiveNamed(applied.name);
      if (definition == null) {
        report.error(
          .unknownDirective,
          'Unknown directive "@${applied.name}".',
          [applied.span],
        );
        continue;
      }
      if (!definition.locations.contains(location)) {
        report.error(
          .misplacedDirective,
          'Directive "@${applied.name}" may not be used on '
          '${location.spelling}.',
          [applied.span],
        );
      }
      if (firstUses[applied.name] case final first?
          when !definition.isRepeatable) {
        report.error(
          .repeatedDirective,
          'The directive "@${applied.name}" can only be used once at this '
          'location.',
          [first.span, applied.span],
        );
      }
      firstUses.putIfAbsent(applied.name, () => applied);
      _arguments(applied, definition);
    }
  }

  void _arguments(AppliedDirective applied, SchemaDirective definition) {
    UniqueNames(report).check(
      [
        for (final argument in applied.arguments)
          (
            argument.name.value,
            const NodeSpan().within(applied.span, argument),
          ),
      ],
      .duplicateDirectiveArgument,
      (name) => 'There can be only one argument named "$name".',
    );
    for (final argument in applied.arguments) {
      if (definition.argumentNamed(argument.name.value) == null) {
        report.error(
          .unknownDirectiveArgument,
          'Unknown argument "${argument.name.value}" on directive '
          '"@${definition.name}".',
          [const NodeSpan().within(applied.span, argument)],
        );
      }
    }
    for (final parameter in definition.arguments) {
      if (parameter.type is NonNullType &&
          parameter.defaultValue == null &&
          applied.argument(parameter.name) == null) {
        report.error(
          .missingDirectiveArgument,
          'Argument "@${definition.name}(${parameter.name}:)" of type '
          '"${const Printer().print(parameter.type)}" is required, but it '
          'was not provided.',
          [applied.span],
        );
      }
    }
  }
}
