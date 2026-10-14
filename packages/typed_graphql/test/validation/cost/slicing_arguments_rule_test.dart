import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('''
type Query {
  users(first: Int, last: Int): [User]
    @listSize(slicingArguments: ["first", "last"])
  pairs(first: Int, last: Int, tag: String): [User]
    @listSize(slicingArguments: ["first", "last"], requireOneSlicingArgument: false)
  one(first: Int): [User] @listSize(slicingArguments: ["first"])
  plain: [User]
}
type User { name: String }
''', builder: const SchemaBuilder(includesCostDirectives: true));

  List<String> errors(String text) =>
      checked.errors(text, [const SlicingArgumentsRule()]);

  test('a field given none of its slicing arguments is reported', () {
    expect(errors('{ users { name } }'), [
      '1:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 0.',
    ]);
  });

  test('a field given one slicing argument is valid', () {
    expect(errors('{ users(first: 3) { name } }'), isEmpty);
  });

  test('a field given two slicing arguments is reported', () {
    expect(errors('{ users(first: 3, last: 2) { name } }'), [
      '1:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 2.',
    ]);
  });

  test('a variable counts as given', () {
    expect(errors(r'query ($n: Int) { users(first: $n) { name } }'), isEmpty);
  });

  test('a null literal does not count', () {
    expect(errors('{ users(first: null) { name } }'), [
      '1:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 0.',
    ]);
  });

  test('a single slicing argument is named alone', () {
    expect(errors('{ one { name } }'), [
      '1:3 GQL237 Field "one" must be given exactly one of its slicing '
          'arguments "first", but it was given 0.',
    ]);
  });

  test('requireOneSlicingArgument false skips the field', () {
    expect(errors('{ pairs { name } }'), isEmpty);
  });

  test('a field without @listSize is skipped', () {
    expect(errors('{ plain { name } }'), isEmpty);
  });

  test('an alias reports the field name at the field', () {
    expect(errors('{\n  list: users { name }\n}'), [
      '2:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 0.',
    ]);
  });
}
