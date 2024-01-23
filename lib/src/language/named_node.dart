import 'node.dart';

abstract interface class NamedNode<T extends NamedNode<dynamic>>
    implements Node<T> {
  String? get name;
}
