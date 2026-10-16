# M11f End-to-End Tests, Web CI and Stage Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close stage M11: end-to-end tests of the client against M6's `GraphQLServer` with no network (queries, partial data, validation errors, GET with CSRF prevention, automatic persisted queries, trusted documents, token refresh, de-duplication, a subscription over server-sent events), the client suite in the dart2js and dart2wasm CI job, a runnable example, and the stage documents (READMEs, `llms.txt`, `docs/discovery.md`, `CLAUDE.md`, the handoff).

**Architecture:** Tests only, plus documents and CI. `typed_graphql_server` becomes a dev dependency of the client (architecture section 1 allows it); nothing in `lib/` changes. `test/e2e/support/` holds the in-memory `PipelineTransport` (an `HttpTransport` that decodes a `TransportRequest`, calls `GraphQLServer.handle` and writes the response: JSON for a `SingleResponse`, an event stream for a `StreamResponse`), the test schema and server, a `TickSource` whose cancellation a test can see, and two hand-written operations with real SHA-256 hashes. M7 is not needed: the HTTP status mapping here is a test double; M11z re-runs the scenarios through M7's handlers.

**Tech Stack:** Dart 3.13 (formatted with the 3.47.6 SDK), `package:test`, `package:meta`, `package:fake_async` (dev, from M11a Task 10), `package:http` (from M11b), `typed_graphql_server` (dev, this plan)

**Spec:** `docs/superpowers/specs/2026-10-16-m11-client-runtime-design.md` (sections 1, 15 and 18), `docs/discovery.md`, `docs/requirements.md` (R8.1-R8.5, R11.1-R11.3).

**Base:** the tree after M11a, M11b, M11c, M11d and M11e are all merged.

**Parallelism:** none: M11f comes after every other M11 plan and touches the shared files last. M11z (`2026-10-16-m11z-end-to-end-over-m7.md`) runs only after M7 is merged and reuses this plan's test support (`TestServer`, `TestSchema`, `TickSource`, the operations).

**Provenance:** the controller verified every task in a scratch copy holding the M11a-M11e commits merged in plan order (the shared files merged by keeping both sides), one commit per task. Every commit passed format (0 changed), `dart analyze --fatal-infos` (no issues), the root suite (353 tests, 381 after the documents) and the client suite (617 tests after task 1, 620 after tasks 2 and 3, 621 after task 4); `dart doc` for the client reports 0 warnings and 0 errors. The CI change was not run (no Chrome locally): CI runs it.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, never catch `Error`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and the client suite green (a task that touches the core also the core suite).
- **Memory and time limits.** Run every `dart` command through this wrapper, one heavy Dart process at a time (the lock is shared with other agents: waiting on it is normal; never kill a process you did not start):

  ```sh
  flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 <command>'
  ```

  Filter the output with `| tail`. No Chrome runs locally: CI covers dart2js and dart2wasm.
- **Formatter.** The wrapper puts the 3.47.6 SDK first on `PATH`, so `dart format` is the newer formatter CLAUDE.md asks for (3.13.1's crashes on `diagnostic_code.dart`).
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen` or `packages/typed_graphql_server` (M11f only adds the server as a client dev dependency).
- Commits use Conventional Commits, one per task, with the subject given in the task and a trailer naming the real model of the implementer, for example `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Run every command from the repository root unless a step says otherwise.
- Changes to existing files are unified diffs against the tree the earlier tasks leave. If a hunk does not apply, the tree has drifted (or a parallel plan merged first): save the diff to a file and apply it with `git apply --3way`; for the shared files listed under **Parallelism**, keep both sides' lines (exports and categories sorted). If that fails, stop and report it.
- Tests never read git-ignored or untracked files and never open a socket or a port.
- `lib/` of the client imports only `dart:async`, `dart:collection`, `dart:convert`, `dart:core`, `dart:math`, `dart:typed_data`, `package:meta`, the core barrel and (from M11b) `package:http/http.dart` (`test/quality/imports_test.dart`).

## Interfaces consumed

- Every public API of M11a-M11e: `GraphQLClient`, `GraphQLData`, `GraphQLErrors`, `GraphQLTransportFailure`, `HttpLink`, `HttpTransport`, `TransportRequest`, `TransportResponse`, `PersistedQueryLink`, `AuthLink`, `DedupeLink`, `SseLink`, `MockLink`, `Link.from`.
- M6 (server, dev dependency): `GraphQLServer`, `ServerRequest`, `RequestInfo`, `SingleResponse`, `StreamResponse`, `ServerOutcome`, `MemoryPersistedQueryStore`, `TrustedDocuments.decode`, `ExecutableSchemaBuilder`, `GraphQLException`.
- Test support of M11a: `test/support/test_operations.dart` (`HelloQuery`, `GreetQuery`, `RenameMutation`, `TicksSubscription`).

## Interfaces produced

- Test support for M11z: `test/e2e/support/test_server.dart` (`TestServer().build({persistedQueries, trustedDocuments, ticks})`), `test_schema.dart` (`TestSchema`), `tick_source.dart` (`TickSource`, `isCancelled`), `e2e_operations.dart` (`PartialQuery`, `UnknownFieldQuery`).
- `packages/typed_graphql_client/example/example.dart`.
- The CI job `web` runs the client suite under dart2js and dart2wasm.

## File map

| File | Change | Task |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | 3 |
| `CLAUDE.md` | Modify | 3, 4 |
| `README.md` | Modify | 4 |
| `docs/discovery.md` | Modify | 4 |
| `docs/superpowers/HANDOFF.md` | Modify | 4 |
| `llms.txt` | Modify | 4 |
| `packages/typed_graphql_client/CHANGELOG.md` | Modify | 4 |
| `packages/typed_graphql_client/README.md` | Modify | 4 |
| `packages/typed_graphql_client/example/example.dart` | Create | 4 |
| `packages/typed_graphql_client/lib/typed_graphql_client.dart` | Modify | 4 |
| `packages/typed_graphql_client/pubspec.yaml` | Modify | 1, 4 |
| `packages/typed_graphql_client/test/e2e/get_test.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e/persisted_queries_test.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e/policy_links_test.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e/queries_test.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e/subscription_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/e2e/support/e2e_operations.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e/support/event_stream_writer.dart` | Create | 2 |
| `packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart` | Create/Modify | 1, 2 |
| `packages/typed_graphql_client/test/e2e/support/request_params_reader.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e/support/served_request.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e/support/test_schema.dart` | Create/Modify | 1, 2 |
| `packages/typed_graphql_client/test/e2e/support/test_server.dart` | Create/Modify | 1, 2 |
| `packages/typed_graphql_client/test/e2e/support/tick_source.dart` | Create | 2 |
| `packages/typed_graphql_client/test/example_test.dart` | Create | 4 |
| `packages/typed_graphql_codegen/README.md` | Modify | 4 |
| `test/discovery/llms_file_test.dart` | Modify | 4 |

### Task 1: test(typed_graphql_client): add the end-to-end tests against the server pipeline

**Why.** Spec section 15 (R8.4, R11.3). `typed_graphql_server` becomes a dev dependency. `PipelineTransport` serves each `TransportRequest` with M6's `GraphQLServer.handle` and records what it served; its status mapping (`executed` 200, `requestError` 400, `methodNotAllowed` 405, `internalError` 500) is a test double, since M7 owns the real one. Ruling: a stale token is refused by the transport with a 401 (`isAuthorized`), as a gateway would, because M6's context factory can only turn a refusal into a request error. The scenarios: a query with variables, partial data, a validation error (`GQL205`), a `GET` query with the preflight header beside a `POST` mutation, automatic persisted queries (miss, text, then the hash alone), a server without a store, trusted documents (an untrusted query is `GQL415`), `AuthLink` refreshing once also for two concurrent queries, and `DedupeLink` sending two concurrent identical queries once.

**Files** (verified commit `d9f1dc8` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/pubspec.yaml`
- Create `packages/typed_graphql_client/test/e2e/get_test.dart`
- Create `packages/typed_graphql_client/test/e2e/persisted_queries_test.dart`
- Create `packages/typed_graphql_client/test/e2e/policy_links_test.dart`
- Create `packages/typed_graphql_client/test/e2e/queries_test.dart`
- Create `packages/typed_graphql_client/test/e2e/support/e2e_operations.dart`
- Create `packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart`
- Create `packages/typed_graphql_client/test/e2e/support/request_params_reader.dart`
- Create `packages/typed_graphql_client/test/e2e/support/served_request.dart`
- Create `packages/typed_graphql_client/test/e2e/support/test_schema.dart`
- Create `packages/typed_graphql_client/test/e2e/support/test_server.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/e2e/get_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';

void main() {
  late PipelineTransport transport;
  late GraphQLClient client;

  setUp(() {
    transport = PipelineTransport(const TestServer().build());
    client = GraphQLClient(
      link: HttpLink(
        uri: Uri.parse('http://localhost/graphql'),
        transport: transport,
        usesGetForQueries: true,
      ),
    );
  });

  group('GET queries over the pipeline', () {
    test('a query goes as GET with the preflight header', () async {
      await client.query(const GreetQuery('Ada'));
      final served = transport.served.single;
      expect(served.method, 'GET');
      expect(served.headers['graphql-require-preflight'], 'true');
    });

    test('CSRF prevention accepts the GET query', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
    });

    test('the variables travel in the query string', () async {
      await client.query(const GreetQuery('Ada'));
      expect(
        transport.served.single.uri.queryParameters['variables'],
        '{"name":"Ada"}',
      );
    });

    test('a mutation through the same link goes as POST', () async {
      final response = await client.mutate(const RenameMutation('Grace'));
      expect((response as GraphQLData<String>).data, 'Grace');
      expect(transport.served.single.method, 'POST');
    });
  });
}
```

Create `packages/typed_graphql_client/test/e2e/persisted_queries_test.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/test_operations.dart';
import 'support/e2e_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';

void main() {
  final uri = Uri.parse('http://localhost/graphql');

  GraphQLClient clientOver(PipelineTransport transport, Link persisted) =>
      GraphQLClient(
        link: Link.from([persisted, HttpLink(uri: uri, transport: transport)]),
      );

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  group('automatic persisted queries', () {
    late PipelineTransport transport;
    late GraphQLClient client;

    setUp(() {
      transport = PipelineTransport(
        const TestServer().build(persistedQueries: MemoryPersistedQueryStore()),
      );
      client = clientOver(transport, PersistedQueryLink());
    });

    test('the first query is a miss, then a resend with the text', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(transport.served.map((request) => request.params.query), [
        isNull,
        HelloQuery.operationDocument.text,
      ]);
    });

    test('the second identical query sends the hash alone', () async {
      await client.query(const HelloQuery());
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(transport.served, hasLength(3));
      expect(transport.served.last.params.query, isNull);
    });
  });

  group('a server without a store', () {
    test('answers not supported and the link switches to text', () async {
      final transport = PipelineTransport(const TestServer().build());
      final client = clientOver(transport, PersistedQueryLink());
      final first = await client.query(const HelloQuery());
      await client.query(const HelloQuery());
      expect((first as GraphQLData<String>).data, 'hello');
      expect(transport.served.map((request) => request.params.query), [
        isNull,
        HelloQuery.operationDocument.text,
        HelloQuery.operationDocument.text,
      ]);
    });
  });

  group('trusted documents', () {
    late PipelineTransport transport;
    late GraphQLClient client;

    setUp(() {
      final manifest = const JsonReader().parse(
        jsonEncode({
          'format': 'apollo-persisted-query-manifest',
          'version': 1,
          'operations': [
            {
              'id': HelloQuery.operationDocument.sha256,
              'name': 'Hello',
              'type': 'query',
              'body': HelloQuery.operationDocument.text,
            },
          ],
        }),
      );
      final trusted = switch (manifest) {
        DecodeSuccess(:final value) => switch (TrustedDocuments.decode(value)) {
          DecodeSuccess(:final value) => value,
          DecodeFailure(:final message) => throw StateError(message),
        },
        DecodeFailure(:final message) => throw StateError(message),
      };
      transport = PipelineTransport(
        const TestServer().build(trustedDocuments: trusted),
      );
      client = clientOver(transport, PersistedQueryLink(isAutomatic: false));
    });

    test('a trusted query succeeds with the hash alone', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(transport.served.single.params.query, isNull);
    });

    test('an untrusted query gives GQL415', () async {
      final response = await client.query(const PartialQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL415']);
    });
  });
}
```

Create `packages/typed_graphql_client/test/e2e/policy_links_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';

void main() {
  final uri = Uri.parse('http://localhost/graphql');

  group('AuthLink with a refresh', () {
    late PipelineTransport transport;
    late GraphQLClient client;
    late String token;
    late int refreshes;

    setUp(() {
      token = 'stale';
      refreshes = 0;
      transport = PipelineTransport(
        const TestServer().build(),
        isAuthorized: (authorization) => authorization == 'Bearer fresh',
      );
      client = GraphQLClient(
        link: Link.from([
          AuthLink(
            token: () => token,
            refresh: () async {
              refreshes++;
              return token = 'fresh';
            },
          ),
          HttpLink(uri: uri, transport: transport),
        ]),
      );
    });

    test('a stale token is refreshed and the query succeeds', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(
        transport.served.map((request) => request.headers['authorization']),
        ['Bearer stale', 'Bearer fresh'],
      );
    });

    test('two queries at the same time refresh once', () async {
      final responses = await Future.wait([
        client.query(const HelloQuery()),
        client.query(const GreetQuery('Ada')),
      ]);
      expect(responses.every((response) => response is GraphQLData), isTrue);
      expect(refreshes, 1);
    });
  });

  group('DedupeLink', () {
    test('two identical queries at the same time reach the server once', () {
      final transport = PipelineTransport(const TestServer().build());
      final client = GraphQLClient(
        link: Link.from([
          DedupeLink(),
          HttpLink(uri: uri, transport: transport),
        ]),
      );
      return Future.wait([
        client.query(const GreetQuery('Ada')),
        client.query(const GreetQuery('Ada')),
      ]).then((responses) {
        expect(responses.whereType<GraphQLData<String>>(), hasLength(2));
        expect(transport.served, hasLength(1));
      });
    });
  });
}
```

Create `packages/typed_graphql_client/test/e2e/queries_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/e2e_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_schema.dart';
import 'support/test_server.dart';

void main() {
  late PipelineTransport transport;
  late GraphQLClient client;

  setUp(() {
    transport = PipelineTransport(const TestServer().build());
    client = GraphQLClient(
      link: HttpLink(
        uri: Uri.parse('http://localhost/graphql'),
        transport: transport,
      ),
    );
  });

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  group('queries over the pipeline', () {
    test('a query with variables gives the data', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect(response, isA<GraphQLData<String>>());
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(response.hasErrors, isFalse);
    });

    test('the variables reach the server as JSON', () async {
      await client.query(const GreetQuery('Ada'));
      expect(
        transport.served.single.params.variables,
        JsonObject({'name': const JsonString('Ada')}),
      );
    });

    test('a mutation over POST gives the data', () async {
      final response = await client.mutate(const RenameMutation('Grace'));
      expect((response as GraphQLData<String>).data, 'Grace');
      expect(transport.served.single.method, 'POST');
    });

    test('a failing field gives the data with the error', () async {
      final response = await client.query(const PartialQuery());
      final data = response as GraphQLData<String>;
      expect(data.data, 'hello');
      expect(data.errors.map(codeOf), [TestSchema.brokenCode]);
    });

    test('an unknown field gives the errors with the code', () async {
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
    });
  });
}
```

Create `packages/typed_graphql_client/test/e2e/support/e2e_operations.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../../support/test_operations.dart';

/// `query Partial{hello broken}`: `broken` fails, `hello` is the data.
final class PartialQuery extends GraphQLQuery<String> {
  /// Creates the query.
  const PartialQuery();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Partial',
    type: OperationType.query,
    text: 'query Partial{hello broken}',
    sha256: '07e000c279847cbe0d5541f498b549a3c88c3a162a6303002bd4949188141b3c',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('hello').read(data);
}

/// `query Unknown{nope}`: the schema has no field `nope`.
final class UnknownFieldQuery extends GraphQLQuery<String> {
  /// Creates the query.
  const UnknownFieldQuery();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Unknown',
    type: OperationType.query,
    text: 'query Unknown{nope}',
    sha256: '2271bbec64e5cd1210f83921cd7205cc41d186daefd83e73736669b8352b8e6e',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('nope').read(data);
}
```

Create `packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'request_params_reader.dart';
import 'served_request.dart';

/// An [HttpTransport] that serves each request with a [GraphQLServer], with
/// no network, and records what it served.
///
/// The status of a response is the one GraphQL over HTTP gives the
/// [ServerOutcome]: `executed` 200, `requestError` 400, `methodNotAllowed`
/// 405, `internalError` 500. M7 will own this mapping; here it is a test
/// double.
///
/// `isAuthorized` stands for the authentication layer in front of a real
/// server: the M6 context factory can only turn a refusal into a 400
/// `requestError`, so a stale token is answered here with a 401 before the
/// server runs, as a gateway would.
final class PipelineTransport implements HttpTransport {
  /// Creates a transport over [server]; [isAuthorized] receives the
  /// `authorization` header (null when absent) and, when it gives false, the
  /// request is answered with a 401 and never reaches the server.
  PipelineTransport(this.server, {this.isAuthorized});

  /// The server that answers.
  final GraphQLServer<Object?> server;

  /// Decides from the `authorization` header whether a request is served.
  final bool Function(String? authorization)? isAuthorized;

  /// Every request received, in order, including the refused ones.
  final List<ServedRequest> served = [];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final params = await const RequestParamsReader().read(request);
    served.add(
      ServedRequest(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        params: params,
      ),
    );
    if (isAuthorized?.call(request.headers['authorization']) == false) {
      return _unauthorized();
    }
    final response = await server.handle(
      ServerRequest(
        params: params,
        info: RequestInfo(
          method: request.method,
          uri: request.uri,
          headers: request.headers,
        ),
      ),
    );
    return switch (response) {
      SingleResponse() => _write(response),
      StreamResponse() => throw StateError('Streams need M7 (M11z).'),
    };
  }

  TransportResponse _write(SingleResponse response) => _answer(
    switch (response.outcome) {
      ServerOutcome.executed => 200,
      ServerOutcome.requestError => 400,
      ServerOutcome.methodNotAllowed => 405,
      ServerOutcome.internalError => 500,
    },
    response.body,
    response.headers,
  );

  TransportResponse _unauthorized() => _answer(
    401,
    JsonObject({
      'errors': JsonArray([GraphQLError('Unauthorized.').toJson()]),
    }),
    const {},
  );

  TransportResponse _answer(
    int status,
    JsonObject body,
    Map<String, String> headers,
  ) => TransportResponse(
    statusCode: status,
    headers: {...headers, 'content-type': 'application/graphql-response+json'},
    body: Stream.value(utf8.encode(jsonEncode(body.toJson()))),
  );
}
```

Create `packages/typed_graphql_client/test/e2e/support/request_params_reader.dart`:

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

/// Reads the GraphQL parameters of a [TransportRequest] as GraphQL over HTTP
/// defines them: the JSON body of a `POST`, the query parameters of a `GET`.
final class RequestParamsReader {
  /// Creates the reader.
  const RequestParamsReader();

  /// The parameters of [request]; a request this client cannot have sent is
  /// a [StateError], since it is a bug of the test.
  Future<GraphQLRequest> read(TransportRequest request) async {
    final json = request.method == 'GET'
        ? _fromQuery(request.uri.queryParameters)
        : await _fromBody(request);
    return switch (GraphQLRequest.decode(json)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure(:final message) => throw StateError(message),
    };
  }

  Future<JsonValue> _fromBody(TransportRequest request) async {
    final bytes = await (request.body ?? const Stream<List<int>>.empty())
        .expand((chunk) => chunk)
        .toList();
    return _parse(utf8.decode(bytes));
  }

  JsonValue _fromQuery(Map<String, String> parameters) => JsonObject({
    'query': ?_text(parameters['query']),
    'operationName': ?_text(parameters['operationName']),
    'variables': ?_json(parameters['variables']),
    'extensions': ?_json(parameters['extensions']),
  });

  JsonString? _text(String? value) => value == null ? null : JsonString(value);

  JsonValue? _json(String? value) => value == null ? null : _parse(value);

  JsonValue _parse(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    DecodeFailure(:final message) => throw StateError(message),
  };
}
```

Create `packages/typed_graphql_client/test/e2e/support/served_request.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// One request a `PipelineTransport` served, as it went over the wire.
final class ServedRequest {
  /// Creates the record.
  const ServedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.params,
  });

  /// The HTTP method.
  final String method;

  /// The URL, with the query parameters of a `GET` request.
  final Uri uri;

  /// The headers, names in lower case.
  final Map<String, String> headers;

  /// The GraphQL parameters the server received.
  final GraphQLRequest params;

  @override
  String toString() => 'ServedRequest($method $uri)';
}
```

Create `packages/typed_graphql_client/test/e2e/support/test_schema.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The schema the client's hand-written test operations run against.
final class TestSchema {
  /// Creates the description.
  const TestSchema();

  /// The code of the error the `broken` field fails with.
  static const String brokenCode = 'BROKEN';

  /// Builds the schema: `hello`, `greet(name:)`, a `broken` field that
  /// fails, and the mutation `rename(name:)`.
  ExecutableSchema<Object?> build() {
    final b = ExecutableSchemaBuilder<Object?>();
    final name = Arg('name', b.string);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'hello'),
        t
            .field('greet', b.string, args: [name])
            .resolve(
              (parent, args, context, info) => 'Hello, ${args.get(name)}!',
            ),
        t
            .field('broken', b.string.nullable)
            .resolve(
              (parent, args, context, info) => throw GraphQLException(
                'It is broken.',
                extensions: JsonObject({'code': const JsonString(brokenCode)}),
              ),
            ),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t
            .field('rename', b.string, args: [name])
            .resolve((parent, args, context, info) => args.get(name)),
      ],
    );
    return b.build(query: query, mutation: mutation);
  }
}
```

Create `packages/typed_graphql_client/test/e2e/support/test_server.dart`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'test_schema.dart';

/// Builds the M6 server the end-to-end tests talk to.
final class TestServer {
  /// Creates the description.
  const TestServer();

  /// A server over [TestSchema] with the production profile; its context is
  /// not used, so it is null.
  GraphQLServer<Object?> build({
    PersistedQueryStore? persistedQueries,
    TrustedDocuments? trustedDocuments,
  }) => GraphQLServer<Object?>(
    schema: const TestSchema().build(),
    contextFactory: (request) => null,
    persistedQueries: persistedQueries,
    trustedDocuments: trustedDocuments,
  );
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: the new tests do not compile: the `test/e2e/support/` files do not exist (and `typed_graphql_server` is not a dependency until the pubspec change and `pub get`).

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/pubspec.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/pubspec.yaml b/packages/typed_graphql_client/pubspec.yaml
index ba51e1d..c54ff7b 100644
--- a/packages/typed_graphql_client/pubspec.yaml
+++ b/packages/typed_graphql_client/pubspec.yaml
@@ -17,5 +17,6 @@ dependencies:
 dev_dependencies:
   fake_async: ^1.3.1
   test: ^1.31.0
+  typed_graphql_server: ^0.0.1
 
 resolution: workspace
```

- [ ] **Step 4: Format, then run the green check.**

This task changes a `pubspec.yaml`: run `flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart pub get'` at the root before anything else.

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes (617 client tests).

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "test(typed_graphql_client): add the end-to-end tests against the server pipeline

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 2: test(typed_graphql_client): add the end-to-end subscription over server-sent events

**Why.** Spec sections 12 and 15. `PipelineTransport` answered a `StreamResponse` with a `StateError`; it now answers a request that accepts `text/event-stream` with 200 `text/event-stream; charset=utf-8` and a lazy body (`EventStreamWriter`): one `event: next` per result, then `event: complete` (the M7 spec's distinct connections format). Cancelling the body, or the request's `abortTrigger`, cancels the server's results stream. The schema gains `Subscription.ticks: Int!` over a `TickSource` (`stream()` counts 1, 2, 3; `isCancelled` tells a test the source was cancelled), passed through `TestSchema.build({ticks})` and `TestServer().build({..., ticks})`; M11z reuses these names. The tests: `SseLink` receives the three ticks and the end, a cancel after the first tick reaches the server's source, and a query through `SseLink` gives the data.

**Files** (verified commit `c037edc` of the controller's scratch copy):

- Create `packages/typed_graphql_client/test/e2e/subscription_test.dart`
- Create `packages/typed_graphql_client/test/e2e/support/event_stream_writer.dart`
- Modify `packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart`
- Modify `packages/typed_graphql_client/test/e2e/support/test_schema.dart`
- Modify `packages/typed_graphql_client/test/e2e/support/test_server.dart`
- Create `packages/typed_graphql_client/test/e2e/support/tick_source.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/e2e/subscription_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';
import 'support/tick_source.dart';

void main() {
  late TickSource ticks;
  late GraphQLClient client;

  setUp(() {
    ticks = TickSource();
    client = GraphQLClient(
      link: SseLink(
        uri: Uri.parse('http://localhost/graphql'),
        transport: PipelineTransport(const TestServer().build(ticks: ticks)),
      ),
    );
  });

  group('server-sent events over the pipeline', () {
    test('a subscription delivers the ticks and ends', () async {
      final responses = await client
          .subscribe(const TicksSubscription())
          .toList();
      expect(
        responses.map((response) => (response as GraphQLData<int>).data),
        [1, 2, 3],
      );
    });

    test('cancelling after the first tick cancels the source', () async {
      final subscription = client
          .subscribe(const TicksSubscription())
          .listen(null);
      final first = Completer<GraphQLResponse<int>>();
      subscription.onData(first.complete);
      await first.future;
      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(ticks.isCancelled, isTrue);
    });

    test('a query through the link gives the data', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
    });
  });
}
```

Create `packages/typed_graphql_client/test/e2e/support/event_stream_writer.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

/// Writes the results of a subscription as a graphql-sse event stream in
/// distinct connections mode: one `next` event per result, then `complete`.
final class EventStreamWriter {
  /// Creates the writer.
  const EventStreamWriter();

  /// The bytes of the event stream for [results]; it is lazy, and cancelling
  /// it, or completing [abortTrigger], cancels [results].
  Stream<List<int>> write(
    Stream<ExecutionResult> results,
    Future<void>? abortTrigger,
  ) {
    late StreamController<List<int>> controller; // Set below, read by onListen.
    StreamSubscription<ExecutionResult>? subscription;
    controller = StreamController<List<int>>(
      onListen: () {
        subscription = results.listen(
          (result) => controller.add(
            utf8.encode(
              'event: next\ndata: ${jsonEncode(result.toJson().toJson())}\n\n',
            ),
          ),
          onError: controller.addError,
          onDone: () {
            controller.add(utf8.encode('event: complete\ndata: \n\n'));
            controller.close();
          },
        );
        abortTrigger?.then((_) {
          subscription?.cancel();
          controller.close();
        });
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
```

Modify `packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart b/packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart
index d8d4e8f..5b1af26 100644
--- a/packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart
+++ b/packages/typed_graphql_client/test/e2e/support/pipeline_transport.dart
@@ -5,6 +5,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_client/typed_graphql_client.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
+import 'event_stream_writer.dart';
 import 'request_params_reader.dart';
 import 'served_request.dart';
 
@@ -61,10 +62,32 @@ final class PipelineTransport implements HttpTransport {
     );
     return switch (response) {
       SingleResponse() => _write(response),
-      StreamResponse() => throw StateError('Streams need M7 (M11z).'),
+      StreamResponse() when _acceptsEventStream(request) => _stream(
+        response,
+        request,
+      ),
+      StreamResponse() => throw StateError('A stream needs text/event-stream.'),
     };
   }
 
+  bool _acceptsEventStream(TransportRequest request) =>
+      request.headers['accept']?.contains('text/event-stream') ?? false;
+
+  TransportResponse _stream(
+    StreamResponse response,
+    TransportRequest request,
+  ) => TransportResponse(
+    statusCode: 200,
+    headers: {
+      ...response.headers,
+      'content-type': 'text/event-stream; charset=utf-8',
+    },
+    body: const EventStreamWriter().write(
+      response.results,
+      request.abortTrigger,
+    ),
+  );
+
   TransportResponse _write(SingleResponse response) => _answer(
     switch (response.outcome) {
       ServerOutcome.executed => 200,
```

Modify `packages/typed_graphql_client/test/e2e/support/test_schema.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/test/e2e/support/test_schema.dart b/packages/typed_graphql_client/test/e2e/support/test_schema.dart
index d8210a0..91ae821 100644
--- a/packages/typed_graphql_client/test/e2e/support/test_schema.dart
+++ b/packages/typed_graphql_client/test/e2e/support/test_schema.dart
@@ -1,6 +1,8 @@
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
+import 'tick_source.dart';
+
 /// The schema the client's hand-written test operations run against.
 final class TestSchema {
   /// Creates the description.
@@ -10,8 +12,10 @@ final class TestSchema {
   static const String brokenCode = 'BROKEN';
 
   /// Builds the schema: `hello`, `greet(name:)`, a `broken` field that
-  /// fails, and the mutation `rename(name:)`.
-  ExecutableSchema<Object?> build() {
+  /// fails, the mutation `rename(name:)` and the subscription `ticks`, whose
+  /// events come from [ticks] (a fresh [TickSource] when null).
+  ExecutableSchema<Object?> build({TickSource? ticks}) {
+    final source = ticks ?? TickSource();
     final b = ExecutableSchemaBuilder<Object?>();
     final name = Arg('name', b.string);
     final query = b.object<Object?>(
@@ -41,6 +45,18 @@ final class TestSchema {
             .resolve((parent, args, context, info) => args.get(name)),
       ],
     );
-    return b.build(query: query, mutation: mutation);
+    final subscription = b.object<Object?>(
+      'Subscription',
+      fields: (t) => [
+        t
+            .field('ticks', b.int)
+            .subscribe((parent, args, context, info) => source.stream()),
+      ],
+    );
+    return b.build(
+      query: query,
+      mutation: mutation,
+      subscription: subscription,
+    );
   }
 }
```

Modify `packages/typed_graphql_client/test/e2e/support/test_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/test/e2e/support/test_server.dart b/packages/typed_graphql_client/test/e2e/support/test_server.dart
index 604f448..1169448 100644
--- a/packages/typed_graphql_client/test/e2e/support/test_server.dart
+++ b/packages/typed_graphql_client/test/e2e/support/test_server.dart
@@ -1,6 +1,7 @@
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
 import 'test_schema.dart';
+import 'tick_source.dart';
 
 /// Builds the M6 server the end-to-end tests talk to.
 final class TestServer {
@@ -12,8 +13,9 @@ final class TestServer {
   GraphQLServer<Object?> build({
     PersistedQueryStore? persistedQueries,
     TrustedDocuments? trustedDocuments,
+    TickSource? ticks,
   }) => GraphQLServer<Object?>(
-    schema: const TestSchema().build(),
+    schema: const TestSchema().build(ticks: ticks),
     contextFactory: (request) => null,
     persistedQueries: persistedQueries,
     trustedDocuments: trustedDocuments,
```

Create `packages/typed_graphql_client/test/e2e/support/tick_source.dart`:

```dart
import 'dart:async';

/// The event source of the `ticks` subscription, which lets a test see
/// whether the server cancelled it.
final class TickSource {
  /// Creates a source that has not been listened to.
  TickSource();

  /// Whether a listener cancelled the stream before it was done.
  bool isCancelled = false;

  /// A lazy stream of 1, 2 and 3, then done; nothing runs until it is
  /// listened to.
  Stream<int> stream() {
    late StreamController<int> controller; // Set below, read by onListen.
    controller = StreamController<int>(
      onListen: () {
        for (var tick = 1; tick <= 3; tick++) {
          controller.add(tick);
        }
        controller.close();
      },
      onCancel: () => isCancelled = true,
    );
    return controller.stream;
  }
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/e2e/subscription_test.dart` does not compile: `tick_source.dart` does not exist and `TestServer.build` has no `ticks` parameter.

- [ ] **Step 3: Write the implementation.**

This commit changes only tests.

- [ ] **Step 4: Format, then run the green check.**

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes (620 client tests).

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "test(typed_graphql_client): add the end-to-end subscription over server-sent events

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 3: ci: run the client suite in Chrome

**Why.** Spec sections 2 and 18 (R0.5): the client imports no platform library, so its suite joins the `web` job beside the core, under dart2js and dart2wasm. Every client test that imports `dart:io` starts with `@TestOn('vm')` (`test/doc/category_tags_test.dart`, `test/doc/guide_snippets_test.dart`, `test/pubspec_test.dart`, `test/quality/imports_test.dart`), and nothing under `test/e2e`, `test/sse`, `test/socket`, `test/http` or `test/policy` imports it. `CLAUDE.md` lists the client's Chrome commands beside the core's. Chrome is not run locally: the first CI run is the check.

**Files** (verified commit `0251110` of the controller's scratch copy):

- Modify `.github/workflows/ci.yml`
- Modify `CLAUDE.md`

- [ ] **Step 1: Write the tests.**

This commit changes no test file.

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: nothing fails: this commit changes no Dart code. Read the diff, and check with `grep -rL "TestOn" $(grep -rl "dart:io" packages/typed_graphql_client/test)` that only `test/quality/import_rule.dart` (a library, not a test) is listed.

- [ ] **Step 3: Write the implementation.**

Modify `.github/workflows/ci.yml` (exact diff):

```diff
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
index 3545915..04d03c5 100644
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -103,7 +103,7 @@ jobs:
           done
 
   web:
-    name: Core on the web (${{ matrix.compiler }})
+    name: Core and client on the web (${{ matrix.compiler }})
     timeout-minutes: 20
     runs-on: ubuntu-latest
     strategy:
@@ -120,12 +120,14 @@ jobs:
       - name: Install dependencies (workspace)
         run: dart pub get
 
-      # The client joins this job when it has code that runs in a browser
-      # (M11); until then its only tests are VM-only.
       - name: Test typed_graphql in Chrome
         run: dart test -p chrome --compiler ${{ matrix.compiler }}
         working-directory: packages/typed_graphql
 
+      - name: Test typed_graphql_client in Chrome
+        run: dart test -p chrome --compiler ${{ matrix.compiler }}
+        working-directory: packages/typed_graphql_client
+
   publish-dry-run:
     name: Publish dry-run
     timeout-minutes: 10
```

Modify `CLAUDE.md` (exact diff):

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 83fc4ca..91a5414 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -110,6 +110,8 @@ cd packages/typed_graphql && dart test                        # one package (eve
 cd packages/typed_graphql && dart test --compiler exe         # AOT (sealed switches, sdk#56010)
 cd packages/typed_graphql && dart test -p chrome --compiler dart2js
 cd packages/typed_graphql && dart test -p chrome --compiler dart2wasm
+cd packages/typed_graphql_client && dart test -p chrome --compiler dart2js
+cd packages/typed_graphql_client && dart test -p chrome --compiler dart2wasm
 cd packages/typed_graphql && dart test test/doc               # snippets, links, category tags
 cd packages/typed_graphql && dart doc                         # must report "Found 0 warnings and 0 errors"
 cd packages/<package> && dart pub publish --dry-run           # never without --dry-run
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes (620 client tests).

- [ ] **Step 5: Commit.**

```sh
git add -A .github/workflows/ci.yml CLAUDE.md
git commit -m "ci: run the client suite in Chrome

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 4: docs: record stage M11 in the documents

**Why.** CLAUDE.md "Documentation" and `docs/discovery.md`: a stage that adds a capability records it, saying only what works today. The client README, pubspec description and library doc name the links, policies and `MockLink` that work, and leave the normalized cache to M12; `example/example.dart` runs a hand-written query and a subscription through a `GraphQLClient` over `MockLink`, and `test/example_test.dart` checks its four lines in a `runZoned` print override (no `dart:io`). `llms.txt` lists the client guides, so `test/discovery/llms_file_test.dart` now expects the core's and the client's guides; `docs/discovery.md` gains five M11 queries. The root README row, the codegen README status, `CLAUDE.md` (Status, a "Client runtime" architecture paragraph, Where things are), the client CHANGELOG and the handoff record the stage.

**Files** (verified commit `73f9e37` of the controller's scratch copy):

- Modify `CLAUDE.md`
- Modify `README.md`
- Modify `docs/discovery.md`
- Modify `docs/superpowers/HANDOFF.md`
- Modify `llms.txt`
- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/README.md`
- Create `packages/typed_graphql_client/example/example.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Modify `packages/typed_graphql_client/pubspec.yaml`
- Create `packages/typed_graphql_client/test/example_test.dart`
- Modify `packages/typed_graphql_codegen/README.md`
- Modify `test/discovery/llms_file_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/example_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';

import '../example/example.dart' as example;

void main() {
  test('the example prints the query and the three ticks', () async {
    final lines = <String>[];
    await runZoned(
      example.main,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
    expect(lines, ['hello: world', 'tick: 1', 'tick: 2', 'tick: 3']);
  });
}
```

Modify `test/discovery/llms_file_test.dart` (exact diff):

```diff
diff --git a/test/discovery/llms_file_test.dart b/test/discovery/llms_file_test.dart
index 70dd2f4..a147906 100644
--- a/test/discovery/llms_file_test.dart
+++ b/test/discovery/llms_file_test.dart
@@ -77,12 +77,13 @@ void main() {
     });
   }
 
-  test('lists exactly the guides of the core', () {
+  test('lists exactly the guides of the core and of the client', () {
     final guides = [
-      for (final file in Directory('packages/typed_graphql/doc').listSync())
-        if (file.uri.pathSegments.last case final name
-            when name.endsWith('.md'))
-          '${prefix}packages/typed_graphql/doc/$name',
+      for (final package in const ['typed_graphql', 'typed_graphql_client'])
+        for (final file in Directory('packages/$package/doc').listSync())
+          if (file.uri.pathSegments.last case final name
+              when name.endsWith('.md'))
+            '${prefix}packages/$package/doc/$name',
     ];
     final listed = llms
         .entriesOf('Guides')
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/example_test.dart` does not compile: `example/example.dart` does not exist. The rest is documents, checked by the root discovery suite and `test/doc`.

- [ ] **Step 3: Write the implementation.**

Modify `CLAUDE.md` (exact diff):

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 91a5414..c0a075a 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -80,7 +80,17 @@ emitters that generate the schema-types library and a library per document
 minified document with its SHA-256, the persisted-operations manifest), the
 codes `GQL500`-`GQL511`, the `generate` and `check` command line, `Optional`
 in the core, the generated-code contract in `typed_graphql_client`, the goldens
-and the Client Code Generation guide.
+and the Client Code Generation guide. M11 (client runtime) delivers
+`GraphQLClient` (`query`, `mutate`, `subscribe`) with the sealed
+`GraphQLResponse` and `ClientFailure` (`GQL460`-`GQL474`), `CancelToken`, the
+link chain (`Link.from`, `SplitLink`, `ContextLink`, `Backoff`, `MockLink`),
+`HttpLink` (GraphQL over HTTP, `GET` for queries, multipart uploads) over an
+`HttpTransport`, `RetryLink`, `DedupeLink`, `PersistedQueryLink` and `AuthLink`,
+`WebSocketLink` (graphql-transport-ws over an app-supplied `ClientSocket`) and
+`SseLink` (graphql-sse, distinct connections), the hostile-input tests, the
+end-to-end tests against `GraphQLServer`, the client suite in Chrome in CI, the
+example and the client guides; the normalized cache and `watchQuery` are M12,
+`@defer` and `@stream` M14, and the tests against the transports of M7 are M11z.
 
 ## Documents
 
@@ -615,6 +625,42 @@ scalar); `read` throws `DataFormatException`, `decode` turns it into a
 `DataEquality` compares lists and `Optional`s by value, and `JsonMerger`
 merges what a class and its fragments write for one object.
 
+**Client runtime** (`typed_graphql_client/lib/src/`; M11). Depends on `meta`,
+`http` and the core; `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
+or web framework (`test/quality/imports_test.dart`), so the package runs on the
+VM, AOT, dart2js and dart2wasm, and CI runs its suite in Chrome. Folders, each
+a dartdoc category with its guide: `client/`, `link/`, `upload/`, `http/`,
+`policy/`, `socket/`, `sse/` (and `operation/`, the contract above).
+`GraphQLClient` calls the link chain, decodes each result with the internal
+`ResponseDecoder` into `GraphQLData` | `GraphQLErrors` |
+`GraphQLTransportFailure`, and never throws for what a server or a network
+does; a link reports a failure as a `LinkFailure` value (`ClientFailure`, one
+code each), not with `addError`. `query` and `mutate` take the first result and
+cancel the chain; `subscribe` is a single-subscription stream that calls the
+chain on `listen`; `OperationStream` cancels upstream without awaiting it (a
+cancel future only the real event loop completes would hang `fakeAsync`). A
+`Link` returns `Stream<LinkResult>` and gets `forward`; `LinkContext` holds
+typed `ContextEntry`s (`RequestHeaders`, `HttpResponseInfo`, `UploadFiles`,
+`Idempotent`). `http/`: `HttpLink` talks to the `HttpTransport` seam, never to
+`package:http` types (`PackageHttpTransport` is the one adapter);
+`HttpRequestEncoder` builds POST, `GET` and multipart requests and merges
+headers (protocol, link, then context), `ResponseReader` picks the reader by
+media type under a byte and depth limit, `HttpExchange` sends, times out and
+aborts through `TransportRequest.abortTrigger`. `policy/`: `RetryLink` retries
+only queries and mutations marked `Idempotent` (never a GraphQL error),
+`DedupeLink` shares identical queries in flight through `SharedRequest`,
+`PersistedQueryLink` sends the hash and resends once with the text (APQ) or
+sends the hash alone (trusted documents), `AuthLink` adds a token and, on a 401, refreshes it once and resends once; a
+callback of the caller that throws ends the caller's stream with that error and
+cancels upstream. `socket/`: `WebSocketLink` is lazy, one socket for every
+operation, `connection_init`/`connection_ack`, keep-alive, reconnection with
+`Backoff` (the loop in `SocketDriver`, the operations in `SocketOperations`); a
+`ClientSocket` is three members the app implements, so no socket library is
+imposed. `sse/`: `SseLink` runs one `POST` per operation; the internal
+`EventStreamParser` is a stream transformer over `EventAssembler` (WHATWG
+rules, bounded by `maxEventBytes`), `next` is a result, `complete` ends the
+stream, anything else is `GQL473`; cancelling closes the connection.
+
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
 `ArgumentError`, `RangeError`, `StateError`.
@@ -838,6 +884,12 @@ README that leaves the package folder is an absolute URL.
   `RulePort` for the validation rule suites, `ExecutionPort` for the
   execution, variables and input-coercion suites).
 - Hostile-document tests: `packages/typed_graphql/test/validation/hostile_*_test.dart`.
+- Client end-to-end tests against `GraphQLServer` (queries, `GET`, persisted
+  queries, the policy links, a subscription over server-sent events):
+  `packages/typed_graphql_client/test/e2e/`, over the in-memory
+  `PipelineTransport` in `test/e2e/support/`. Client hostile-input tests:
+  `test/http/hostile_response_test.dart`, `test/socket/hostile_socket_test.dart`
+  and `test/sse/hostile_stream_test.dart`.
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
   round trip, hostile SDL, introspection round trip, hostile
   introspection, coordinates, valid operations, hostile operations and
```

Modify `README.md` (exact diff):

```diff
diff --git a/README.md b/README.md
index 26cac76..ae5e827 100644
--- a/README.md
+++ b/README.md
@@ -116,7 +116,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete), DataLoader, the request pipeline and persisted documents (M6, complete) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
-| [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
+| [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | `GraphQLClient`, links for HTTP, WebSocket and server-sent events, retry, dedupe, persisted queries, authentication, `MockLink` and the generated-code contract (M10, M11); the normalized cache is M12 |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
 | [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema, introspection, validation and execution suites, fuzzers, benchmarks (M2-M5) |
```

Modify `docs/discovery.md` (exact diff):

```diff
diff --git a/docs/discovery.md b/docs/discovery.md
index 3b0307e..0824c7e 100644
--- a/docs/discovery.md
+++ b/docs/discovery.md
@@ -51,6 +51,11 @@ adds its row (or turns it to "yes") together with its README line and its
 | GraphQL trusted documents dart | M6 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | yes |
+| dart graphql client | M11 | yes |
+| graphql subscriptions websocket dart | M11 | yes |
+| graphql over http client dart | M11 | yes |
+| graphql persisted queries client dart | M11 | yes |
+| graphql sse dart client | M11 | yes |
 
 ## Metadata
 
@@ -104,7 +109,7 @@ linked.
 
 `llms.txt` at the repository root has the [llmstxt.org](https://llmstxt.org)
 shape: one `#` title, one `>` summary, then the sections *Packages* (each with
-its README status), *Guides* (every `packages/typed_graphql/doc/*.md`) and
+its README status), *Guides* (every `doc/*.md` of `packages/typed_graphql` and `packages/typed_graphql_client`) and
 *Reference*. Every link is an absolute
 `https://github.com/4akloon/graphql_dart/blob/main/<path>` URL to a file of
 the repository. pub.dev package URLs are added at M16.
```

Modify `docs/superpowers/HANDOFF.md` (exact diff):

```diff
diff --git a/docs/superpowers/HANDOFF.md b/docs/superpowers/HANDOFF.md
index 1ec869b..c621e35 100644
--- a/docs/superpowers/HANDOFF.md
+++ b/docs/superpowers/HANDOFF.md
@@ -1,6 +1,6 @@
 # Handoff: where typed_graphql stands and how to continue
 
-Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M5 (a-d), M10 and M6 merged into `main` too (M6 merge 1fe4b2e); local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
+Last updated: 2026-10-16 (M11 built in a verification copy, not merged; M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M5 (a-d), M10 and M6 merged into `main` too (M6 merge 1fe4b2e); local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
 first on a new device or in a new Claude session. Session memory and scratch
 directories do not travel; this file and the repository hold everything
 needed.
@@ -23,7 +23,8 @@ db33dc7, 62ba263, cb78cf6, 8be71bd, 6981a03, 6c0dc4d, 383fa6a, f469521,
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
 | M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md); M5c: [plan](plans/2026-10-15-m5c-introspection-and-subscriptions.md); M5d: [plan](plans/2026-10-15-m5d-lookahead-authorization-cancellation.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; M5d is done on the same branch: `FieldInfo.selection` (look-ahead, `ColumnAllowlist`), `Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`, `GQL352`), `CancelSignal`, `timeout` and `FieldInfo.cancelSignal` (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor benchmark, spec §18 items 34-44 and the Look-ahead, Authorization and Cancellation guides. **Stage M5 is complete and merged into `main` (f963761; not pushed).** The final opus whole-branch review and its fix round are done (a guarded subscription is authorized once, at `subscribe`, and `execute` on it runs the guard; coerced arguments are frozen). Open questions for the owner are spec §21, with recommendations in `docs/superpowers/specs/2026-10-15-m5-execution-design.md`. Next: M6 (server pipeline) |
 | M6 Server pipeline | [spec](specs/2026-10-15-m6-server-pipeline-design.md) | M6a: [plan](plans/2026-10-15-m6a-dataloader.md); M6b: [plan](plans/2026-10-15-m6b-request-pipeline.md); M6c: [plan](plans/2026-10-15-m6c-persisted-documents.md) | Complete and merged into `main` (1fe4b2e; not pushed; the final review and its two fix rounds are done on sonnet, per the owner's rule that opus is only for specs and plans): M6a DataLoader (`BatchLoader`, `GroupedLoader`) and the DataLoader guide; M6b `GraphQLServer`, profiles and limits, the cost limit, CSRF prevention, the document cache, extensions (`GQL400`-`GQL403`), the hostile-input tests and the Server guide; M6c automatic persisted queries and trusted documents (`GQL410`-`GQL415`) and the Persisted Documents guide. Open questions for the owner are spec §17, with recommendations. Next: M7 (transports; it must pass `POST` in the per-message `RequestInfo` of a WebSocket connection, spec §16) |
-| M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete and merged into `main` (3d1fe38; not pushed): the final opus whole-branch review is done and its fix round is committed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
+| M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete and merged into `main` (3d1fe38; not pushed): the final opus whole-branch review is done and its fix round is committed (the plans are generated from the commits; the fix round's commits are in the M10d plan). `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
+| M11 Client runtime | [spec](specs/2026-10-16-m11-client-runtime-design.md) | `plans/2026-10-16-m11*.md`, one plan per sub-stage: M11a client core, M11b HTTP, M11c request policies, M11d WebSocket, M11e server-sent events, M11f end-to-end tests, CI and documents | M11a-M11f are built: `GraphQLClient` (`query`, `mutate`, `subscribe`), the sealed `GraphQLResponse` and `ClientFailure` (`GQL460`-`GQL474`), `CancelToken`, the link chain and `MockLink`, `HttpLink` (GET for queries, multipart uploads), `RetryLink`, `DedupeLink`, `PersistedQueryLink`, `AuthLink`, `WebSocketLink` over an app-supplied `ClientSocket`, `SseLink` (distinct connections), the hostile-input tests, the end-to-end tests against `GraphQLServer` through an in-memory transport (`test/e2e/`; the subscription over server-sent events included), the client suite in Chrome in CI (dart2js and dart2wasm), the example and the guides. The Chrome runs have not been seen locally (the 8 GB `ulimit`): the first CI run is their first run. **M11z waits for M7**: the same end-to-end tests over the real transports (HTTP, graphql-transport-ws, graphql-sse single connection). The normalized cache and `watchQuery` are M12, `@defer` and `@stream` M14. Open questions for the owner are spec section 17 |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
@@ -33,7 +34,7 @@ db33dc7, 62ba263, cb78cf6, 8be71bd, 6981a03, 6c0dc4d, 383fa6a, f469521,
   type cannot be sealed or matched with `is`).
 - `Source`, `SourceLocation` and `SourceSpan` live in `diagnostics/`.
 - `analysis_options.yaml` is adapted from typed_openapi's, not verbatim.
-- The client's web (dart2js, dart2wasm) test runs are deferred to M11.
+- The client's web (dart2js, dart2wasm) test runs joined CI with M11f.
 
 ## How a stage is done
 
@@ -133,6 +134,6 @@ M3b is complete and merged into `main` locally (not pushed). Left open by the M3
 
 - Remote: https://github.com/4akloon/graphql_dart (`main`).
 - CI: `.github/workflows/ci.yml` (format and analyze; tests on 3.13.0 and
-  stable on Linux, stable on macOS and Windows; AOT; the core in Chrome with
-  dart2js and dart2wasm; publish dry-run).
+  stable on Linux, stable on macOS and Windows; AOT; the core and the client in
+  Chrome with dart2js and dart2wasm; publish dry-run).
 - `reference/` is git-ignored; `tool/fetch_reference.sh` fetches it.
```

Modify `llms.txt` (exact diff):

```diff
diff --git a/llms.txt b/llms.txt
index 5dd08ff..bbacd80 100644
--- a/llms.txt
+++ b/llms.txt
@@ -1,13 +1,13 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); and serves transport-agnostic requests with GraphQLServer (a document cache, depth, alias, directive, token, length and cost limits, production and development profiles, CSRF prevention, extensions and error masking) with automatic persisted queries or trusted documents; the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); and serves transport-agnostic requests with GraphQLServer (a document cache, depth, alias, directive, token, length and cost limits, production and development profiles, CSRF prevention, extensions and error masking) with automatic persisted queries or trusted documents; the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on, typed_graphql_client, sends them with GraphQLClient over HTTP (GET queries, file uploads), WebSocket (graphql-transport-ws) or server-sent events, with retry, dedupe, persisted-query and authentication links and a MockLink for tests; its normalized cache is not built yet (M12). Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
 - [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation with opt-in limits and cost analysis, wire protocol and diagnostics
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
-- [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
-- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
+- [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the client runtime works (GraphQLClient with typed responses, links for HTTP, WebSocket and server-sent events, retry, dedupe, persisted queries, authentication and MockLink; guides: Client, Links, HTTP, Server-sent events, Request Policies, WebSocket, Uploads and Generated Operations in its doc folder, runnable example in its example folder); the normalized cache and watchQuery are not built yet (M12)
+- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which sends them (the server generator is M8)
 - [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation, DataLoader, Server and Persisted Documents in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation, DataLoader (BatchLoader, GroupedLoader) and the request pipeline (GraphQLServer with limits, the cost limit, CSRF prevention, extensions, automatic persisted queries and trusted documents) work; transport handlers (M7) come later
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
@@ -22,6 +22,15 @@
 - [Introspection](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/introspection.md): the introspection query, a schema's answer, and a schema built from an answer
 - [Operation validation](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/validation.md): validate a document against a schema; the rules and their codes; custom rules; work limits; limit rules and cost analysis
 - [Example](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/example/example.dart): a runnable program: report syntax errors, print a document, build a schema from SDL, validate a request
+- [Client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/client.md): send queries, mutations and subscriptions with GraphQLClient; the sealed responses and the failures with their codes; cancelling
+- [Client links](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/links.md): the link chain, Link.from, SplitLink, ContextLink, Backoff and MockLink for tests
+- [Client HTTP](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/http.md): HttpLink: GraphQL over HTTP, GET for queries, the transport seam and how an answer is read
+- [Client server-sent events](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/sse.md): SseLink: queries, mutations and subscriptions over graphql-sse in distinct connections mode
+- [Client request policies](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/policies.md): RetryLink, DedupeLink, PersistedQueryLink (automatic persisted queries and trusted documents) and AuthLink, and the order of a chain
+- [Client WebSocket](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/websocket.md): WebSocketLink: graphql-transport-ws over a ClientSocket you supply, keep-alive and reconnection
+- [Client uploads](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/uploads.md): send files over HTTP as the multipart request specification says
+- [Generated operations](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/operations.md): the contract code from typed_graphql_codegen compiles against: operations and data codecs
+- [Client example](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/example/example.dart): a runnable program: a query and a subscription over MockLink
 
 ## Reference
 
```

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 4b8acf4..d542083 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -79,3 +79,5 @@
   ends without `complete` is `GQL473`, an event limit (`GQL463`), strict
   incremental UTF-8, cancellation that closes the connection; the
   Server-sent events guide (R8.4).
+- `example/example.dart`: a query and a subscription over `MockLink`; the
+  README lists what works.
```

Modify `packages/typed_graphql_client/README.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_client/README.md b/packages/typed_graphql_client/README.md
index 1cfeae8..c90b657 100644
--- a/packages/typed_graphql_client/README.md
+++ b/packages/typed_graphql_client/README.md
@@ -4,20 +4,68 @@
 ![Role](https://img.shields.io/badge/role-client-blue)
 ![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)
 
-**A fully typed GraphQL client for Dart and Flutter: links, transports, a normalized cache and MockLink, for operations generated by typed_graphql_codegen.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
+**A fully typed GraphQL client for Dart and Flutter: send generated queries, mutations and subscriptions over HTTP, WebSocket or server-sent events through a chain of links, with typed responses instead of exceptions.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: under construction.** This release holds only the contract that
-> code generated by `typed_graphql_codegen` compiles against: `GraphQLQuery`,
-> `GraphQLMutation`, `GraphQLSubscription`, `OperationDocument` and the data
-> codecs (`DataCodec` and its kinds). The client itself arrives in stage M11
-> of the [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
+> **Status: under construction.** The client runtime works: `GraphQLClient`,
+> the sealed `GraphQLResponse`, links for HTTP, WebSocket and server-sent
+> events, request policies and `MockLink`. The normalized cache and
+> `watchQuery` (M12) and `@defer` / `@stream` (M14) are not built yet.
 
-The [Generated Operations guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/operations.md)
-describes the contract and shows how a decode failure reports its path. There
-is no client to send an operation yet; the part of typed_graphql that works
-today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql).
+## What works today
 
-Planned: `GraphQLClient`, the sealed `GraphQLResponse`, links for HTTP, WebSocket and SSE, and `MockLink` (M11); the normalized cache and `watchQuery` (M12).
+- `GraphQLClient` with `query`, `mutate` and `subscribe`; the result is a
+  sealed `GraphQLResponse` (`GraphQLData`, `GraphQLErrors`,
+  `GraphQLTransportFailure`), and a failure is a `ClientFailure` with a
+  stable code (`GQL460`-`GQL474`), never an exception.
+- Links: `Link.from`, `SplitLink`, `ContextLink` and `MockLink` for tests.
+- `HttpLink`: GraphQL over HTTP, `GET` for queries and multipart file
+  uploads.
+- `RetryLink`, `DedupeLink`, `PersistedQueryLink` (automatic persisted
+  queries and trusted documents) and `AuthLink`.
+- `WebSocketLink`: the graphql-transport-ws protocol over a `ClientSocket`
+  that your application supplies.
+- `SseLink`: graphql-sse in distinct connections mode. Single connection
+  mode is not supported.
+- The contract that code generated by `typed_graphql_codegen` compiles
+  against: `GraphQLQuery`, `GraphQLMutation`, `GraphQLSubscription`,
+  `OperationDocument` and the data codecs.
+
+## Quick start
+
+The operations come from `typed_graphql_codegen`. A client takes a link and
+sends them:
+
+```text
+final client = GraphQLClient(
+  link: HttpLink(
+    uri: Uri.parse('https://example.com/graphql'),
+    transport: PackageHttpTransport(http.Client()),
+  ),
+);
+
+switch (await client.query(const HelloQuery())) {
+  case GraphQLData(:final data):
+    print(data);
+  case GraphQLErrors(:final errors):
+    print(errors.first.message);
+  case GraphQLTransportFailure(:final failure):
+    print(failure);
+}
+```
+
+The [example](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/example/example.dart)
+is a complete program that runs a query and a subscription over `MockLink`.
+
+## Guides
+
+- [Client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/client.md): sending operations, responses and failures, cancelling
+- [Links](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/links.md): the link chain, `Link.from`, `SplitLink`, `ContextLink`, `MockLink`
+- [HTTP](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/http.md): `HttpLink`, `GET` for queries, transports
+- [Server-sent events](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/sse.md): `SseLink`
+- [Request Policies](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/policies.md): retry, dedupe, persisted queries, authentication
+- [WebSocket](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/websocket.md): `WebSocketLink` and `ClientSocket`
+- [Uploads](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/uploads.md): multipart file uploads
+- [Generated Operations](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/operations.md): the contract generated code compiles against
 
 ## License
 
````

Create `packages/typed_graphql_client/example/example.dart`:

```dart
// Runs a query and a subscription through a GraphQLClient whose link is a
// MockLink, so no network is needed. The operations are written by hand here;
// typed_graphql_codegen generates them from .graphql documents. Output goes
// through the zone, which keeps the program free of dart:io.
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class HelloQuery extends GraphQLQuery<String> {
  const HelloQuery();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Hello',
    type: OperationType.query,
    text: 'query Hello{hello}',
    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<String> decodeData(JsonObject data) => switch (data['hello']) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected a string', path: [PathKey('hello')]),
  };
}

final class TicksSubscription extends GraphQLSubscription<int> {
  const TicksSubscription();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Ticks',
    type: OperationType.subscription,
    text: 'subscription Ticks{ticks}',
    sha256: '14c970476cf383579b21ff6dbb8326a9f2e3ea340def21bcb5bf9cf9b1af1f38',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<int> decodeData(JsonObject data) => switch (data['ticks']) {
    JsonNumber(:final asInt?) => DecodeSuccess(asInt),
    _ => const DecodeFailure('expected an integer', path: [PathKey('ticks')]),
  };
}

Future<void> main() async {
  Stream<LinkResult> ticks() async* {
    for (var tick = 1; tick <= 3; tick++) {
      yield LinkPayload(
        ExecutionResult(JsonObject({'ticks': JsonNumber(tick)})),
      );
    }
  }

  final link = MockLink()
    ..addData(JsonObject({'hello': const JsonString('world')}))
    ..addStream(ticks());
  final client = GraphQLClient(link: link);

  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
    Zone.current.print('hello: $data');
  }
  await for (final response in client.subscribe(const TicksSubscription())) {
    if (response case GraphQLData(:final data)) {
      Zone.current.print('tick: $data');
    }
  }
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index 0ba9615..a5dc642 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -1,10 +1,16 @@
-/// A fully typed GraphQL client for Dart and Flutter: links, transports, a
-/// normalized cache and MockLink, for operations generated by
+/// A fully typed GraphQL client for Dart and Flutter: HTTP, WebSocket and SSE
+/// links, retry, persisted queries and MockLink, for operations generated by
 /// typed_graphql_codegen.
 ///
-/// This version holds only the contract generated code compiles against:
-/// operations, data codecs and their errors. The client itself arrives in
-/// stage M11; see the package README.
+/// [GraphQLClient] sends a generated query, mutation or subscription through
+/// a chain of links and returns a sealed [GraphQLResponse]; a request that
+/// gets no GraphQL response is a [ClientFailure] with a stable code, never an
+/// exception. The terminating links are [HttpLink], [WebSocketLink] and
+/// [SseLink]; [RetryLink], [DedupeLink], [PersistedQueryLink] and [AuthLink]
+/// sit in front of them, and [MockLink] stands in for a server in tests. The
+/// library also holds the contract generated code compiles against
+/// (operations and data codecs). The normalized cache is not built yet; see
+/// the package README.
 library;
 
 export 'src/client/cancel_token.dart';
```

Modify `packages/typed_graphql_client/pubspec.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/pubspec.yaml b/packages/typed_graphql_client/pubspec.yaml
index c54ff7b..6a11ad8 100644
--- a/packages/typed_graphql_client/pubspec.yaml
+++ b/packages/typed_graphql_client/pubspec.yaml
@@ -1,6 +1,6 @@
 name: typed_graphql_client
 description: >-
-  A fully typed GraphQL client for Dart and Flutter: links, transports, a normalized cache and MockLink, for operations generated by typed_graphql_codegen.
+  A fully typed GraphQL client for Dart and Flutter: HTTP, WebSocket and SSE links, retry, persisted queries and MockLink, for operations generated by typed_graphql_codegen.
 version: 0.0.1
 repository: https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_client
 issue_tracker: https://github.com/4akloon/graphql_dart/issues
```

Modify `packages/typed_graphql_codegen/README.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_codegen/README.md b/packages/typed_graphql_codegen/README.md
index 5d392b9..e90960e 100644
--- a/packages/typed_graphql_codegen/README.md
+++ b/packages/typed_graphql_codegen/README.md
@@ -7,8 +7,7 @@
 **Generate typed Dart client code from a GraphQL schema and `.graphql` operations, from the command line or in code, with every problem reported at its file, line and column.** It reads `typed_graphql.yaml`, loads the schema from a file or a URL, validates the documents and writes the library of the enums and input objects the operations use and, per document, the classes of its operations, variables, data and fragments, with the minified document, its SHA-256 and the persisted-operations manifest. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
 > **Status: under construction.** The client generator and its command line
-> work; the classes need `typed_graphql_client`, which holds only the contract
-> the generated code compiles against until M11. The SDL-first server
+> work; the classes need `typed_graphql_client`, which sends them. The SDL-first server
 > generator (M8) and the `build_runner` builder (M9) are not built yet (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
```

- [ ] **Step 4: Format, then run the green check.**

This task changes a `pubspec.yaml`: run `flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart pub get'` at the root before anything else.

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart doc --dry-run"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes, `dart doc` reports "Found 0 warnings and 0 errors" (621 client tests).

- [ ] **Step 5: Commit.**

```sh
git add -A CLAUDE.md README.md docs llms.txt packages test
git commit -m "docs: record stage M11 in the documents

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

## Review Focus

- The e2e tests run on the web: no `dart:io`, no port, no sleep.
- `PipelineTransport` is honest about what it stands in for: its status mapping and its 401 are test doubles with a comment saying so; the server is never changed.
- The event-stream writer is lazy and cancels the server's stream when the client cancels.
- Every document says only what works today: the cache, `watchQuery`, `@defer`/`@stream` and graphql-sse single connection mode are named as not built.
- The CI step's working directory and compiler matrix match the core's step.

## Verification

After the last task, run the format, analyze, root, client and `dart doc` checks with the Global Constraints wrapper (the commands are listed in M11a's Verification). Expected: 0 files changed, `No issues found!`, the root suite (381 tests) and the client suite (621 tests) pass, `dart doc` reports "Found 0 warnings and 0 errors". Then run the self-review of CLAUDE.md (`wc -l` of every file touched, the longest method).
