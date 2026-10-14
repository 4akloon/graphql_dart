import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'validation_port.dart';

/// graphql-js's validation harness (`validation/__tests__/harness.ts`): one
/// rule checked against `testSchema` or another schema, each error as
/// `expectJSON` compares it.
final class RulePort {
  /// Checks documents with [rule] against [schema], graphql-js's
  /// `testSchema` by default.
  RulePort(ValidationRule rule, {ValidSchema? schema})
    : this.all([rule], schema: schema);

  /// Checks documents with [rules] together: a graphql-js rule that M4
  /// splits into several (section 5 of the M4 spec).
  RulePort.all(this.rules, {ValidSchema? schema})
    : schema = schema ?? testSchema;

  /// The rules the tests check.
  final List<ValidationRule> rules;

  /// The schema documents are validated against.
  final ValidSchema schema;

  /// graphql-js's `testSchema`, built once.
  static final ValidSchema testSchema = RulePort.validated(_testSdl);

  /// [sdl] built as graphql-js's `buildSchema` builds a template literal,
  /// and validated: graphql-js's `validate` asserts a valid schema.
  static ValidSchema validated(String sdl) =>
      switch (const SchemaValidator().validate(
        const ValidationPort().build(sdl),
      )) {
        final ValidSchema valid => valid,
        InvalidSchema(:final diagnostics) => fail('$diagnostics'),
      };

  /// graphql-js's `expectValidationErrorsWithSchema`: the same rules
  /// against the schema built from [sdl].
  RulePort withSchema(String sdl) =>
      RulePort.all(rules, schema: validated(sdl));

  /// The errors of [query], a template literal written as a Dart
  /// multi-line literal (its first line break is restored, so lines count
  /// as in graphql-js): each the message, then ` @ ` and its locations
  /// when it has any. [hidesSuggestions] is graphql-js's
  /// `hideSuggestions`.
  List<String> errors(String query, {bool hidesSuggestions = false}) {
    final source = Source('\n$query');
    final document = switch (const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final diagnostics) => fail('$diagnostics'),
    };
    final validator = DocumentValidator(
      rules: rules,
      includesSuggestions: !hidesSuggestions,
    );
    return [
      for (final diagnostic
          in validator.validate(schema, document, source: source).diagnostics)
        _printed(diagnostic),
    ];
  }

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

  static const String _testSdl = '''
  interface Mammal {
    mother: Mammal
    father: Mammal
  }

  interface Pet {
    name(surname: Boolean): String
  }

  interface Canine implements Mammal {
    name(surname: Boolean): String
    mother: Canine
    father: Canine
  }

  enum DogCommand {
    SIT
    HEEL
    DOWN
  }

  scalar GeoPoint

  type Dog implements Pet & Mammal & Canine {
    name(surname: Boolean): String
    nickname: String
    barkVolume: Int
    barks: Boolean
    doesKnowCommand(dogCommand: DogCommand): Boolean
    isHouseTrained(atOtherHomes: Boolean = true): Boolean
    isAtLocation(x: Int, y: Int): Boolean
    distanceFrom(loc: GeoPoint): Float
    mother: Dog
    father: Dog
  }

  type Cat implements Pet {
    name(surname: Boolean): String
    nickname: String
    meows: Boolean
    meowsVolume: Int
    furColor: FurColor
  }

  union CatOrDog = Cat | Dog

  type Human {
    name(surname: Boolean): String
    pets: [Pet]
    relatives: [Human]!
  }

  enum FurColor {
    BROWN
    BLACK
    TAN
    SPOTTED
    NO_FUR
    UNKNOWN
  }

  input ComplexInput {
    requiredField: Boolean!
    nonNullField: Boolean! = false
    intField: Int
    stringField: String
    booleanField: Boolean
    stringListField: [String]
  }

  input OneOfInput @oneOf {
    stringField: String
    intField: Int
  }

  type ComplicatedArgs {
    # TODO List
    # TODO Coercion
    # TODO NotNulls
    intArgField(intArg: Int): String
    nonNullIntArgField(nonNullIntArg: Int!): String
    stringArgField(stringArg: String): String
    booleanArgField(booleanArg: Boolean): String
    enumArgField(enumArg: FurColor): String
    floatArgField(floatArg: Float): String
    idArgField(idArg: ID): String
    stringListArgField(stringListArg: [String]): String
    stringListNonNullArgField(stringListNonNullArg: [String!]): String
    complexArgField(complexArg: ComplexInput): String
    oneOfArgField(oneOfArg: OneOfInput): String
    multipleReqs(req1: Int!, req2: Int!): String
    nonNullFieldWithDefault(arg: Int! = 0): String
    multipleOpts(opt1: Int = 0, opt2: Int = 0): String
    multipleOptAndReq(req1: Int!, req2: Int!, opt1: Int = 0, opt2: Int = 0): String
  }

  type QueryRoot {
    human(id: ID): Human
    dog: Dog
    cat: Cat
    pet: Pet
    catOrDog: CatOrDog
    complicatedArgs: ComplicatedArgs
  }

  schema {
    query: QueryRoot
  }

  directive @onField on FIELD
''';
}
