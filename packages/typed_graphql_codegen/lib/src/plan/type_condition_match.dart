/// How a type condition relates to the parent type it is written in.
enum TypeConditionMatch {
  /// The condition covers every value of the parent, now and later.
  applies,

  /// The parent is abstract and the condition selects some of its values.
  narrows,

  /// No value of the parent can satisfy the condition.
  never,
}
