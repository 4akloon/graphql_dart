import 'package:graphql_dart/src/language/ignored_chars.dart';

import 'abstract_node.dart';
import 'comment.dart';
import 'described_node.dart';
import 'description.dart';
import 'node.dart';

abstract interface class AbstractDescribedNode<T extends Node<dynamic>>
    extends AbstractNode<T> implements DescribeNode<T> {
  final Description? _description;

  AbstractDescribedNode({
    IgnoredChars? ignoredChars,
    List<Comment> comments = const [],
    Map<String, String> additionalData = const {},
    super.sourceLocation,
    Description? description,
  })  : _description = description,
        super(
          ignoredChars: ignoredChars ?? IgnoredChars.empty(),
          comments: comments,
          additionalData: additionalData,
        );

  @override
  Description? get description => _description;
}
