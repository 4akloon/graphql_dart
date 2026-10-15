import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test('a present value equals a present equal value', () {
    expect(
      const Optional<String>.present('a'),
      equals(const Optional<String>.present('a')),
    );
  });

  test('a present value equals one with another static type', () {
    expect(
      const Optional<int?>.present(1),
      equals(const Optional<Object?>.present(1)),
    );
  });

  test('a present value differs from one with another value', () {
    expect(
      const Optional<int>.present(1),
      isNot(equals(const Optional<int>.present(2))),
    );
  });

  test('a present null differs from absent', () {
    expect(
      const Optional<String?>.present(null),
      isNot(equals(const Optional<String?>.absent())),
    );
  });

  test('absent values are equal across types', () {
    expect(
      const Optional<int>.absent(),
      equals(const Optional<String?>.absent()),
    );
  });

  test('hash codes agree with equality', () {
    expect(
      const Optional<int?>.present(1).hashCode,
      const Optional<Object?>.present(1).hashCode,
    );
    expect(
      const Optional<int>.absent().hashCode,
      const Optional<String>.absent().hashCode,
    );
  });

  test('toString names the state', () {
    expect(
      [
        const Optional<String?>.present('a').toString(),
        const Optional<String?>.present(null).toString(),
        const Optional<String?>.absent().toString(),
      ],
      ['Optional.present(a)', 'Optional.present(null)', 'Optional.absent()'],
    );
  });

  test('a switch with two cases is exhaustive', () {
    String describe(Optional<int> value) => switch (value) {
      Present(:final value) => 'present $value',
      Absent() => 'absent',
    };
    expect(describe(const Optional.present(3)), 'present 3');
    expect(describe(const Optional.absent()), 'absent');
  });
}
