import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/relations/type_comparator.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const comparator = TypeComparator();
  const dog = NamedType(Name('Dog'));
  const cat = NamedType(Name('Cat'));

  TypeRef deep(TypeRef inner, int depth) {
    var type = inner;
    for (var i = 0; i < depth; i++) {
      type = ListType(type);
    }
    return type;
  }

  bool never(String sub, String sup) => false;

  test('finds the name inside the wrappers', () {
    expect(comparator.namedTypeName(const NonNullType(ListType(dog))), 'Dog');
  });

  test('equal types have the same wrappers and name', () {
    expect(
      comparator.isEqual(const ListType(dog), const ListType(dog)),
      isTrue,
    );
    expect(
      comparator.isEqual(const ListType(dog), const ListType(cat)),
      isFalse,
    );
    expect(comparator.isEqual(const NonNullType(dog), dog), isFalse);
  });

  test('a non-null type is a sub type of its nullable form', () {
    expect(comparator.isSubType(const NonNullType(dog), dog, never), isTrue);
    expect(comparator.isSubType(dog, const NonNullType(dog), never), isFalse);
  });

  test('named types defer to the given relation', () {
    expect(comparator.isSubType(dog, cat, never), isFalse);
    expect(comparator.isSubType(dog, cat, (sub, sup) => sub == 'Dog'), isTrue);
  });

  test('deeply wrapped types compare without recursion', () {
    final a = deep(dog, 100000);
    final b = deep(dog, 100000);
    expect(comparator.namedTypeName(a), 'Dog');
    expect(comparator.isEqual(a, b), isTrue);
    expect(comparator.isSubType(a, b, never), isTrue);
  });
}
