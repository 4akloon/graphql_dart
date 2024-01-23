import 'source_location.dart';

class Description {
  final String content;
  final SourceLocation sourceLocation;
  final bool isMultiLine;

  Description({
    required this.content,
    required this.sourceLocation,
    required this.isMultiLine,
  });
}
