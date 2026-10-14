import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('PathSegment', () {
    test('compares keys by name and indexes by index', () {
      expect(const PathKey('a'), const PathKey('a'));
      expect(const PathIndex(0), const PathIndex(0));
      expect(const PathKey('0'), isNot(const PathIndex(0)));
      expect(const PathKey('a').hashCode, const PathKey('a').hashCode);
    });

    test('prints the bare key or index', () {
      expect(const PathKey('hero').toString(), 'hero');
      expect(const PathIndex(2).toString(), '2');
    });
  });

  group('DecodeResult', () {
    test('a switch over it is exhaustive', () {
      String describe(DecodeResult<int> result) => switch (result) {
        DecodeSuccess(:final value) => 'value $value',
        DecodeFailure(:final message) => 'failure $message',
      };
      expect(describe(const DecodeSuccess(1)), 'value 1');
      expect(describe(const DecodeFailure('bad')), 'failure bad');
    });

    test('inside leaves a success as it is', () {
      const result = DecodeSuccess(1);
      expect(result.inside(const PathKey('a')), same(result));
    });

    test('inside puts the step in front of the failure path', () {
      final failure = const DecodeFailure('expected a string')
          .inside(const PathKey('message'))
          .inside(const PathIndex(0))
          .inside(const PathKey('errors'));
      expect(
        failure,
        const DecodeFailure(
          'expected a string',
          path: [PathKey('errors'), PathIndex(0), PathKey('message')],
        ),
      );
    });

    test('a failure prints its path as JSONPath', () {
      const failure = DecodeFailure(
        'expected a string',
        path: [PathKey('errors'), PathIndex(0), PathKey('message')],
      );
      expect(failure.toString(), r'$.errors[0].message: expected a string');
      expect(const DecodeFailure('bad').toString(), r'$: bad');
    });

    test('failures compare by message and path, not by printed form', () {
      const dotted = DecodeFailure('bad', path: [PathKey('a.b')]);
      const nested = DecodeFailure('bad', path: [PathKey('a'), PathKey('b')]);
      expect(dotted.toString(), nested.toString());
      expect(dotted, isNot(nested));
      expect(
        const DecodeFailure('bad', path: [PathIndex(1)]).hashCode,
        const DecodeFailure('bad', path: [PathIndex(1)]).hashCode,
      );
    });

    test('successes compare by value', () {
      expect(const DecodeSuccess('a'), const DecodeSuccess('a'));
      expect(const DecodeSuccess('a'), isNot(const DecodeSuccess('b')));
    });
  });
}
