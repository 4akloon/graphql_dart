import 'abstract_node.dart';
import 'comment.dart';
import 'described_node.dart';
import 'description.dart';
import 'ignored_chars.dart';
import 'node.dart';

abstract class AbstractDescribedNode<T extends Node<dynamic>>
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
