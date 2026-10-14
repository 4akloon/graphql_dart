import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const type = Name('Query', start: 0, end: 5);
  const field = Name('hero', start: 6, end: 10);
  const argument = Name('episode', start: 11, end: 18);

  test('children are the names in text order', () {
    expect(const TypeCoordinate(type).children, [same(type)]);
    expect(const MemberCoordinate(type, field).children, [
      same(type),
      same(field),
    ]);
    expect(const ArgumentCoordinate(type, field, argument).children, [
      same(type),
      same(field),
      same(argument),
    ]);
    expect(const DirectiveCoordinate(type).children, [same(type)]);
    expect(const DirectiveArgumentCoordinate(type, argument).children, [
      same(type),
      same(argument),
    ]);
  });

  test('withChildren rebuilds every kind of coordinate', () {
    const coordinates = <SchemaCoordinate>[
      TypeCoordinate(type, start: 0, end: 5),
      MemberCoordinate(type, field, start: 0, end: 10),
      ArgumentCoordinate(type, field, argument, start: 0, end: 20),
      DirectiveCoordinate(type, start: 0, end: 6),
      DirectiveArgumentCoordinate(type, argument, start: 0, end: 16),
    ];
    coordinates.forEach(check.expectRebuilds);
  });

  test('a type and a directive with the same name are not equivalent', () {
    expect(
      const TypeCoordinate(type)
          .isEquivalentTo(const DirectiveCoordinate(type)),
      isFalse,
    );
  });

  test('a member coordinate needs both names', () {
    expect(
      () => const MemberCoordinate(type, field).withChildren(const [type]),
      throwsStateError,
    );
  });
}
