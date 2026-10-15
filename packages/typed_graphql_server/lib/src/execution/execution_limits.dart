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
        'Execution exceeds the limit of ${_options.maxSteps} completed '
        'values.',
        site,
      );
      return false;
    }
    if (site.depth > _options.maxDepth) {
      _reporter.fieldError(
        DiagnosticCode.maxExecutionDepthExceeded,
        'Execution exceeds the maximum depth of ${_options.maxDepth}.',
        site,
      );
      return false;
    }
    return true;
  }
}
