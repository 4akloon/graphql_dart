import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// An SDL text parsed for a schema test: its [source] and its [document],
/// which the test expects to have no syntax errors.
final class Sdl {
  /// Parses [text], named `schema.graphql`; directive extensions are on,
  /// as the working draft allows them.
  Sdl(String text) : this._(Source(text, name: 'schema.graphql'));

  Sdl._(this.source) : document = _parse(source);

  /// The parsed text.
  final Source source;

  /// The parsed document.
  final Document document;

  /// The definitions of [document] of type [T], in order.
  List<T> all<T extends Definition>() =>
      document.definitions.whereType<T>().toList();

  static Document _parse(Source source) {
    const parser = Parser(
      options: ParserOptions(allowDirectiveExtensions: true),
    );
    return switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final diagnostics) => fail('$diagnostics'),
    };
  }
}
