import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();
  const texts = [
    'Query',
    'Query.hero',
    'Query.hero(episode:)',
    '@deprecated',
    '@deprecated(reason:)',
  ];

  SchemaCoordinate coordinateOf(String text) =>
      switch (parser.parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  test('prints each form as it is written', () {
    for (final text in texts) {
      expect(const Printer().print(coordinateOf(text)), text);
    }
  });

  test('the minified form of a coordinate is the canonical one', () {
    for (final text in texts) {
      expect(const Printer(isMinified: true).print(coordinateOf(text)), text);
    }
  });

  test('prints a coordinate built in code', () {
    const coordinate = ArgumentCoordinate(Name('T'), Name('f'), Name('a'));
    expect(const Printer().print(coordinate), 'T.f(a:)');
  });
}
