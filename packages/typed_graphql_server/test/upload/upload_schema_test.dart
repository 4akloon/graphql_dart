import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/upload/memory_upload.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final uploads = Uploads();
  final b = ExecutableSchemaBuilder<Object?>();
  final upload = b.scalar<Upload>(Uploads.scalarName, uploads.codec);
  final file = Arg('file', upload);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('ok', b.string).pure((_) => 'ok')],
  );
  final mutation = b.object<Object?>(
    'Mutation',
    fields: (t) => [
      t.field('upload', b.string.nullable, args: [file]).resolve((
        parent,
        args,
        context,
        info,
      ) async {
        final received = args.get(file);
        final bytes = await received.openRead().expand((c) => c).toList();
        return '${received.filename}:${utf8.decode(bytes)}';
      }),
    ],
  );
  final schema = b.build(query: query, mutation: mutation);

  Future<Map<String, Object?>> run(String text, [JsonObject? variables]) async {
    final document = const Parser().parse(Source(text)).requireDocument();
    final payload = await schema.execute(
      ValidDocument.assumeValid(schema.schema, document),
      context: null,
      variables: variables,
    );
    return payload.toJson().toJson();
  }

  String register(String name, String content) => uploads.registry.register(
    MemoryUpload(name, 'text/plain', Uint8List.fromList(utf8.encode(content))),
  );

  group('the Upload scalar in a schema', () {
    test('is declared under its name', () {
      expect(upload.name, 'Upload');
    });

    test(
      'a variable holding a registered token reaches the resolver',
      () async {
        final token = register('a.txt', 'hello');
        final json = await run(
          r'mutation ($f: Upload!) { upload(file: $f) }',
          JsonObject({'f': JsonString(token)}),
        );
        expect(json['data'], {'upload': 'a.txt:hello'});
      },
    );

    test(
      'a literal that is not a registered token is a coercion error',
      () async {
        final json = await run('mutation { upload(file: "upload:unknown") }');
        expect(json['errors'], isNotEmpty);
        expect(json['data'], {'upload': null});
      },
    );
  });
}
