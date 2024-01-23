import 'comment.dart';
import 'ignored_chars.dart';
import 'source_location.dart';

abstract class NodeBuilder<T extends NodeBuilder<dynamic>> {
  SourceLocation? sourceLocation;
  List<Comment> _comments;
  IgnoredChars ignoredChars;
  Map<String, String> additionalData;

  NodeBuilder({
    this.sourceLocation,
    IgnoredChars? ignoredChars,
    List<Comment> comments = const [],
    Map<String, String> additionalData = const {},
  })  : ignoredChars = ignoredChars ?? IgnoredChars.empty(),
        _comments = List.unmodifiable(comments),
        additionalData = {...additionalData};

  List<Comment> get comments => _comments;

  set comments(List<Comment> comments) {
    _comments = List.unmodifiable(comments);
  }

  void setAdditionalDataEntry(String key, String value) =>
      additionalData[key] = value;
}
