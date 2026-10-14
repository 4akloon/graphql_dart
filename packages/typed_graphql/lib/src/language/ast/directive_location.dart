/// A place where a directive may be applied (spec §3.13,
/// `DirectiveLocation`): the nineteen locations of the September2025
/// edition and the working draft's [directiveDefinition].
///
/// A directive definition names its locations in [spelling]: `FIELD`,
/// `INPUT_FIELD_DEFINITION`. The values are in the order of the spec's
/// grammar, executable locations first.
///
/// {@category language}
enum DirectiveLocation(
  /// The name a directive definition and introspection use, such as
  /// `FIELD_DEFINITION`.
  final String spelling,
) {
  /// `QUERY`: a query operation.
  query('QUERY'),

  /// `MUTATION`: a mutation operation.
  mutation('MUTATION'),

  /// `SUBSCRIPTION`: a subscription operation.
  subscription('SUBSCRIPTION'),

  /// `FIELD`: a field of a selection set.
  field('FIELD'),

  /// `FRAGMENT_DEFINITION`: a fragment definition.
  fragmentDefinition('FRAGMENT_DEFINITION'),

  /// `FRAGMENT_SPREAD`: a fragment spread.
  fragmentSpread('FRAGMENT_SPREAD'),

  /// `INLINE_FRAGMENT`: an inline fragment.
  inlineFragment('INLINE_FRAGMENT'),

  /// `VARIABLE_DEFINITION`: a variable definition of an operation.
  variableDefinition('VARIABLE_DEFINITION'),

  /// `SCHEMA`: the schema definition or a schema extension.
  schema('SCHEMA'),

  /// `SCALAR`: a scalar type.
  scalar('SCALAR'),

  /// `OBJECT`: an object type.
  object('OBJECT'),

  /// `FIELD_DEFINITION`: a field of an object or interface type.
  fieldDefinition('FIELD_DEFINITION'),

  /// `ARGUMENT_DEFINITION`: an argument of a field or a directive.
  argumentDefinition('ARGUMENT_DEFINITION'),

  /// `INTERFACE`: an interface type.
  interface('INTERFACE'),

  /// `UNION`: a union type.
  union('UNION'),

  /// `ENUM`: an enum type.
  enumType('ENUM'),

  /// `ENUM_VALUE`: a value of an enum type.
  enumValue('ENUM_VALUE'),

  /// `INPUT_OBJECT`: an input object type.
  inputObject('INPUT_OBJECT'),

  /// `INPUT_FIELD_DEFINITION`: a field of an input object type.
  inputFieldDefinition('INPUT_FIELD_DEFINITION'),

  /// `DIRECTIVE_DEFINITION`: a directive definition; working draft only
  /// (`ParserOptions.allowDirectiveExtensions`).
  directiveDefinition('DIRECTIVE_DEFINITION');

  /// The location spelled [spelling]; null when there is none.
  static DirectiveLocation? named(String spelling) {
    for (final location in values) {
      if (location.spelling == spelling) {
        return location;
      }
    }
    return null;
  }

  /// Whether it is a place in an operation, not in a schema (spec §3.13,
  /// `ExecutableDirectiveLocation`).
  bool get isExecutable => index <= variableDefinition.index;
}
