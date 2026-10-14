import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// A custom scalar for the tests: a date as `yyyy-mm-dd` text.
final class _DateCodec implements ScalarCodec<DateTime> {
  const _DateCodec();

  @override
  DecodeResult<DateTime> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => switch (DateTime.tryParse(value)) {
      final date? => DecodeSuccess(date),
      null => DecodeFailure('not a date: $value'),
    },
    _ => DecodeFailure('not a date: $json'),
  };

  @override
  JsonValue encode(DateTime value) =>
      JsonString(value.toIso8601String().substring(0, 10));
}

void main() {
  test('holds the five built-in codecs by name', () {
    final codecs = ScalarCodecs();
    expect(codecs.codecFor('Int'), isA<IntCodec>());
    expect(codecs.codecFor('Float'), isA<FloatCodec>());
    expect(codecs.codecFor('String'), isA<StringCodec>());
    expect(codecs.codecFor('Boolean'), isA<BooleanCodec>());
    expect(codecs.codecFor('ID'), isA<IdCodec>());
    expect(codecs.codecFor('Date'), isNull);
  });

  test('adds a codec for a custom scalar in a new registry', () {
    final codecs = ScalarCodecs();
    final withDate = codecs.withCodec('Date', const _DateCodec());
    expect(withDate.codecFor('Date'), isA<_DateCodec>());
    expect(withDate.codecFor('Int'), isA<IntCodec>());
    expect(codecs.codecFor('Date'), isNull);
  });

  test('decodes through a registered codec', () {
    final codec = ScalarCodecs()
        .withCodec('Date', const _DateCodec())
        .codecFor('Date');
    expect(
      codec?.decode(const JsonString('2026-10-14')),
      DecodeSuccess<DateTime>(DateTime(2026, 10, 14)),
    );
  });

  test('refuses to replace a built-in codec', () {
    expect(
      () => ScalarCodecs().withCodec('Int', const StringCodec()),
      throwsArgumentError,
    );
  });
}
