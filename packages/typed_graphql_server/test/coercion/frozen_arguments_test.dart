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
}
