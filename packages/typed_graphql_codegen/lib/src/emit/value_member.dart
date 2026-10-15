/// A member that takes part in the value semantics of a generated class.
final class const ValueMember(
  /// The Dart member name.
  final String name,

  /// Whether its value is a `List`, which `==` and `hashCode` compare by
  /// content through `DataEquality`.
  final bool isList,
) {
  /// Creates a member.
  this;

  /// How `==` reads the member of the compared object.
  String get otherRead => 'other.$name';

  /// How `==` reads the member of this object: a member named `other` would
  /// be shadowed by the parameter.
  String get ownRead => name == 'other' ? 'this.other' : name;

  /// The member read inside a string literal: `$name`, or `${name}` when the
  /// name has a `$` that would end the short form early.
  String get interpolation => name.contains(r'$') ? '\${$name}' : '\$$name';
}
