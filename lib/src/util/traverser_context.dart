import 'breadcrumb.dart';
import 'node_location.dart';

enum Phase { leave, enter, backref }

abstract interface class TraverserContext<T> {
  T thisNode();

  T originalThisNode();

  void changeNode(T newNode);

  void deleteNode();

  bool isDeleted();

  bool isChanged();

  TraverserContext<T> getParentContext();

  List<T> getParentNodes();

  T getParentNode();

  List<Breadcrumb<T>> getBreadcrumbs();

  NodeLocation getLocation();

  bool isVisited();

  Set<T> visitedNodes();

  S? getVar<S>();

  S? getVarFromParent<S>();

  TraverserContext<T> setVar<S>(S value);

  void setAccumulate(Object accumulate);

  U getNewAccumulate<U>();

  U getCurrentAccumulate<U>();

  U getSharedContextData<U>();

  bool isRootContext();

  Map<String, List<TraverserContext<T>>> getChildrenContexts();

  Phase getPhase();

  bool isParallel();
}
