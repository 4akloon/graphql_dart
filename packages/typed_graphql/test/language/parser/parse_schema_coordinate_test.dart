import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  SchemaCoordinate coordinateOf(String text) =>
      switch (parser.parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  /// Each diagnostic of parsing [text] as `line:column id message`; the
  /// test expects a failure.
  List<String> errorsOf(String text) =>
      switch (parser.parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess() => fail('expected syntax errors'),
        ParseElementFailure(:final diagnostics) => [
          for (final diagnostic in diagnostics)
            '${diagnostic.span?.location} ${diagnostic.code.id} '
                '${diagnostic.message}',
        ],
      };

  test('spans a member coordinate from the type to the member', () {
    final node = coordinateOf('T.f');
    expect([node.start, node.end], [0, 3]);
  });

  test('parses each of the five forms into its node', () {
    expect(
      coordinateOf('Query'),
      isA<TypeCoordinate>().having((node) => node.name.value, 'name', 'Query'),
    );
    expect(
      coordinateOf('Query.hero'),
      isA<MemberCoordinate>().having(
        (node) => node.memberName.value,
        'memberName',
        'hero',
      ),
    );
    expect(
      coordinateOf('Query.hero(episode:)'),
      isA<ArgumentCoordinate>()
          .having((node) => node.fieldName.value, 'fieldName', 'hero')
          .having((node) => node.argumentName.value, 'argument', 'episode'),
    );
    expect(
      coordinateOf('@deprecated'),
      isA<DirectiveCoordinate>().having(
        (node) => node.name.value,
        'name',
        'deprecated',
      ),
    );
    expect(
      coordinateOf('@deprecated(reason:)'),
      isA<DirectiveArgumentCoordinate>().having(
        (node) => node.argumentName.value,
        'argumentName',
        'reason',
      ),
    );
  });

  test('a coordinate spans the whole text, its names their own', () {
    final coordinate = coordinateOf('@a(b:)');
    expect((coordinate.start, coordinate.end), (0, 6));
    expect((coordinate.name.start, coordinate.name.end), (1, 2));
  });

  test('a third name is an error at the second dot', () {
    expect(errorsOf('MyType.field.deep'), [
      '1:13 GQL007 Expected <EOF>, found ".".',
    ]);
  });

  test('a directive has no member', () {
    expect(errorsOf('@myDirective.field'), [
      '1:13 GQL007 Expected <EOF>, found ".".',
    ]);
  });

  test('a type has no argument', () {
    expect(errorsOf('MyType(arg:)'), [
      '1:7 GQL007 Expected <EOF>, found "(".',
    ]);
  });

  test('an argument coordinate holds no value', () {
    expect(errorsOf('MyType.field(arg: value)'), [
      '1:18 GQL001 Invalid character: " ".',
    ]);
    expect(errorsOf('MyType.field(arg:value)'), [
      '1:18 GQL007 Expected ")", found Name "value".',
    ]);
  });

  test('ignored tokens around a coordinate are errors', () {
    expect(errorsOf(' Query'), ['1:1 GQL001 Invalid character: " ".']);
    expect(errorsOf('Query\n'), ['1:6 GQL001 Invalid character: U+000A.']);
  });

  test('empty text is a missing name', () {
    expect(errorsOf(''), ['1:1 GQL007 Expected Name, found <EOF>.']);
  });

  test('document syntax is not a coordinate', () {
    expect(errorsOf('{ a }'), ['1:1 GQL001 Invalid character: "{".']);
  });
}
