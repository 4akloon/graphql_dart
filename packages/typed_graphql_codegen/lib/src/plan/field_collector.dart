import 'package:typed_graphql/typed_graphql.dart';

import 'applicability.dart';
import 'collected_selection.dart';
import 'condition.dart';
import 'directive_conditions.dart';
import 'field_group.dart';
import 'fragment_use.dart';
import 'narrowing.dart';
import 'selection_source.dart';
import 'type_condition_match.dart';

/// Collects the fields, fragment uses and narrowing conditions of selection
/// sets for a parent type (spec §6). It walks with an explicit stack.
final class const FieldCollector(
  /// The schema the fields are looked up in.
  final Schema schema,

  /// The fragment definitions of the project, by name.
  final Map<String, FragmentDefinition> fragments,
) {
  /// Creates a collector.
  this;

  /// Collects [sources], in order, for [parent].
  CollectedSelection collect(SchemaType parent, List<SelectionSource> sources) {
    final run = _Run(schema, fragments, parent);
    for (final source in sources) {
      run.visit(source);
    }
    return run.result();
  }
}

typedef _Pending = (Selection, bool, List<Condition>);

final class _GroupBuilder {
  _GroupBuilder(this.fieldName, this.definition);

  final String fieldName;
  final SchemaField definition;
  final List<Field> nodes = [];
  bool isConditional = true;
}

final class _Run {
  _Run(this.schema, this.fragments, this.parent)
    : applicability = Applicability(schema);

  static const _conditions = DirectiveConditions();

  final Schema schema;
  final Map<String, FragmentDefinition> fragments;
  final SchemaType parent;
  final Applicability applicability;
  final Map<String, _GroupBuilder> groups = {};
  final Map<String, FragmentUse> uses = {};
  final List<Narrowing> narrowings = [];
  bool selectsTypename = false;

  CollectedSelection result() => CollectedSelection(
    [
      for (final MapEntry(key: responseName, value: group) in groups.entries)
        FieldGroup(
          responseName,
          group.fieldName,
          group.nodes,
          isConditional: group.isConditional,
          definition: group.definition,
        ),
    ],
    uses.values.toList(),
    narrowings,
    selectsTypename: selectsTypename,
  );

  void visit(SelectionSource source) {
    final stack = <_Pending>[];
    void push(SelectionSet set, bool isConditional, List<Condition> held) {
      for (final selection in set.selections.reversed) {
        stack.add((selection, isConditional, held));
      }
    }

    push(source.selectionSet, source.isConditional, source.conditions);
    while (stack.isNotEmpty) {
      final (selection, isConditional, held) = stack.removeLast();
      final own = _conditions.of(switch (selection) {
        Field(:final directives) ||
        FragmentSpread(:final directives) ||
        InlineFragment(:final directives) => directives,
      });
      if (own == null) {
        continue;
      }
      final all = [...held, ...own];
      final isNowConditional = isConditional || own.isNotEmpty;
      switch (selection) {
        case Field():
          _field(selection, isNowConditional);
        case InlineFragment():
          final inner = _inline(selection, isNowConditional, all);
          if (inner != null) {
            push(inner.selectionSet, isNowConditional, all);
          }
        case FragmentSpread():
          _spread(selection, all);
      }
    }
  }

  /// The inline fragment's source when it applies to the parent; a
  /// narrowing is recorded here, a `never` fragment is dropped.
  SelectionSource? _inline(
    InlineFragment fragment,
    bool isConditional,
    List<Condition> conditions,
  ) {
    final name = fragment.typeCondition?.name.value ?? parent.name;
    final source = SelectionSource(
      fragment.selectionSet,
      isConditional: isConditional,
      conditions: conditions,
    );
    switch (applicability.match(name, parent)) {
      case TypeConditionMatch.applies:
        return source;
      case TypeConditionMatch.narrows:
        narrowings.add(Narrowing(name, source: source));
      case TypeConditionMatch.never:
        break;
    }
    return null;
  }

  void _field(Field field, bool isConditional) {
    final fieldName = field.name.value;
    final responseName = field.alias?.value ?? fieldName;
    if (field.alias == null && fieldName == '__typename') {
      selectsTypename = true;
      return;
    }
    final definition = _definition(fieldName);
    if (definition == null) {
      return;
    }
    final group = groups[responseName] ??= _GroupBuilder(
      fieldName,
      definition,
    );
    group.nodes.add(field);
    group.isConditional = group.isConditional && isConditional;
  }

  void _spread(FragmentSpread spread, List<Condition> conditions) {
    final name = spread.name.value;
    final definition = fragments[name];
    if (definition == null) {
      return;
    }
    final condition = definition.typeCondition.name.value;
    switch (applicability.match(condition, parent)) {
      case TypeConditionMatch.applies:
        final existing = uses[name];
        uses[name] = existing == null
            ? FragmentUse(name, [conditions])
            : existing.merge(conditions);
      case TypeConditionMatch.narrows:
        narrowings.add(
          Narrowing(condition, fragmentName: name, conditions: conditions),
        );
      case TypeConditionMatch.never:
        break;
    }
  }

  /// Null for a field the parent lacks, which validation rules out.
  SchemaField? _definition(String fieldName) {
    if (fieldName == '__typename') {
      return _typename;
    }
    return switch (parent) {
      final ObjectType type => type.fieldNamed(fieldName),
      final InterfaceType type => type.fieldNamed(fieldName),
      _ => null,
    };
  }

  static final SchemaField _typename = SchemaField(
    '__typename',
    const NonNullType(NamedType(Name('String'))),
  );
}
