import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../fragment_spread_collector.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.2.2 "Fragment spreads must not form cycles": a fragment does
/// not spread itself, directly or through other fragments (`GQL216`).
///
/// A depth-first search as graphql-js's, but with an explicit stack: a
/// chain of a hundred thousand fragments must not overflow the call stack,
/// on the web least of all. Each spread followed is charged to the step
/// budget.
///
/// {@category validation}
final class const NoFragmentCyclesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoFragmentCycles(context);
}

/// A fragment on the search stack and how many of its spreads were taken.
final class _Frame(final String name, final List<FragmentSpread> spreads) {
  int nextIndex = 0;
}

final class _NoFragmentCycles(final ValidationContext context)
    extends AstVisitor {
  // Fragments already searched: keeps the work linear and reports a cycle
  // once.
  final Set<String> _visited = {};
  // The spreads from the search root to the current fragment.
  final List<FragmentSpread> _spreadPath = [];
  // Where each fragment on the stack starts in _spreadPath.
  final Map<String, int> _pathIndexByName = {};

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition():
        return .skip;
      case final FragmentDefinition fragment:
        _search(fragment);
        return .skip;
      default:
        return .next;
    }
  }

  void _search(FragmentDefinition root) {
    if (context.isAborted) {
      return;
    }
    final frames = <_Frame>[];
    _open(root, frames);
    while (frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.nextIndex == frame.spreads.length) {
        _pathIndexByName.remove(frame.name);
        frames.removeLast();
        if (frames.isNotEmpty) {
          _spreadPath.removeLast();
        }
        continue;
      }
      // A full sink ignores reports: stop, as the budget does.
      if (context.isAborted ||
          !_follow(frame.spreads[frame.nextIndex++], frames)) {
        frames.clear();
        _spreadPath.clear();
        _pathIndexByName.clear();
      }
    }
  }

  // Takes one spread; false once the step budget is spent.
  bool _follow(FragmentSpread spread, List<_Frame> frames) {
    if (!context.spend(1)) {
      return false;
    }
    final spreadName = spread.name.value;
    _spreadPath.add(spread);
    if (_pathIndexByName[spreadName] case final cycleStart?) {
      // The message and the path copy cost the cycle's length.
      if (!context.spend(_spreadPath.length - cycleStart)) {
        return false;
      }
      _reportCycle(spreadName, _spreadPath.sublist(cycleStart));
    } else if (context.fragmentNamed(spreadName) case final target?) {
      // The path stays while the target's frame is open.
      if (_open(target, frames)) {
        return true;
      }
    }
    _spreadPath.removeLast();
    return true;
  }

  // Opens a frame for [fragment]; false when it was searched already or
  // spreads nothing.
  bool _open(FragmentDefinition fragment, List<_Frame> frames) {
    final name = fragment.name.value;
    if (!_visited.add(name)) {
      return false;
    }
    final spreads = const FragmentSpreadCollector().collect(
      fragment.selectionSet,
    );
    if (spreads.isEmpty) {
      return false;
    }
    _pathIndexByName[name] = _spreadPath.length;
    frames.add(_Frame(name, spreads));
    return true;
  }

  void _reportCycle(String spreadName, List<FragmentSpread> cyclePath) {
    final via = [
      for (final spread in cyclePath.take(cyclePath.length - 1))
        '"${spread.name.value}"',
    ].join(', ');
    context.report(
      .noFragmentCycles,
      'Cannot spread fragment "$spreadName" within itself'
      '${via.isEmpty ? '.' : ' via $via.'}',
      cyclePath,
    );
  }
}
