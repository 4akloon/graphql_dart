import 'package:typed_graphql/typed_graphql.dart';

import 'schema_port.dart';

/// graphql-js's `buildSchema`, `extendSchema` and `validateSchema` as the
/// ported validation tests use them, with each error as graphql-js's
/// message and locations.
final class ValidationPort {
  /// Creates the helpers; they keep no state.
  const ValidationPort();

  static const SchemaPort _schemas = SchemaPort();

  /// graphql-js's `buildSchema` of a template literal written as a Dart
  /// multi-line literal, which drops the line break right after its
  /// opening quotes: the break is restored, so lines count as in
  /// graphql-js.
  Schema build(String sdl) => _schemas.build('\n$sdl');

  /// graphql-js's `extendSchema` of [schema] with [sdl], restored as
  /// [build] restores it.
  Schema extend(Schema schema, String sdl) => _schemas.extend(schema, '\n$sdl');

  /// The text of graphql-js's `SomeSchema`, whose types the tests that
  /// build a schema in code reference.
  static const String someSdl = '''
scalar SomeScalar
interface SomeInterface { f: SomeObject }
type SomeObject implements SomeInterface { f: SomeObject }
union SomeUnion = SomeObject
enum SomeEnum { ONLY }
input SomeInputObject { val: String = "hello" }
directive @SomeDirective on QUERY''';

  /// The types of graphql-js's `SomeSchema`.
  List<SchemaType> get someTypes => _schemas.build(someSdl).types;

  /// graphql-js's `withModifiers`: the type named [name], as a list, as
  /// non-null and as a non-null list, written as GraphQL text.
  List<String> withModifiers(String name) => [
    name,
    '[$name]',
    '$name!',
    '[$name]!',
  ];

  /// A schema built in code of [types] and [directives], whose query root
  /// is `Query`.
  Schema schema(
    List<SchemaType> types, {
    List<SchemaDirective> directives = const [],
  }) => Schema(types: types, directives: directives, queryTypeName: 'Query');

  /// graphql-js's `schemaWithFieldType`: a `Query` root whose field `f`
  /// has [type], beside [type] and [types].
  Schema withFieldType(SchemaType type, {List<SchemaType> types = const []}) =>
      schema([
        ObjectType(
          'Query',
          fields: [SchemaField('f', NamedType(Name(type.name)))],
        ),
        type,
        ...types,
      ]);

  /// graphql-js's `validateSchema(schema)` as `expectJSON` compares it:
  /// each error as its message, then ` @ ` and its locations
  /// (`line:column`, the place first, then the related spans) when it has
  /// any.
  List<String> errors(Schema schema) => [
    for (final diagnostic
        in const SchemaValidator().validate(schema).diagnostics)
      _printed(diagnostic),
  ];

  String _printed(Diagnostic diagnostic) {
    final locations = [
      for (final span in [?diagnostic.span, ...diagnostic.related])
        '${span.location.line}:${span.location.column}',
    ];
    return switch (locations) {
      [] => diagnostic.message,
      _ => '${diagnostic.message} @ ${locations.join(' ')}',
    };
  }
}
