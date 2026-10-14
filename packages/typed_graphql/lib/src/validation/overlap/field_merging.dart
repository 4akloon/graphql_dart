import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../validation_context.dart';
import 'argument_text.dart';
import 'conflict_judge.dart';
import 'conflict_reports.dart';
import 'field_origin.dart';
import 'field_shape.dart';
import 'fragment_path.dart';
import 'merge_item.dart';
import 'merge_split.dart';
import 'merge_work.dart';
import 'selection_collector.dart';

/// Spec §5.3.2 "Field Selection Merging" without comparing every pair of
/// fields (R3.3; XING's algorithm, which Sangria uses).
///
/// Each operation is a root, and so is each fragment that no earlier root
/// expanded: a fragment's own conflicts are found wherever it is
/// expanded, so a chain of fragments is merged once, not once per link
/// (graphql-js checks every fragment again). A root's fields are merged
/// level by level: each set of fields with one response name is split
/// into classes ([MergeSplit]), the pairs that may conflict are judged
/// ([ConflictJudge]) and each class's subfields form the sets of the next
/// level, depth first over an explicit stack. Every field merged and every
/// pair compared charges the step budget.
final class FieldMerging(
  /// The run the work is charged to and reported in.
  final ValidationContext context,
  final Map<Field, FieldOrigin> origins,
) {
  /// Creates the check of the fields [origins] describes.
  this;

  final FieldShape _shapes = FieldShape(context.schema);
  final ArgumentText _arguments = ArgumentText();
  final ConflictReports _reports = ConflictReports(context);
  final Set<String> _expanded = {};

  /// Reports the conflicts of every root.
  void check() {
    for (final definition in context.document.definitions) {
      if (context.isAborted || _reports.isFull) {
        break;
      }
      switch (definition) {
        case FragmentDefinition(:final name)
            when _expanded.contains(name.value):
          continue;
        case final ExecutableDefinition root:
          _checkRoot(root);
      }
    }
    _reports.flush();
  }

  void _checkRoot(ExecutableDefinition root) {
    final path = FragmentPath();
    final SelectionSet selectionSet;
    switch (root) {
      case OperationDefinition():
        selectionSet = root.selectionSet;
      case FragmentDefinition():
        selectionSet = root.selectionSet;
        path.enter([root.name.value]);
    }
    final merge = _RootMerge(
      SelectionCollector(context, origins, path),
      MergeSplit(context, _shapes, _arguments),
      ConflictJudge(context, _shapes, _arguments, root),
    );
    final steps = <_Step>[];
    merge.descend(steps, const MergeWork([]), [(selectionSet, null)]);
    while (steps.isNotEmpty && !context.isAborted && !_reports.isFull) {
      switch (steps.removeLast()) {
        case _Enter(:final fragments):
          path.enter(fragments);
          _expanded.addAll(fragments);
        case _Leave(:final fragments):
          path.leave(fragments);
        case _Visit(:final work):
          merge.visit(steps, work, _reports);
      }
    }
  }
}

/// The merge of one root: its collector, splitter and judge.
final class _RootMerge(
  final SelectionCollector collector,
  final MergeSplit splitter,
  final ConflictJudge judge,
) {
  /// Judges the pairs of [work] into [reports] and puts the sets under
  /// each of its classes on [steps].
  void visit(List<_Step> steps, MergeWork work, ConflictReports reports) {
    final (:pairs, :parts) = splitter.split(work);
    for (final pair in pairs) {
      if (reports.isFull) return;
      if (judge.judge(pair) case final conflict?) reports.add(conflict);
    }
    final descents = [
      for (final part in parts)
        (
          part,
          [
            for (final item in part.items)
              if (item.node.selectionSet case final selectionSet?)
                (selectionSet, item),
          ],
        ),
    ];
    for (final (part, sources) in descents.reversed) {
      descend(steps, part, sources);
    }
  }

  /// Collects the fields of [sources] and puts their sets on [steps],
  /// checked as [part] is, between entering and leaving the fragments
  /// expanded to find them.
  void descend(
    List<_Step> steps,
    MergeWork part,
    List<(SelectionSet, MergeItem?)> sources,
  ) {
    final (:groups, :expanded) = collector.collect(sources);
    steps.add(_Leave(expanded));
    for (final items in groups.values.toList().reversed) {
      steps.add(
        _Visit(
          MergeWork(
            items,
            checksShape: part.checksShape,
            checksNames: part.checksNames,
          ),
        ),
      );
    }
    steps.add(_Enter(expanded));
  }
}

sealed class _Step {}

final class _Enter(final List<String> fragments) extends _Step;

final class _Leave(final List<String> fragments) extends _Step;

final class _Visit(final MergeWork work) extends _Step;
