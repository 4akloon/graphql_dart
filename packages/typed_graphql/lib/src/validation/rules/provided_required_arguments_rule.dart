import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../schema/model/input_value.dart';
import '../meta_fields.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.4.3 "Required Arguments": every non-null argument without a
/// default value is provided (`GQL210`).
///
/// Checked when the field or directive is left, so errors inside it come
/// first, as graphql-js.
///
/// {@category validation}
final class const ProvidedRequiredArgumentsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ProvidedRequiredArguments(context);
}

final class _ProvidedRequiredArguments(final ValidationContext context)
    extends AstVisitor {
  @override
  void leave(Node node) {
    switch (node) {
      case Field():
        _checkField(node);
      case Directive():
        _checkDirective(node);
    }
  }

  void _checkField(Field node) {
    final typeInfo = context.typeInfo;
    final field = typeInfo.fieldDefinition;
    final parent = typeInfo.parentType;
    if (field == null || parent == null) {
      return;
    }
    final provided = {
      for (final argument in node.arguments) argument.name.value,
    };
    // graphql-js names a meta-field `<meta>`: it belongs to no type.
    final owner = identical(field, MetaFields.type) ? '<meta>' : parent.name;
    for (final argument in field.arguments) {
      if (_isMissing(argument, provided)) {
        _report(node, '$owner.${field.name}(${argument.name}:)', argument);
      }
    }
  }

  void _checkDirective(Directive node) {
    final name = node.name.value;
    final definition = context.schema.directiveNamed(name);
    if (definition == null) {
      return;
    }
    final provided = {
      for (final argument in node.arguments) argument.name.value,
    };
    for (final argument in definition.arguments) {
      if (_isMissing(argument, provided)) {
        _report(node, '@$name(${argument.name}:)', argument);
      }
    }
  }

  bool _isMissing(InputValue argument, Set<String> provided) =>
      !provided.contains(argument.name) &&
      argument.type is NonNullType &&
      argument.defaultValue == null;

  void _report(Node node, String coordinate, InputValue argument) {
    final type = const Printer().print(argument.type);
    context.report(
      .providedRequiredArguments,
      'Argument "$coordinate" of type "$type" is required, but it was '
      'not provided.',
      [node],
    );
  }
}
