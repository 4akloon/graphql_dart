@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test('rejects a maxDepth above maxSupportedDepth', () {
    expect(
      () => JsonReader(maxDepth: JsonReader.maxSupportedDepth + 1),
      throwsA(isA<AssertionError>()),
    );
  });

  test('rejects a negative maxDepth', () {
    expect(() => JsonReader(maxDepth: -1), throwsA(isA<AssertionError>()));
  });
}
