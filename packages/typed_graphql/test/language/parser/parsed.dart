import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// The result of parsing one text, for tests.
final class Parsed {
  /// Parses [text] with [options].
  Parsed(String text, {ParserOptions options = const ParserOptions()})
    : result = Parser(options: options).parse(Source(text));

  /// The parse result.
  final ParseResult result;

  /// The document, which the test expects to have no errors.
  Document get document => switch (result) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// The partial document, which the test expects to have errors.
  Document get partial => switch (result) {
    ParseSuccess() => fail('expected syntax errors'),
    ParseFailure(:final partial) => partial,
  };

  /// Each diagnostic as `line:column id message`.
  List<String> get errors => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];

  /// The only definition of [document].
  T single<T extends Definition>() => document.definitions.single as T;
}
