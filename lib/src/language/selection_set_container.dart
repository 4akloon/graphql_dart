import 'package:graphql_dart/src/language/selection_set.dart';

import 'node.dart';

abstract interface class SelectionSetContainer<T extends Node<dynamic>>
    implements Node<T> {
  SelectionSet? get selectionSet;
}
