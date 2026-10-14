import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  Value valueOf(String text) => switch (parser.parseValue(Source(text))) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };

  List<String> errorsOf(ParseElementResult<Node> result) => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];

  group('parseValue', () {
    test('parses every scalar kind with its offsets', () {
      final value = valueOf(r'[1, -2.5e3, "s", """b""", true, null, RED, $v]');
      final items = (value as ListValue).values;
      expect(items.map((item) => item.runtimeType), [
        IntValue,
        FloatValue,
        StringValue,
        StringValue,
        BooleanValue,
        NullValue,
        EnumValue,
        Variable,
      ]);
      expect((items[1] as FloatValue).value, '-2.5e3');
      expect((items[3] as StringValue).isBlock, isTrue);
      expect([items[1].start, items[1].end], [4, 10]);
      expect([items[7].start, items[7].end], [43, 45]);
    });

    test('parses objects with nested lists', () {
      final expected = ObjectValue([
        ObjectField(
          const Name('a'),
          ListValue([
            const IntValue('1'),
            ObjectValue(const [ObjectField(Name('b'), IntValue('2'))]),
          ]),
        ),
        const ObjectField(Name('c'), StringValue('x')),
      ]);
      final value = valueOf('{a: [1, {b: 2}], c: "x"}');
      expect(value.isEquivalentTo(expected), isTrue);
      expect([value.start, value.end], [0, 24]);
    });

    test('rejects a variable in a constant value at the dollar sign', () {
      final result = parser.parseValue(Source(r'[1, $var]'), isConst: true);
      expect(errorsOf(result), [
        r'1:5 GQL009 Unexpected variable "$var" in constant value.',
      ]);
      final bare = parser.parseValue(Source(r'$'), isConst: true);
      expect(errorsOf(bare), [r'1:1 GQL008 Unexpected "$".']);
    });

    test('reports an unexpected and a missing token', () {
      expect(errorsOf(parser.parseValue(Source(')'))), [
        '1:1 GQL008 Unexpected ")".',
      ]);
      expect(errorsOf(parser.parseValue(Source('{a 1}'))), [
        '1:4 GQL007 Expected ":", found Int "1".',
      ]);
      expect(errorsOf(parser.parseValue(Source('1 x'))), [
        '1:3 GQL007 Expected <EOF>, found Name "x".',
      ]);
    });

    test('adds nothing to a lexer error', () {
      expect(errorsOf(parser.parseValue(Source('[1, ~]'))), [
        '1:5 GQL001 Unexpected character: "~".',
      ]);
    });
  });

  group('parseTypeRef', () {
    test('wraps list and non-null types', () {
      final result = parser.parseTypeRef(Source('[String!]!'));
      final type = (result as ParseElementSuccess<TypeRef>).value;
      const expected = NonNullType(
        ListType(NonNullType(NamedType(Name('String')))),
      );
      expect(type.isEquivalentTo(expected), isTrue);
      expect([type.start, type.end], [0, 10]);
    });

    test('reports a missing bracket', () {
      expect(errorsOf(parser.parseTypeRef(Source('[[A]'))), [
        '1:5 GQL007 Expected "]", found <EOF>.',
      ]);
    });
  });

  group('limits', () {
    const shallow = Parser(options: ParserOptions(maxDepth: 3));

    test('accepts nesting up to maxDepth', () {
      expect(
        shallow.parseValue(Source('[[{a: 1}]]')),
        isA<ParseElementSuccess<Value>>(),
      );
      expect(
        shallow.parseTypeRef(Source('[[[A]]]')),
        isA<ParseElementSuccess<TypeRef>>(),
      );
    });

    test('reports one error at the level past maxDepth', () {
      expect(errorsOf(shallow.parseValue(Source('[[[[1]]]]'))), [
        '1:4 GQL010 Document nests deeper than 3 levels.',
      ]);
      expect(errorsOf(shallow.parseTypeRef(Source('[[[[A]]]]'))), [
        '1:4 GQL010 Document nests deeper than 3 levels.',
      ]);
    });

    test('stops at maxTokens with one error', () {
      const short = Parser(options: ParserOptions(maxTokens: 2));
      expect(errorsOf(short.parseValue(Source('[1, 2]'))), [
        '1:5 GQL006 Document contains more than 2 tokens. Parsing aborted.',
      ]);
    });
  });
}
