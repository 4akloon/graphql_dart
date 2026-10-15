import '../../diagnostics/suggestions.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/build/built_ins.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.2 "Fragment Spread Type Existence" and §5.8.2 "Variables
/// Are Input Types": every type a type condition or a variable definition
/// names exists (`GQL212`).
///
/// As graphql-js, the types the document itself defines are known. The
/// built-in scalars and introspection types are always known: graphql-js's
/// extra case for them inside a type system definition only matters when
/// there is no schema, and a validated document always has one.
///
/// {@category validation}
final class const KnownTypeNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownTypeNames(context);
}

final class _KnownTypeNames extends AstVisitor {
  _KnownTypeNames(this.context) {
    const builtIns = BuiltIns();
    for (final type in [
      ...context.schema.types,
      ...builtIns.scalars,
      ...builtIns.introspectionTypes,
    ]) {
      _typeNames.add(type.name);
    }
    for (final definition in context.document.definitions) {
      if (definition case TypeDefinition(:final name)) {
        _typeNames.add(name.value);
      }
    }
  }

  final ValidationContext context;
  final Set<String> _typeNames = {};

  @override
  VisitAction enter(Node node) {
    if (node case NamedType(:final name)
        when !_typeNames.contains(name.value)) {
      const suggestions = Suggestions();
      final suggested = context.includesSuggestions
          ? suggestions.listFor(name.value, _typeNames)
          : const <String>[];
      context.report(
        .knownTypeNames,
        'Unknown type "${name.value}".${suggestions.didYouMean(suggested)}',
        [node],
      );
    }
    return .next;
  }
}
