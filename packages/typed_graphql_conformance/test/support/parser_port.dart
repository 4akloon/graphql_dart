import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'ast_json.dart';
import 'error_json.dart';

/// graphql-js's parser test helpers over [Parser]: results as graphql-js
/// AST JSON ([AstJson]) and the first diagnostic as `GraphQLError` JSON.
final class ParserPort {
  /// Creates the helpers; [options] stand for graphql-js's parse options.
  const ParserPort({this.options = const ParserOptions()});

  /// The parser options of every call.
  final ParserOptions options;

  Parser get _parser => Parser(options: options);

  /// `parse(text)`, which must succeed; the test fails otherwise.
  Document document(String text) => switch (_parser.parse(Source(text))) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// `toJSONDeep(parse(text))`.
  Object? parse(String text) => const AstJson().of(document(text));

  /// `expectSyntaxError(text)`: the first diagnostic of `parse(text)`.
  Map<String, Object?> syntaxError(String text) =>
      _firstError(_parser.parse(Source(text)).diagnostics);

  /// `toJSONDeep(parseValue(text))`.
  Object? parseValue(String text) =>
      const AstJson().of(_element(_parser.parseValue(Source(text))));

  /// `toJSONDeep(parseConstValue(text))`.
  Object? parseConstValue(String text) => const AstJson().of(
    _element(_parser.parseValue(Source(text), isConst: true)),
  );

  /// `toJSONDeep(parseType(text))`.
  Object? parseType(String text) =>
      const AstJson().of(_element(_parser.parseTypeRef(Source(text))));

  /// `toJSONDeep(parseSchemaCoordinate(text))`.
  Object? parseSchemaCoordinate(String text) => const AstJson().of(
    _element(_parser.parseSchemaCoordinate(Source(text))),
  );

  /// The first diagnostic of `parseSchemaCoordinate(text)`.
  Map<String, Object?> coordinateSyntaxError(String text) =>
      _firstError(_parser.parseSchemaCoordinate(Source(text)).diagnostics);

  /// The first diagnostic of `parseValue(text)`.
  Map<String, Object?> valueSyntaxError(String text) =>
      _firstError(_parser.parseValue(Source(text)).diagnostics);

  /// The first diagnostic of `parseConstValue(text)`.
  Map<String, Object?> constValueSyntaxError(String text) => _firstError(
    _parser.parseValue(Source(text), isConst: true).diagnostics,
  );

  T _element<T extends Node>(ParseElementResult<T> result) => switch (result) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };

  Map<String, Object?> _firstError(List<Diagnostic> diagnostics) {
    if (diagnostics.isEmpty) {
      fail('expected a syntax error');
    }
    return const ErrorJson().of(diagnostics.first);
  }
}
