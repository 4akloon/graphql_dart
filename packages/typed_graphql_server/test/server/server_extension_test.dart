import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hook_extension.dart';
import 'support/recording_extension.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  group('the order of the hooks', () {
    test('the first extension is the outermost in every phase', () async {
      final log = <String>[];
      final server = fixture.server(
        extensions: [
          RecordingExtension('a', log),
          RecordingExtension('b', log),
        ],
      );
      await server.handle(fixture.request('{ hello }'));
      expect(log, [
        'a:request',
        'b:request',
        'a:document',
        'b:document',
        '/b:document',
        '/a:document',
        'a:execute',
        'b:execute',
        '/b:execute',
        '/a:execute',
        '/b:request',
        '/a:request',
      ]);
    });

    test('a request without extensions is served', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }'),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  group('onRequest', () {
    test('may answer itself: nothing else runs', () async {
      final log = <String>[];
      var built = 0;
      final server = fixture.server(
        contextFactory: (_) {
          built++;
          return const Ctx('x');
        },
        extensions: [
          HookExtension(
            request: (request, next) async => SingleResponse(
              RequestErrorResult(errors: [GraphQLError('Closed')]),
              outcome: ServerOutcome.requestError,
            ),
          ),
          RecordingExtension('inner', log),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'Closed');
      expect(log, isEmpty);
      expect(built, 0);
    });

    test('sees the response coming back and may add headers', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            request: (request, next) async =>
                (await next(request)).withHeaders({'X-Served': 'yes'}),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(response.headers, {'x-served': 'yes'});
    });
  });

  group('onDocument', () {
    test('replacing the text runs the replacement', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) => next(request.withText('{ tag }')),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.json(response)['data'], {'tag': 'default'});
    });

    test('rejecting is a request error with its errors', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) async =>
                DocumentRejected([GraphQLError('Not allowed')]),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'Not allowed');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('a text over the maximum is GQL401', () async {
      final server = fixture.server(
        profile: const ServerProfile(
          introspection: .enabled,
          includesSuggestions: true,
          maskErrors: false,
          csrfPrevention: null,
          limits: ServerLimits(maxDocumentLength: 10),
        ),
        extensions: [
          HookExtension(
            document: (request, next) =>
                next(request.withText('{ hello } # long comment')),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL401');
    });

    test('an empty text is GQL400', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) => next(request.withText('')),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL400');
    });

    test('the same text gives the identical document twice', () async {
      final documents = <ValidDocument>[];
      final server = fixture.server(
        extensions: [
          HookExtension(
            execute: (request, next) {
              documents.add(request.document);
              return next(request);
            },
          ),
        ],
      );
      await server.handle(fixture.request('{ hello }'));
      await server.handle(fixture.request('{ hello }'));
      expect(documents[1], same(documents[0]));
    });

    test('the accepted hash is the SHA-256 the server computed', () async {
      final hashes = <String>[];
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) async {
              final result = await next(request);
              if (result case DocumentAccepted(:final hash)) hashes.add(hash);
              return result;
            },
          ),
        ],
      );
      await server.handle(fixture.request('{ hello }'));
      expect(hashes.single, hasLength(64));
    });
  });

  group('errors of a hook', () {
    test('a GraphQLException is a request error with its extensions', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) => throw GraphQLException(
              'Denied',
              extensions: JsonObject({'code': const JsonString('DENIED')}),
            ),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'DENIED');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('any other error is masked and seen by onError', () async {
      final seen = <Object>[];
      final server = fixture.server(
        profile: ServerProfile.production,
        onError: (error, stackTrace, reported) {
          seen.add(error);
          return null;
        },
        extensions: [
          HookExtension(
            request: (request, next) => throw StateError('secret'),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL330');
      expect(fixture.messageOf(response), 'Unexpected error.');
      expect(seen.single, isA<StateError>());
    });
  });
}
