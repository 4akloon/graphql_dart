import '../emit/dart_names.dart';

/// Names the classes generated for operations, fragments and selections.
final class ClassNames {
  /// Creates the class namer.
  const ClassNames();

  static const DartNames _names = DartNames();

  /// The class of an operation's data: `GetUser` is `GetUserData`.
  String operationData(String operationName) =>
      '${_names.typeName(operationName)}Data';

  /// The class of a fragment definition.
  String fragment(String fragmentName) => _names.typeName(fragmentName);

  /// The class of the field [memberName] of the class [owner].
  String nested(String owner, String memberName) =>
      '$owner${_names.capitalized(memberName)}';

  /// The class that holds the fragments spread on the class [owner].
  String holder(String owner) => '${owner}Fragments';
}
