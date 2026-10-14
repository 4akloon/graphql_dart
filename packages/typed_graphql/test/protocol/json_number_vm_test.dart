@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test(
    'asInt is null for int.minValue, whose magnitude is not a safe integer',
    () {
      expect(JsonNumber(-9223372036854775807 - 1).asInt, isNull);
    },
  );
}
