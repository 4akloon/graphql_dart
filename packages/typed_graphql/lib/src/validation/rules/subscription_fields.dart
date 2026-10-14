import '../../language/ast/directive.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../../language/ast/type_ref.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import '../validation_context.dart';

/// The top-level fields of a subscription grouped by response key, as
/// graphql-js's `collectFields` gathers them with `@skip` and `@include`
/// forbidden (spec §5.2.4.1 `CollectSubscriptionFields`).
final class SubscriptionFields {
  /// Collects [selectionSet] for [root], following the fragments of
  /// [context] each once.
  ///
  /// The selections are walked with a stack, so deeply nested inline
  /// fragments cannot overflow the call stack.
  SubscriptionFields(
    ValidationContext context,
    ObjectType root,
    SelectionSet selectionSet,
  ) {
    final visited = <String>{};
    final pending = [...selectionSet.selections.reversed];
    while (pending.isNotEmpty && context.spend(1)) {
      final selection = pending.removeLast();
      if (_isForbidden(selection)) {
        continue;
      }
      switch (selection) {
        case Field():
          (fields[(selection.alias ?? selection.name).value] ??= []).add(
            selection,
          );
        case InlineFragment(:final typeCondition, :final selectionSet):
          if (_matches(context.schema, typeCondition, root)) {
            pending.addAll(selectionSet.selections.reversed);
          }
        case FragmentSpread(:final name):
          final fragment = context.fragmentNamed(name.value);
          if (fragment != null &&
              _matches(context.schema, fragment.typeCondition, root) &&
              visited.add(name.value)) {
            pending.addAll(fragment.selectionSet.selections.reversed);
          }
      }
    }
  }

  /// The fields by response key, in the order they were first selected.
  final Map<String, List<Field>> fields = {};

  /// The `@skip` and `@include` directives found, in document order.
  final List<Directive> forbiddenDirectives = [];

  // graphql-js's `shouldIncludeNode` with `forbidSkipAndInclude`: the
  // first `@skip`, else the first `@include`, makes the selection
  // forbidden.
  bool _isForbidden(Selection selection) {
    final directives = switch (selection) {
      Field(:final directives) ||
      InlineFragment(:final directives) ||
      FragmentSpread(:final directives) => directives,
    };
    for (final name in const ['skip', 'include']) {
      for (final directive in directives) {
        if (directive.name.value == name) {
          forbiddenDirectives.add(directive);
          return true;
        }
      }
    }
    return false;
  }

  // graphql-js's `doesFragmentConditionMatch`.
  static bool _matches(Schema schema, NamedType? condition, ObjectType root) {
    if (condition == null) {
      return true;
    }
    return switch (schema.typeNamed(condition.name.value)) {
      final type? when identical(type, root) => true,
      final InterfaceType type => schema.isSubType(type, root),
      final UnionType type => schema.isSubType(type, root),
      _ => false,
    };
  }
}
