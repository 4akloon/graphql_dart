import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'rebuild_check.dart';

void main() {
  const check = RebuildCheck();
  const name = Name('v', start: 1, end: 2);

  group('Value', () {
    test('a variable has its name as its only child', () {
      expect(const Variable(name).children, [same(name)]);
    });

    test('scalar values have no children', () {
      const leaves = <Value>[
        IntValue('1'),
        FloatValue('1.5'),
        StringValue('s'),
        BooleanValue(true),
        NullValue(),
        EnumValue('RED'),
      ];
      for (final leaf in leaves) {
        expect(leaf.children, isEmpty, reason: '$leaf');
      }
    });

    test('a list has its items and an object its fields as children', () {
      const field = ObjectField(Name('a'), IntValue('1'));
      expect(ListValue(const [NullValue()]).children, [isA<NullValue>()]);
      expect(ObjectValue(const [field]).children, [same(field)]);
    });

    test('withChildren rebuilds every kind of value', () {
      final values = <Value>[
        const Variable(name, start: 0, end: 2),
        const IntValue('-12', start: 3, end: 6),
        const FloatValue('1.5e3'),
        const StringValue('s', isBlock: true),
        const BooleanValue(false),
        const NullValue(),
        const EnumValue('RED'),
        ListValue(const [Variable(name), IntValue('1')], start: 4, end: 9),
        ObjectValue([
          const ObjectField(Name('a'), Variable(name), start: 1, end: 5),
        ]),
      ];
      values.forEach(check.expectRebuilds);
    });

    test('a scalar value rejects children', () {
      expect(
        () => const IntValue('1').withChildren(const [name]),
        throwsStateError,
      );
    });
  });

  group('TypeRef', () {
    const named = NamedType(Name('Int'), start: 1, end: 4);

    test('wrappers have the wrapped type as their only child', () {
      expect(const ListType(named).children, [same(named)]);
      expect(const NonNullType(named).children, [same(named)]);
    });

    test('withChildren rebuilds every kind of type', () {
      const types = <TypeRef>[
        named,
        ListType(named, start: 0, end: 5),
        NonNullType(ListType(NonNullType(named)), start: 0, end: 7),
      ];
      types.forEach(check.expectRebuilds);
    });
  });
}
