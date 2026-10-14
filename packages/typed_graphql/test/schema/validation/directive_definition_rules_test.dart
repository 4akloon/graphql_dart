import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('a directive without locations built in code is reported', () {
    final schema = Schema(
      types: [
        ObjectType(
          'Query',
          fields: [SchemaField('a', const NamedType(Name('Int')))],
        ),
      ],
      directives: [SchemaDirective('d')],
      queryTypeName: 'Query',
    );
    expect(Validated.schema(schema).errors, [
      'null GQL129 Directive @d must include 1 or more locations.',
    ]);
  });

  test('a directive applied to its own argument references itself', () {
    expect(
      errorsOf(
        '''
type Query { a: Int }
directive @invalidExample(arg: String @invalidExample) on ARGUMENT_DEFINITION''',
      ),
      [
        '2:1 GQL130 Directive "@invalidExample" must not reference itself '
            'directly or indirectly.',
      ],
    );
  });

  test('a directive reached through an argument type references itself', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(arg: In) on INPUT_FIELD_DEFINITION
input In { a: Int @d }'''),
      [
        '2:1 GQL130 Directive "@d" must not reference itself directly or '
            'indirectly.',
      ],
    );
  });

  test('a directive reached through another directive references itself', () {
    expect(
      Validated('''
type Query { a: Int }
directive @a(x: Int @b) on ARGUMENT_DEFINITION
directive @b(y: Int @a) on ARGUMENT_DEFINITION''').codes,
      ['GQL130', 'GQL130'],
    );
  });

  test('a cycle of types that does not reach the directive ends', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(arg: In) on FIELD
input In { a: In b: Int @deprecated }'''),
      isEmpty,
    );
  });

  test('a directive that references other directives only is valid', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(arg: Int @deprecated) on FIELD'''),
      isEmpty,
    );
  });
}
