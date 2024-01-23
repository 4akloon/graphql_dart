import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'argument.dart';
import 'node.dart';

abstract interface class NodeVisitor {
  TraversalControl visitArgument(Argument node, TraverserContext<Node> context);
}
