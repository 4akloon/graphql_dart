import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's schema test helpers (`buildSchema`, `printSchema`,
/// `expectPrintedSchema`, `cycleSDL`, `buildSingleFieldSchema`) and the
/// parts a ported test builds a schema from: type references, constant
/// values and applied directives written as GraphQL text.
final class SchemaPort {
  /// Creates the helpers; they keep no state.
  const SchemaPort();

  static const Parser _parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true),
  );

  /// [text] as a type reference, such as `[String!]`.
  TypeRef type(String text) => _element(_parser.parseTypeRef(Source(text)));

  /// A reference to the type named [name], as an interface or a union
  /// member.
  NamedType named(String name) => NamedType(Name(name));

  /// [text] as a constant value, such as `{ a: 1 }`.
  Value value(String text) =>
      _element(_parser.parseValue(Source(text), isConst: true));

  /// The directives applied in [text], such as `@deprecated(reason: "x")`.
  List<AppliedDirective> applied(String text) {
    final directives = switch (_document('scalar Applied $text').definitions) {
      [ScalarTypeDefinition(:final directives)] => directives,
      _ => fail('Not directives: $text'),
    };
    return [
      for (final directive in directives)
        AppliedDirective(
          directive.name.value,
          arguments: directive.arguments,
        ),
    ];
  }

  /// graphql-js's `buildSchema`: [sdl] built; fails the test on a
  /// diagnostic.
  Schema build(String sdl) =>
      switch (const SchemaBuilder().fromSdl(_document(sdl))) {
        BuildSuccess(:final schema) => schema,
        BuildFailure(:final diagnostics) => fail('$diagnostics'),
      };

  /// graphql-js's `printSchema`.
  String print(Schema schema) => const SchemaPrinter().print(schema);

  /// graphql-js's `expectPrintedSchema`: [schema] printed, after checking
  /// that building and printing the text gives it back.
  String printed(Schema schema) {
    final text = print(schema);
    expect(print(build(text)), text);
    return text;
  }

  /// graphql-js's `cycleSDL`: [sdl] built and printed.
  String cycle(String sdl) => print(build(sdl));

  /// graphql-js's `buildSingleFieldSchema`: a `Query` root whose one
  /// field, `singleField`, has [type], [arguments] and [description].
  Schema singleField(
    String type, {
    List<InputValue> arguments = const [],
    String? description,
  }) => Schema(
    types: [
      ObjectType(
        'Query',
        fields: [
          SchemaField(
            'singleField',
            this.type(type),
            arguments: arguments,
            description: description,
          ),
        ],
      ),
    ],
    queryTypeName: 'Query',
  );

  /// An argument or input field named [name] of [type], with the default
  /// value written as [defaultValue].
  InputValue input(String name, String type, {String? defaultValue}) =>
      InputValue(
        name,
        this.type(type),
        defaultValue: defaultValue == null ? null : value(defaultValue),
      );

  Document _document(String sdl) => switch (_parser.parse(Source(sdl))) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  T _element<T extends Node>(ParseElementResult<T> result) => switch (result) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };
}
