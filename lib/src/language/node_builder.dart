import 'comment.dart';
import 'ignored_chars.dart';
import 'source_location.dart';

abstract class NodeBuilder<T extends NodeBuilder<dynamic>> {
  SourceLocation? sourceLocation;
  List<Comment> comments;
  IgnoredChars ignoredChars;
  Map<String, String> additionalData;

  NodeBuilder({
    this.sourceLocation,
    IgnoredChars? ignoredChars,
    this.comments = const [],
    Map<String, String> additionalData = const {},
  })  : ignoredChars = ignoredChars ?? IgnoredChars.empty(),
        additionalData = {...additionalData};

  void setAdditionalDataEntry(String key, String value) =>
      additionalData[key] = value;
}
