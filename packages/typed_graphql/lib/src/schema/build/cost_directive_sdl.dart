/// The SDL of the IBM GraphQL Cost Directives draft's `@cost` and
/// `@listSize` (https://ibm.github.io/graphql-specs/cost-spec.html).
///
/// Kept apart from `BuiltInSdl` because the draft is not part of the
/// specification: a schema has these directives only by an opt-in.
final class const CostDirectiveSdl() {
  /// Creates the text holder.
  this;

  /// The two directive definitions, led by a blank line.
  String get text => _text;

  static const String _text = '''

"""
The IBM draft's weight of a schema element in a cost analysis.
"""
directive @cost(
  """The weight, a decimal number written as a string."""
  weight: String!
) on ARGUMENT_DEFINITION | ENUM | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | OBJECT | SCALAR

"""
The IBM draft's size hints for a list field in a cost analysis.
"""
directive @listSize(
  """The size assumed for the list when no slicing argument is given."""
  assumedSize: Int

  """Arguments that limit the size of the list."""
  slicingArguments: [String!]

  """Fields of the returned object that are lists limited like the field."""
  sizedFields: [String!]

  """Whether exactly one slicing argument must be given."""
  requireOneSlicingArgument: Boolean = true
) on FIELD_DEFINITION
''';
}
