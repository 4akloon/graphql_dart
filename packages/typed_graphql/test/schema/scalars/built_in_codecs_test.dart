import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('IntCodec', () {
    const codec = IntCodec();

    test('decodes the bounds of a signed 32-bit integer', () {
      expect(
        codec.decode(JsonNumber(2147483647)),
        const DecodeSuccess<int>(2147483647),
      );
      expect(
        codec.decode(JsonNumber(-2147483648)),
        const DecodeSuccess<int>(-2147483648),
      );
    });

    test('decodes a whole float as an integer', () {
      expect(codec.decode(JsonNumber(3.0)), const DecodeSuccess<int>(3));
      expect(codec.decode(JsonNumber(1e0)), const DecodeSuccess<int>(1));
      expect(
        codec.decode(JsonNumber(2147483647.0)),
        const DecodeSuccess<int>(2147483647),
      );
    });

    test('decodes negative zero as zero', () {
      expect(codec.decode(JsonNumber(-0.0)), const DecodeSuccess<int>(0));
    });

    test('rejects a fraction just past the upper bound as a fraction', () {
      expect(codec.decode(JsonNumber(2147483647.5)), isA<DecodeFailure>());
    });

    test('rejects a number past the bounds', () {
      expect(
        codec.decode(JsonNumber(2147483648)),
        const DecodeFailure(
          'Int cannot represent non 32-bit signed integer value: 2147483648',
        ),
      );
      expect(codec.decode(JsonNumber(-2147483649)), isA<DecodeFailure>());
      expect(codec.decode(JsonNumber(1e100)), isA<DecodeFailure>());
    });

    test('rejects a fraction', () {
      // The message prints the number, which differs per platform for a
      // fraction, so only its start is asserted.
      final failure = codec.decode(JsonNumber(1.5)) as DecodeFailure;
      expect(failure.message, startsWith('Int cannot represent non-integer'));
    });

    test('rejects a string', () {
      expect(
        codec.decode(const JsonString('1')),
        const DecodeFailure('Int cannot represent non-integer value: "1"'),
      );
    });

    test('rejects a boolean and null', () {
      expect(codec.decode(const JsonBool(true)), isA<DecodeFailure>());
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('encodes an integer as a number', () {
      expect(codec.encode(42), JsonNumber(42));
    });

    test('encodes the bounds', () {
      expect(codec.encode(IntCodec.min), JsonNumber(IntCodec.min));
      expect(codec.encode(IntCodec.max), JsonNumber(IntCodec.max));
    });

    test('refuses to encode an integer past the bounds', () {
      expect(() => codec.encode(IntCodec.max + 1), throwsArgumentError);
      expect(() => codec.encode(IntCodec.min - 1), throwsArgumentError);
    });
  });

  group('FloatCodec', () {
    const codec = FloatCodec();

    test('decodes any finite number as a double', () {
      expect(codec.decode(JsonNumber(1.5)), const DecodeSuccess<double>(1.5));
      expect(codec.decode(JsonNumber(2)), const DecodeSuccess<double>(2));
    });

    test('decodes negative zero as zero', () {
      expect(codec.decode(JsonNumber(-0.0)), const DecodeSuccess<double>(0));
    });

    test('rejects a string and a boolean', () {
      expect(
        codec.decode(const JsonString('1.5')),
        const DecodeFailure('Float cannot represent non numeric value: "1.5"'),
      );
      expect(codec.decode(const JsonBool(false)), isA<DecodeFailure>());
    });

    test('rejects null', () {
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('encodes a double as a number', () {
      expect(codec.encode(0.25), JsonNumber(0.25));
    });

    test('refuses to encode NaN and the infinities', () {
      expect(() => codec.encode(double.nan), throwsArgumentError);
      expect(() => codec.encode(double.infinity), throwsArgumentError);
    });
  });

  group('StringCodec', () {
    const codec = StringCodec();

    test('decodes a string and encodes it back', () {
      expect(
        codec.decode(const JsonString('abc')),
        const DecodeSuccess<String>('abc'),
      );
      expect(codec.encode('abc'), const JsonString('abc'));
    });

    test('rejects a number', () {
      expect(
        codec.decode(JsonNumber(1)),
        const DecodeFailure('String cannot represent a non string value: 1'),
      );
    });

    test('rejects null', () {
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });
  });

  group('BooleanCodec', () {
    const codec = BooleanCodec();

    test('decodes a boolean and encodes it back', () {
      expect(
        codec.decode(const JsonBool(true)),
        const DecodeSuccess<bool>(true),
      );
      expect(codec.encode(false), const JsonBool(false));
    });

    test('rejects a number', () {
      expect(
        codec.decode(JsonNumber(0)),
        const DecodeFailure('Boolean cannot represent a non boolean value: 0'),
      );
    });

    test('rejects null', () {
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });
  });

  group('IdCodec', () {
    const codec = IdCodec();

    test('decodes a string and an integer as a string', () {
      expect(
        codec.decode(const JsonString('a1')),
        const DecodeSuccess<String>('a1'),
      );
      expect(codec.decode(JsonNumber(12)), const DecodeSuccess<String>('12'));
    });

    test('rejects a fraction', () {
      // The message prints the number, which differs per platform for a
      // fraction, so only its start is asserted.
      final failure = codec.decode(JsonNumber(1.5)) as DecodeFailure;
      expect(failure.message, startsWith('ID cannot represent value'));
    });

    test('rejects a boolean, naming it', () {
      expect(
        codec.decode(const JsonBool(true)),
        const DecodeFailure('ID cannot represent value: true'),
      );
    });

    test('rejects null', () {
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('rejects an integer past 2^53 - 1, which the web cannot hold', () {
      expect(
        codec.decode(JsonNumber(9007199254740991)),
        const DecodeSuccess<String>('9007199254740991'),
      );
      expect(codec.decode(JsonNumber(9007199254740992)), isA<DecodeFailure>());
      expect(
        codec.decode(JsonNumber(-9007199254740992)),
        isA<DecodeFailure>(),
      );
    });

    test('encodes a string', () {
      expect(codec.encode('12'), const JsonString('12'));
    });
  });
}
