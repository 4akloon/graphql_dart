import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hook_extension.dart';
import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();

  /// Servers that fail in one place each, with the errors the hook saw.
  final failures = <String, ServerExtension<Ctx>?>{
    'a throwing extension in onRequest': HookExtension(
      request: (request, next) => throw StateError(hostileSecret),
    ),
    'a throwing extension in onDocument': HookExtension(
      document: (request, next) => throw StateError(hostileSecret),
    ),
    'a throwing extension in onExecute': HookExtension(
      execute: (request, next) => throw StateError(hostileSecret),
    ),
    'a throwing context factory': null,
  };

  GraphQLServer<Ctx> serverFor(
    ServerProfile profile,
    ServerExtension<Ctx>? extension,
    List<Object> seen,
  ) => hostile.server(
    profile: profile,
    contextFactory: extension == null
        ? (_) => throw StateError(hostileSecret)
        : null,
    extensions: [?extension],
    onError: (error, stackTrace, reported) {
      seen.add(error);
      return null;
    },
  );

  group('in production', () {
    for (final MapEntry(key: label, value: extension) in failures.entries) {
      test('$label is the masked message and nothing else', () async {
        final seen = <Object>[];
        final server = serverFor(ServerProfile.production, extension, seen);
        final response = await server.handle(fixture.request('{ hello }'));
        expect(fixture.codeOf(response), 'GQL330');
        expect(fixture.messageOf(response), 'Unexpected error.');
        expect(jsonEncode(fixture.json(response)), isNot(contains('secret')));
        expect(
          jsonEncode(fixture.json(response)),
          isNot(contains('Bad state')),
        );
        expect(jsonEncode(fixture.json(response)), isNot(contains('.dart')));
        expect(
          (response as SingleResponse).outcome,
          ServerOutcome.internalError,
        );
      });

      test('$label reaches onError raw', () async {
        final seen = <Object>[];
        final server = serverFor(ServerProfile.production, extension, seen);
        await server.handle(fixture.request('{ hello }'));
        expect(seen.single, isA<StateError>());
        expect(seen.single.toString(), contains(hostileSecret));
      });
    }

    test(
      'a throwing resolver is the masked message and nothing else',
      () async {
        final seen = <Object>[];
        final server = hostile.server(
          onError: (error, stackTrace, reported) {
            seen.add(error);
            return null;
          },
        );
        final response = await server.handle(fixture.request('{ boom }'));
        final body = jsonEncode(fixture.json(response));
        expect(fixture.messageOf(response), 'Unexpected error.');
        expect(body, isNot(contains('secret')));
        expect(body, isNot(contains('Bad state')));
        expect(seen.single, isA<StateError>());
      },
    );
  });

  group('in development', () {
    for (final MapEntry(key: label, value: extension) in failures.entries) {
      test('$label shows the message', () async {
        final server = serverFor(ServerProfile.development, extension, []);
        final response = await server.handle(fixture.request('{ hello }'));
        expect(fixture.messageOf(response), contains(hostileSecret));
      });
    }

    test('a throwing resolver shows the message', () async {
      final response = await hostile
          .server(profile: ServerProfile.development)
          .handle(fixture.request('{ boom }'));
      expect(fixture.messageOf(response), contains(hostileSecret));
    });
  });
}
