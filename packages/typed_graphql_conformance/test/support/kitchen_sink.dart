/// graphql-js's kitchen-sink documents (`src/__testUtils__/`), which use
/// every part of the grammar.
abstract final class KitchenSink {
  /// `kitchenSinkQuery`. Dart drops the first line break of a multi-line
  /// literal; graphql-js's text starts with one, so it is put back.
  static const String query =
      '\n'
      r'''
"Query description"
query queryName(
  "Very complex variable"
  $foo: ComplexType,
  $site: Site = MOBILE
) @onQuery {
  whoever123is: node(id: [123, 456]) {
    id
    ... on User @onInlineFragment {
      field2 {
        id
        alias: field1(first: 10, after: $foo) @include(if: $foo) {
          id
          ...frag @onFragmentSpread
        }
      }
    }
    ... @skip(unless: $foo) {
      id
    }
    ... {
      id
    }
  }
}

mutation likeStory @onMutation {
  like(story: 123) @onField {
    story {
      id @onField
    }
  }
}

subscription StoryLikeSubscription(
  $input: StoryLikeSubscribeInput @onVariableDefinition
)
  @onSubscription {
  storyLikeSubscribe(input: $input) {
    story {
      likers {
        count
      }
      likeSentence {
        text
      }
    }
  }
}

"""
  Fragment description
"""
fragment frag on Friend @onFragmentDefinition {
  foo(
    size: $size
    bar: $b
    obj: {
      key: "value"
      block: """
      block string uses \"""
      """
    }
  )
}

{
  unnamed(truthy: true, falsy: false, nullish: null)
  query
}

query {
  __typename
}
''';

  /// `kitchenSinkSDL`, which needs `allowDirectiveExtensions`.
  static const String sdl =
      '\n'
      '''
"""This is a description of the schema as a whole."""
schema {
  query: QueryType
  mutation: MutationType
}

"""
This is a description
of the `Foo` type.
"""
type Foo implements Bar & Baz & Two {
  "Description of the `one` field."
  one: Type
  """
  This is a description of the `two` field.
  """
  two(
    """
    This is a description of the `argument` argument.
    """
    argument: InputType!
  ): Type
  """This is a description of the `three` field."""
  three(argument: InputType, other: String): Int
  four(argument: String = "string"): String
  five(argument: [String] = ["string", "string"]): String
  six(argument: InputType = {key: "value"}): Type
  seven(argument: Int = null): Type
  eight(argument: OneOfInputType): Type
}

type AnnotatedObject @onObject(arg: "value") {
  annotatedField(arg: Type = "default" @onArgumentDefinition): Type @onField
}

type UndefinedType

extend type Foo {
  seven(argument: [String]): Type
}

extend type Foo @onType

interface Bar {
  one: Type
  four(argument: String = "string"): String
}

interface AnnotatedInterface @onInterface {
  annotatedField(arg: Type @onArgumentDefinition): Type @onField
}

interface UndefinedInterface

extend interface Bar implements Two {
  two(argument: InputType!): Type
}

extend interface Bar @onInterface

interface Baz implements Bar & Two {
  one: Type
  two(argument: InputType!): Type
  four(argument: String = "string"): String
}

union Feed =
  | Story
  | Article
  | Advert

union AnnotatedUnion @onUnion = A | B

union AnnotatedUnionTwo @onUnion = | A | B

union UndefinedUnion

extend union Feed = Photo | Video

extend union Feed @onUnion

scalar CustomScalar

scalar AnnotatedScalar @onScalar

extend scalar CustomScalar @onScalar

enum Site {
  """
  This is a description of the `DESKTOP` value
  """
  DESKTOP

  """This is a description of the `MOBILE` value"""
  MOBILE

  "This is a description of the `WEB` value"
  WEB
}

enum AnnotatedEnum @onEnum {
  ANNOTATED_VALUE @onEnumValue
  OTHER_VALUE
}

enum UndefinedEnum

extend enum Site {
  VR
}

extend enum Site @onEnum

input InputType {
  key: String!
  answer: Int = 42
}

input OneOfInputType @oneOf {
  string: String
  int: Int
}

input AnnotatedInput @onInputObject {
  annotatedField: Type @onInputFieldDefinition
}

input UndefinedInput

extend input InputType {
  other: Float = 1.23e4 @onInputFieldDefinition
}

extend input InputType @onInputObject

directive @onDirectiveDefinition on DIRECTIVE_DEFINITION

"""
This is a description of the `@skip` directive
"""
directive @skip(
  """This is a description of the `if` argument"""
  if: Boolean! @onArgumentDefinition
) @onDirectiveDefinition on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

directive @include(if: Boolean!)
  on FIELD
   | FRAGMENT_SPREAD
   | INLINE_FRAGMENT

directive @include2(if: Boolean!) on
  | FIELD
  | FRAGMENT_SPREAD
  | INLINE_FRAGMENT

directive @myRepeatableDir(name: String!) repeatable on
  | OBJECT
  | INTERFACE

extend directive @skip @onDirectiveDefinition

extend schema @onSchema

extend schema @onSchema {
  subscription: SubscriptionType
}
''';
}
