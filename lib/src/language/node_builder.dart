import 'comment.dart';
import 'ignored_chars.dart';
import 'source_location.dart';

abstract interface class NodeBuilder {
  NodeBuilder sourceLocation(SourceLocation sourceLocation);

  NodeBuilder comments(List<Comment> comments);

  NodeBuilder ignoredChars(IgnoredChars ignoredChars);

  NodeBuilder additionalData(Map<String, String> additionalData);

  NodeBuilder additionalDataEntry(String key, String value);
}
