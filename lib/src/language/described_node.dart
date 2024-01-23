import 'description.dart';
import 'node.dart';

abstract interface class DescribeNode<T extends Node<dynamic>>
    implements Node<T> {
  Description? get description;
}
