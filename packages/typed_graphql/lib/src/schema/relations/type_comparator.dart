import '../../language/ast/type_ref.dart';

/// Compares type references (spec §3.6.1 `IsValidImplementationFieldType`,
/// graphql-js's `typeComparators`) without recursion, so a deeply wrapped
/// type cannot overflow the stack.
final class const TypeComparator() {
  /// Creates a comparator.
  this;

  /// The name of the named type inside [type]'s list and non-null
  /// wrappers.
  String namedTypeName(TypeRef type) => namedType(type).name.value;

  /// The named type node inside [type]'s list and non-null wrappers.
  NamedType namedType(TypeRef type) {
    var current = type;
    while (true) {
      switch (current) {
        case NamedType():
          return current;
        case ListType(type: final inner) || NonNullType(type: final inner):
          current = inner;
      }
    }
  }

  /// Whether [a] and [b] are the same type: the same wrappers around the
  /// same name.
  bool isEqual(TypeRef a, TypeRef b) {
    var (left, right) = (a, b);
    while (true) {
      switch ((left, right)) {
        case (NamedType(:final name), NamedType(name: final other)):
          return name.value == other.value;
        case (ListType(type: final l), ListType(type: final r)) ||
            (NonNullType(type: final l), NonNullType(type: final r)):
          (left, right) = (l, r);
        case _:
          return false;
      }
    }
  }

  /// Whether a value of type [subType] is always a valid value of
  /// [superType]: equal, or narrower by non-null or by [isNamedSubType]
  /// on the named types (graphql-js's `isTypeSubTypeOf`).
  bool isSubType(
    TypeRef subType,
    TypeRef superType,
    bool Function(String subName, String superName) isNamedSubType,
  ) {
    var (sub, sup) = (subType, superType);
    while (true) {
      switch ((sub, sup)) {
        case (NamedType(:final name), NamedType(name: final other)):
          return name.value == other.value ||
              isNamedSubType(name.value, other.value);
        case (NonNullType(type: final s), NonNullType(type: final t)) ||
            (ListType(type: final s), ListType(type: final t)):
          (sub, sup) = (s, t);
        case (NonNullType(type: final s), _):
          sub = s;
        case _:
          return false;
      }
    }
  }
}
