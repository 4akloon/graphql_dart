import 'package:test/test.dart';
import 'package:typed_graphql/src/language/ast/child_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const a = Name('a');
  const b = Name('b');
  const one = IntValue('1');

  group('ChildReader', () {
    test('rebuild keeps the node when every child is identical', () {
      const field = ObjectField(a, one);
      final rebuilt = ChildReader(const [a, one]).rebuild(
        field,
        (read) => fail('nothing changed, so nothing is built'),
      );
      expect(identical(rebuilt, field), isTrue);
    });

    test('one throws a StateError when the child is missing', () {
      expect(() => ChildReader(const []).one<Name>(), throwsStateError);
    });

    test('one throws a StateError for a child of another kind', () {
      expect(() => ChildReader(const [one]).one<Name>(), throwsStateError);
    });

    test('optional consumes nothing when the next child is another kind', () {
      final read = ChildReader(const [one]);
      expect(read.optional<Name>(), isNull);
      expect(read.one<IntValue>(), same(one));
    });

    test('all reads the run of one kind and stops at another', () {
      final read = ChildReader(const [a, b, one]);
      expect(read.all<Name>(), [same(a), same(b)]);
      expect(read.all<Name>(), isEmpty);
      expect(read.one<Value>(), same(one));
    });

    test('rebuild throws a StateError for a child left over', () {
      expect(
        () => const ObjectField(a, one).withChildren(const [b, one, one]),
        throwsStateError,
      );
    });
  });

  group('NonNullType', () {
    test('withChildren throws a StateError for a non-null child', () {
      const type = NonNullType(NamedType(a));
      expect(
        () => type.withChildren(const [NonNullType(NamedType(b))]),
        throwsStateError,
      );
    });
  });

  group('isEquivalentTo', () {
    test('ignores positions', () {
      expect(
        const ObjectField(a, one).isEquivalentTo(
          const ObjectField(
            Name('a', start: 4, end: 5),
            IntValue('1', start: 7, end: 8),
            start: 4,
            end: 8,
          ),
        ),
        isTrue,
      );
    });

    test('compares raw lexemes, so 1.0 differs from 1.00', () {
      expect(
        const FloatValue('1.0').isEquivalentTo(const FloatValue('1.00')),
        isFalse,
      );
    });

    test('compares the kind of the node', () {
      expect(const IntValue('1').isEquivalentTo(const EnumValue('1')), isFalse);
    });

    test('compares the block-string flag', () {
      expect(
        const StringValue('s').isEquivalentTo(
          const StringValue('s', isBlock: true),
        ),
        isFalse,
      );
    });

    test('compares children in order and by count', () {
      final ab = ListValue(const [EnumValue('A'), EnumValue('B')]);
      expect(
        ab.isEquivalentTo(ListValue(const [EnumValue('A'), EnumValue('B')])),
        isTrue,
      );
      expect(
        ab.isEquivalentTo(ListValue(const [EnumValue('B'), EnumValue('A')])),
        isFalse,
      );
      expect(ab.isEquivalentTo(ListValue(const [EnumValue('A')])), isFalse);
    });
  });

  group('lists', () {
    test('a node copies its list into an unmodifiable one', () {
      final values = <Value>[one];
      final list = ListValue(values);
      values.clear();
      expect(list.values, [same(one)]);
      expect(() => list.values.add(one), throwsUnsupportedError);
    });

    test('a node built in code is at offset 0', () {
      expect((a.start, a.end), (0, 0));
    });
  });
}
