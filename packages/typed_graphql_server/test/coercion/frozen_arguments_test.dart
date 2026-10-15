import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  late ExecutableSchema<Object?> built;
  late ValidDocument document;
  var seen = <Object?>[];

  setUp(() {
    seen = [];
    final b = ExecutableSchemaBuilder<Object?>();
    final name = Arg('name', b.string);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('greet', b.string.nullable, args: [name]).resolve((
          parent,
          args,
          context,
          info,
        ) {
          seen.add(args.coerced['name']);
          args.coerced['name'] = 'changed';
          return 'ok';
        }),
      ],
    );
    built = b.build(query: query);
    final parsed = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source('{ greet(name: "Ada") }')).requireDocument();
    document = ValidDocument.assumeValid(built.schema, parsed);
  });

  test('a resolver cannot write to the coerced arguments', () async {
    final payload = await built.execute(document, context: null);
    final errors = payload.toJson().toJson()['errors']! as List<Object?>;
    expect(errors, hasLength(1));
  });

  test('a later execution of the cached operation sees the original', () async {
    await built.execute(document, context: null);
    await built.execute(document, context: null);
    expect(seen, ['Ada', 'Ada']);
  });

  group('nested values', () {
    late Object? listArgument;
    late Map<String, Object?> decoderInput;
    late Object? decoded;

    Future<void> run(String query) async {
      final b = ExecutableSchemaBuilder<Object?>();
      final tags = Arg('tags', b.inputList(b.string).nullable);
      final input = b.inputObject<String>(
        'Filter',
        fields: () => [tags],
        decode: (values) {
          decoderInput = values.coerced;
          return 'filter';
        },
      );
      final list = Arg('list', b.inputList(b.string).nullable);
      final filter = Arg('filter', input.nullable);
      final root = b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('f', b.string.nullable, args: [list, filter]).resolve((
            parent,
            args,
            context,
            info,
          ) {
            listArgument = args.coerced['list'];
            decoded = args.coerced['filter'];
            return 'ok';
          }),
        ],
      );
      final schema = b.build(query: root);
      final parsed = const Parser(
        options: ParserOptions(maxTokens: null, maxDepth: null),
      ).parse(Source(query)).requireDocument();
      await schema.execute(
        ValidDocument.assumeValid(schema.schema, parsed),
        context: null,
      );
    }

    test('a list argument cannot be modified', () async {
      await run('{ f(list: ["a"]) }');
      expect(
        () => (listArgument! as List<Object?>).add('b'),
        throwsUnsupportedError,
      );
    });

    test(
      'the map handed to an input object decoder cannot be modified',
      () async {
        await run('{ f(filter: {tags: ["a"]}) }');
        expect(decoded, 'filter');
        expect(() => decoderInput['tags'] = null, throwsUnsupportedError);
      },
    );

    test('a list inside an input object cannot be modified', () async {
      await run('{ f(filter: {tags: ["a"]}) }');
      expect(
        () => (decoderInput['tags']! as List<Object?>).add('b'),
        throwsUnsupportedError,
      );
    });
  });
}
