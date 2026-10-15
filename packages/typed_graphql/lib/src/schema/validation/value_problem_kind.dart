/// Which rule of spec §5.6 a value problem breaks, so that operation
/// validation reports each with the code of its own rule.
enum ValueProblemKind {
  /// A value of the wrong type (spec §5.6.1 "Values of Correct Type").
  invalid,

  /// An input object field the type does not have (spec §5.6.2 "Input
  /// Object Field Names").
  unknownField,

  /// A required input object field that is missing (spec §5.6.4 "Input
  /// Object Required Fields").
  missingField,
}
