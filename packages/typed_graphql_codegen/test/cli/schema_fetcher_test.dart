@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/cli/schema_fetcher.dart';

import '../support/cli_project.dart';

void main() {
  Schema schemaOf(String sdl) {
    final source = Source(sdl, name: 'schema.graphql');
    final document = (const Parser().parse(source) as ParseSuccess).document;
    final built = const SchemaBuilder().fromSdl(document, source: source);
    return (built as BuildSuccess).schema;
  }

  // The golden configuration's other settings, so the output is the same.
  String keptSettings(CliProject project) {
    final lines = project.file('typed_graphql.yaml').readAsLinesSync();
    return '${lines.skip(1).join('\n')}\n';
  }

  late CliProject project;
  late HttpServer server;
  late List<({HttpHeaders headers, String body})> requests;
  void Function(HttpResponse) respond = (response) {};

  setUp(() async {
    project = CliProject();
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      requests.add((headers: request.headers, body: body));
      respond(request.response);
    });
    final sdl = project.file('schema.graphql').readAsStringSync();
    final schema = schemaOf(sdl);
    respond = (response) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'data': schema.toIntrospection().toJson()}));
      response.close();
    };
    project
        .file('typed_graphql.yaml')
        .writeAsStringSync(
          'schema: http://127.0.0.1:${server.port}/graphql\n'
          'headers:\n'
          '  Authorization: Bearer \${TOKEN}\n'
          '${keptSettings(project)}',
        );
  });
  tearDown(() async {
    await server.close(force: true);
    project.delete();
  });

  const environment = {'TOKEN': 'secret-token-value'};

  test('generate from a URL writes the files of the SDL project', () async {
    expect(await project.run(['generate'], environment: environment), 0);
    expect(project.out.toString(), 'Wrote 5 files.\n');
    expect(project.file('lib/user.graphql.dart').existsSync(), isTrue);
  });

  test('the request carries the expanded header and the query', () async {
    await project.run(['generate'], environment: environment);
    expect(
      requests.single.headers.value('authorization'),
      startsWith('Bearer'),
    );
    expect(
      requests.single.headers.value('authorization'),
      'Bearer secret-token-value',
    );
    expect(requests.single.headers.contentType?.mimeType, 'application/json');
    expect(
      requests.single.body,
      GraphQLRequest(query: IntrospectionQuery.full.text).toJson().toString(),
    );
  });

  test('a 401 is GQL510 with the status', () async {
    respond = (response) {
      response.statusCode = 401;
      response.write('nope');
      response.close();
    };
    expect(await project.run(['generate'], environment: environment), 1);
    expect(
      project.err.toString(),
      'error GQL510: Cannot fetch the schema from '
      "'http://127.0.0.1:${server.port}/graphql': HTTP 401 Unauthorized: "
      'nope.\n',
    );
  });

  test('a closed port is GQL510', () async {
    final port = server.port;
    await server.close(force: true);
    expect(await project.run(['generate'], environment: environment), 1);
    expect(
      project.err.toString(),
      startsWith(
        'error GQL510: Cannot fetch the schema from '
        "'http://127.0.0.1:$port/graphql': ",
      ),
    );
  });

  test('a slow server past the timeout is GQL510', () async {
    final hold = Completer<void>();
    respond = (response) {
      unawaited(hold.future.then((_) => response.close()));
    };
    final code = await project.run(
      ['generate'],
      environment: environment,
      fetcher: const SchemaFetcher(timeout: Duration(milliseconds: 200)),
    );
    hold.complete();
    expect(code, 1);
    expect(
      project.err.toString(),
      'error GQL510: Cannot fetch the schema from '
      "'http://127.0.0.1:${server.port}/graphql': "
      'the request timed out after 200ms.\n',
    );
  });

  test('errors without data are GQL502', () async {
    respond = (response) {
      response.write(
        jsonEncode({
          'errors': [
            {'message': 'Introspection is disabled'},
          ],
        }),
      );
      response.close();
    };
    expect(await project.run(['generate'], environment: environment), 1);
    expect(project.err.toString(), contains('error GQL502: The server '));
    expect(project.err.toString(), contains('Introspection is disabled'));
  });

  test('a missing environment variable is GQL501 and sends nothing', () async {
    expect(await project.run(['generate']), 1);
    expect(
      project.err.toString(),
      "error GQL501: The header 'Authorization' uses the environment "
      "variable 'TOKEN', which is not set.\n",
    );
    expect(requests, isEmpty);
  });

  test('a header value never appears in the output', () async {
    respond = (response) {
      response.statusCode = 500;
      response.close();
    };
    await project.run(['generate'], environment: environment);
    await project.run(['check'], environment: environment);
    expect(
      project.out.toString() + project.err.toString(),
      isNot(contains('secret-token-value')),
    );
  });
}
