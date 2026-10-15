import 'package:test/test.dart';
import 'package:typed_graphql/src/protocol/json_inspector.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const inspector = JsonInspector();

  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  test('quotes a string as JSON', () {
    expect(inspector.inspect(json(r'"a\"b\n"')), r'"a\"b\n"');
  });

  test('prints a list with spaces after the commas', () {
    expect(inspector.inspect(json('[1,2,3]')), '[1, 2, 3]');
  });

  test('prints an object as braces around its fields', () {
    expect(inspector.inspect(json('{"a":1,"b":["x"]}')), '{ a: 1, b: ["x"] }');
  });

  test('prints empty containers without spaces', () {
    expect(inspector.inspect(json('[]')), '[]');
    expect(inspector.inspect(json('{}')), '{}');
  });

  test('prints a whole float as an integer', () {
    expect(inspector.inspect(json('1.0')), '1');
    expect(inspector.inspect(json('1.5')), '1.5');
  });

  test('prints null and booleans', () {
    expect(inspector.inspect(json('[null,true,false]')), '[null, true, false]');
  });

  test('shows ten items of a list and counts the rest', () {
    expect(
      inspector.inspect(json('[1,2,3,4,5,6,7,8,9,10,11,12]')),
      '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ... 2 more items]',
    );
  });

  test('says one more item in the singular', () {
    expect(
      inspector.inspect(json('[1,2,3,4,5,6,7,8,9,10,11]')),
      '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ... 1 more item]',
    );
  });

  test('cuts containers nested more than two levels deep', () {
    expect(inspector.inspect(json('[[[1]]]')), '[[[Array]]]');
    expect(
      inspector.inspect(json('{"a":{"b":{"c":1}}}')),
      '{ a: { b: [Object] } }',
    );
  });

  test('is used by the messages of the built-in scalars', () {
    expect(
      const StringCodec().decode(json('[1,2,3]')),
      const DecodeFailure(
        'String cannot represent a non string value: [1, 2, 3]',
      ),
    );
    expect(
      const IntCodec().decode(json('{"a":1}')),
      const DecodeFailure('Int cannot represent non-integer value: { a: 1 }'),
    );
  });
}
