import 'package:typed_graphql/typed_graphql.dart';

import 'completion_site.dart';
import 'error_reporter.dart';
import 'execution_options.dart';

/// Counts the values an execution completes and refuses the ones past
/// `ExecutionOptions.maxDepth` or `maxSteps` (spec 16).
final class ExecutionLimits {
  /// Counts for one execution under [options].
  ExecutionLimits(this._options, this._reporter);

  final ExecutionOptions _options;
  final ErrorReporter _reporter;
  int _steps = 0;

  /// Whether the value at [site] may be completed. A refusal is already
  /// reported: a field error for depth, a halt for steps.
  bool admits(CompletionSite site) {
    if (_reporter.log.isHalted) {
      return false;
    }
    _steps++;
    if (_steps > _options.maxSteps) {
      _reporter.halt(
        DiagnosticCode.maxExecutionStepsExceeded,
        stepsExceededMessage,
        site,
      );
      return false;
    }
    return admitsDepth(site);
  }

  /// The text of the error for a run past `maxSteps`.
  String get stepsExceededMessage =>
      'Execution exceeds the limit of ${_options.maxSteps} completed values.';

  /// Spends [steps] on a look-ahead and says whether they fit under
  /// `maxSteps`. A refusal spends nothing and ends nothing: the look-ahead
  /// throws, which fails its field only.
  bool spend(int steps) {
    if (_reporter.log.isHalted || _steps + steps > _options.maxSteps) {
      return false;
    }
    _steps += steps;
    return true;
  }

  /// Whether the place [site] is within `maxDepth`; a refusal is already
  /// reported as a field error. Costs no step, so a field can be refused
  /// before its resolver runs.
  bool admitsDepth(CompletionSite site) {
    if (site.depth <= _options.maxDepth) {
      return true;
    }
    _reporter.fieldError(
      DiagnosticCode.maxExecutionDepthExceeded,
      'Execution exceeds the maximum depth of ${_options.maxDepth}.',
      site,
    );
    return false;
  }
}
