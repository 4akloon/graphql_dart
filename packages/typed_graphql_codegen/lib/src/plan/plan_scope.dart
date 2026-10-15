import 'class_registry.dart';
import 'plan_work.dart';

/// What planning one class needs besides the class: the [registry] of the
/// whole run and the list its nested work is added to.
final class PlanScope {
  /// Creates the scope of one class in a run that shares [registry].
  PlanScope(this.registry);

  /// The nested classes the run has planned so far.
  final ClassRegistry registry;

  /// The work under the class, in the order it is emitted.
  final List<PlanWork> children = [];
}
