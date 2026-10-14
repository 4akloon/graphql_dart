@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  String typeExtensions(int count) => [
    for (var index = 0; index < count; index++)
      'extend type T { f$index: Int }',
  ].join('\n');

  test('sixteen thousand extensions of one type build in seconds', () {
    final text = 'type T { first: Int }\n${typeExtensions(16000)}';
    final watch = Stopwatch()..start();
    final schema = Built(text).schema;
    watch.stop();
    expect((schema.typeNamed('T') as ObjectType).fields, hasLength(16001));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
