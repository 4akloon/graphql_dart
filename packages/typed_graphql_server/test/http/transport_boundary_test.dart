import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/response_media_type.dart';
import 'package:typed_graphql_server/src/http/result_writer.dart';
import 'package:typed_graphql_server/src/http/transport_errors.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();

  setUp(() => http.contexts = 0);

  group('the outermost boundary', () {
    HttpRequestData brokenRequest() {
      final stream = StreamController<List<int>>().stream..listen(null);
      return http.postStream(
        stream,
        headers: const {'content-type': 'application/json'},
      );
    }

    test('offers a bug to the error hook with its stack trace', () async {
      Object? seenError;
      StackTrace? seenStack;
      final response = await http
          .handler(
            options: HttpOptions(
              onError: (error, stackTrace, reported) {
                seenError = error;
                seenStack = stackTrace;
                return null;
              },
            ),
          )
          .handle(brokenRequest());
      expect(response.status, 500);
      expect(await http.code(response), 'GQL330');
      expect(seenError, isA<StateError>());
      expect(seenStack.toString(), isNotEmpty);
    });

    test('lets the hook replace the error', () async {
      final response = await http
          .handler(
            options: HttpOptions(
              onError: (error, stackTrace, reported) =>
                  GraphQLError('Mine.', extensions: reported.extensions),
            ),
          )
          .handle(brokenRequest());
      expect(await http.message(response), 'Mine.');
    });

    test('survives a hook that throws', () async {
      final response = await http
          .handler(
            options: HttpOptions(
              onError: (error, stackTrace, reported) => throw StateError('x'),
            ),
          )
          .handle(brokenRequest());
      expect((response.status, await http.code(response)), (500, 'GQL330'));
    });

    test('does not tell the hook about a refusal', () async {
      var calls = 0;
      await http
          .handler(
            options: HttpOptions(
              onError: (error, stackTrace, reported) {
                calls++;
                return null;
              },
            ),
          )
          .handle(
            HttpRequestData(method: 'PUT', uri: Uri.parse('/graphql')),
          );
      expect(calls, 0);
    });
  });

  group('caching', () {
    test('varies a result on Accept', () async {
      final response = await http.handler().handle(
        http.get({'query': '{ hello }'}),
      );
      expect(response.headers['vary'], 'accept');
    });

    test('varies a refusal on Accept and forbids storing it', () async {
      final response = await http.handler().handle(
        HttpRequestData(method: 'PUT', uri: Uri.parse('/graphql')),
      );
      expect(response.headers['vary'], 'accept');
      expect(response.headers['cache-control'], 'no-store');
    });

    test('forbids storing an unexpected error', () {
      final response = const TransportErrors(false).unexpected(StateError('x'));
      expect(response.headers['cache-control'], 'no-store');
    });

    test('adds accept to a vary header an extension set', () {
      final response =
          ResultWriter(
            usesPartialSuccessStatus: true,
          ).single(
            SingleResponse(
              ExecutionResult(JsonObject({'a': JsonNumber(1)})),
              headers: const {'vary': 'Origin'},
            ),
            ResponseMediaType.json,
          );
      expect(response.headers['vary'], 'Origin, accept');
    });

    test('does not repeat accept in a vary header', () {
      final response =
          ResultWriter(
            usesPartialSuccessStatus: true,
          ).single(
            SingleResponse(
              ExecutionResult(JsonObject({'a': JsonNumber(1)})),
              headers: const {'vary': 'Accept'},
            ),
            ResponseMediaType.json,
          );
      expect(response.headers['vary'], 'Accept');
    });

    test('varies a batch on Accept', () async {
      final response = await http
          .handler(options: const HttpOptions(batching: BatchPolicy()))
          .handle(
            http.post([
              {'query': '{ hello }'},
            ]),
          );
      expect(response.headers['vary'], 'accept');
    });
  });

  group('the message of an unexpected error', () {
    test('is cut at 500 characters', () {
      final response = const TransportErrors(false).unexpected(
        StateError('x' * 5000),
      );
      final message = utf8.decode((response.body as FixedBody).bytes);
      expect(message.length, lessThan(700));
      expect(message, contains('…'));
    });

    test('is kept when it is short', () {
      final error = const TransportErrors(false).unexpectedError(
        StateError('short'),
      );
      expect(error.message, 'Bad state: short');
    });
  });

  group('a batch', () {
    test('stops running items once the client has gone', () async {
      final signal = CancelSignal();
      final response = await http
          .handler(
            options: const HttpOptions(batching: BatchPolicy()),
            contextFactory: (_) {
              signal.cancel();
              return const Ctx('x');
            },
          )
          .handle(
            http.post([
              {'query': '{ hello }'},
              {'query': '{ hello }'},
              {'query': '{ hello }'},
            ], cancelSignal: signal),
          );
      expect(http.contexts, 1);
      final slots = (await http.json(response))! as List<Object?>;
      expect(slots, hasLength(3));
      for (final slot in slots.skip(1)) {
        final errors = (slot! as Map<String, Object?>)['errors']! as List;
        final extensions =
            (errors.first! as Map<String, Object?>)['extensions']!
                as Map<String, Object?>;
        expect(extensions['code'], 'GQL350');
      }
    });
  });
}
