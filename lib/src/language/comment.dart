import 'package:graphql_dart/src/language/source_location.dart';

class Comment {
  final String content;
  final SourceLocation sourceLocation;

  Comment(this.content, this.sourceLocation);
}
