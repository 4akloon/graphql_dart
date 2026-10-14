import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  String typeExtensions(int count) => [
    for (var index = 0; index < count; index++)
      'extend type T { f$index: Int }',
  ].join('\n');

  String directiveExtensions(int count) => [
    for (var index = 0; index < count; index++) 'extend directive @d @a$index',
  ].join('\n');

  test('many extensions of one type keep every member in order', () {
    final schema = Built(
      'type T { first: Int }\n${typeExtensions(3000)}',
    ).schema;
    final type = schema.typeNamed('T') as ObjectType;
    expect(
      [for (final field in type.fields) field.name],
      [
        'first',
        for (var index = 0; index < 3000; index++) 'f$index',
      ],
    );
    expect(schema.types.where((type) => type.name == 'T'), hasLength(1));
  });

  test('many extensions of one directive keep every applied directive', () {
    final schema = Built(
      'directive @d on FIELD\n${directiveExtensions(3000)}',
    ).schema;
    expect(schema.directiveNamed('d')?.appliedDirectives, hasLength(3000));
  });

  test('sixteen thousand extensions of one type build in seconds', () {
    final text = 'type T { first: Int }\n${typeExtensions(16000)}';
    final watch = Stopwatch()..start();
    final schema = Built(text).schema;
    watch.stop();
    expect((schema.typeNamed('T') as ObjectType).fields, hasLength(16001));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
