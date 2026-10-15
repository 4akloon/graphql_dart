import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'authorization_fixture.dart';

void main() {
  late RoleAuthorizer authorizer;
  late AuthorizationFixture fixture;

  setUp(() {
    authorizer = RoleAuthorizer();
    fixture = AuthorizationFixture(authorizer);
  });

  Map<String, Object?> firstError(Map<String, Object?> json) =>
      (json['errors']! as List<Object?>).first! as Map<String, Object?>;

  String codeOf(Map<String, Object?> error) =>
      (error['extensions']! as Map<String, Object?>)['code']! as String;

  group('decisions', () {
    test('an allow runs the field', () async {
      final json = await fixture.run('{ secret }', roles: {'admin'});
      expect(json, {
        'data': {'secret': 'secret'},
      });
    });

    test('a deny is a GQL352 field error with the default message', () async {
      final json = await fixture.run('{ secret open }');
      expect(json['data'], {'secret': null, 'open': 'open'});
      final error = firstError(json);
      expect(error['message'], 'Not authorized to access Query.secret.');
      expect(error['path'], ['secret']);
      expect(codeOf(error), 'GQL352');
    });

    test('a deny can carry its own message', () async {
      final slow = AuthorizationFixture(SlowAuthorizer());
      final json = await slow.run('{ secret }');
      expect(firstError(json)['message'], 'Slow no.');
    });

    test('an asynchronous decision allows or denies', () async {
      final slow = AuthorizationFixture(SlowAuthorizer());
      expect(await slow.run('{ secret }', roles: {'admin'}), {
        'data': {'secret': 'secret'},
      });
      expect(codeOf(firstError(await slow.run('{ secret }'))), 'GQL352');
    });

    test('a deny on a non-null field propagates to the data', () async {
      final json = await fixture.run('{ open vault }');
      expect(json['data'], isNull);
      expect(codeOf(firstError(json)), 'GQL352');
    });

    test('the authorizer sees requirements, arguments and parent', () async {
      await fixture.run(
        '{ greet(name: "Ada") }',
        roles: {'user', 'staff'},
      );
      final access = authorizer.accesses.single;
      expect(access.requirements, ['user', 'staff']);
      expect(access.info.fieldName, 'greet');
      expect(access.arguments.coerced, {'name': 'Ada'});
      expect(access.context.roles, {'user', 'staff'});
    });

    test('all requirements are passed on, a missing role denies', () async {
      final json = await fixture.run('{ greet(name: "x") }', roles: {'user'});
      expect(json['data'], {'greet': null});
      expect(codeOf(firstError(json)), 'GQL352');
    });

    test(
      'an invalid argument is reported before the authorizer runs',
      () async {
        await fixture.run('{ greet }', roles: {'user', 'staff'});
        expect(authorizer.calls, isEmpty);
      },
    );
  });

  group('lanes', () {
    test('a pure field is guarded', () async {
      await fixture.run('{ secret }');
      expect(authorizer.calls, ['Query.secret']);
    });

    test('a synchronous decision keeps a pure query synchronous', () {
      final result = fixture.built.execute(
        fixture.validDocument('{ secret }'),
        context: const Caller({'admin'}),
      );
      expect(result, isNot(isA<Future<Object?>>()));
    });

    test('an authorizer exception is masked and offered to onError', () async {
      final throwing = AuthorizationFixture(ThrowingAuthorizer());
      final seen = <Object>[];
      final json = await throwing.run(
        '{ secret }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            seen.add(error);
            return null;
          },
        ),
      );
      expect(firstError(json)['message'], 'Unexpected error.');
      expect(codeOf(firstError(json)), 'GQL330');
      expect(seen.single, isA<StateError>());
    });

    test('a guarded subscription is refused at the source', () async {
      final result = await fixture.built.subscribe(
        fixture.validDocument('subscription { tick }'),
        context: const Caller(),
      );
      expect(result, isA<SubscriptionRejected>());
      final allowed = await fixture.built.subscribe(
        fixture.validDocument('subscription { tick }'),
        context: const Caller({'admin'}),
      );
      expect(allowed, isA<SubscriptionStarted>());
    });
  });

  group('rules', () {
    test('a type rule guards the fields without one', () async {
      final json = await fixture.run('{ account { id } }');
      expect(authorizer.calls, ['Account.id']);
      expect(codeOf(firstError(json)), 'GQL352');
    });

    test('a field rule wins over the type rule', () async {
      final json = await fixture.run(
        '{ account { id motto vip } }',
        roles: {'owner'},
      );
      expect(authorizer.calls, ['Account.id', 'Account.vip']);
      expect(json['data'], {
        'account': {'id': 'a1', 'motto': 'free', 'vip': null},
      });
    });

    test('a public field does not call the authorizer', () async {
      final json = await fixture.run('{ shown }');
      expect(json['data'], {'shown': 'shown'});
      expect(authorizer.calls, isEmpty);
    });

    test('an unguarded field does not call the authorizer', () async {
      await fixture.run('{ open }');
      expect(authorizer.calls, isEmpty);
    });

    test('an inherited interface field keeps the interface rule', () async {
      final json = await fixture.run('{ memo { title } }');
      expect(codeOf(firstError(json)), 'GQL352');
      expect(authorizer.calls, ['Memo.title']);
    });

    test('a redeclared interface field does not take its rule', () async {
      final json = await fixture.run('{ note { title } }');
      expect(json['data'], {
        'note': {'title': 'redeclared'},
      });
      expect(authorizer.calls, isEmpty);
    });

    test('introspection is never guarded', () async {
      final json = await fixture.run(
        '{ __typename __schema { queryType { name } } __type(name: "Query") '
        '{ name } }',
      );
      expect(json['data'], {
        '__typename': 'Query',
        '__schema': {
          'queryType': {'name': 'Query'},
        },
        '__type': {'name': 'Query'},
      });
      expect(authorizer.calls, isEmpty);
    });

    test('SelectedField.authorization is the effective rule', () async {
      final b = ExecutableSchemaBuilder<Caller>();
      final item = b.object<Object?>(
        'Item',
        options: ObjectOptions(authorization: Authorization.requires(['x'])),
        fields: (t) => [
          t.field('a', b.string).pure((_) => 'a'),
          t
              .field('b', b.string)
              .withAuthorization(const Authorization.public())
              .pure((_) => 'b'),
        ],
      );
      final rules = <String, Authorization?>{};
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('item', item).resolve((p, a, c, info) {
            for (final field in info.selection.fields) {
              rules[field.name] = field.authorization;
            }
            return 1;
          }),
          t.field('plain', b.string).pure((_) => 'p'),
        ],
      );
      final built = b.build(
        query: query,
        options: BuildOptions<Caller>(authorizer: RoleAuthorizer()),
      );
      await built.execute(
        ValidDocument.assumeValid(
          built.schema,
          fixture.parse('{ item { a b } }'),
        ),
        context: const Caller({'x'}),
      );
      expect(rules['a'], isA<RequiredAuthorization>());
      expect(rules['b'], isA<PublicAuthorization>());
    });
  });

  group('coverage', () {
    test('lists the unguarded fields, introspection excluded, sorted', () {
      expect(AuthorizationCoverage(fixture.built).uncovered, [
        'Memo.size',
        'Note.size',
        'Note.title',
        'Query.account',
        'Query.memo',
        'Query.note',
        'Query.open',
      ]);
    });
  });

  group('GQL304', () {
    test('a guarded field and no authorizer is a build error', () {
      expect(
        () => AuthorizationFixture(null),
        throwsA(
          isA<SchemaBuildError>().having(
            (error) => error.diagnostics.single,
            'diagnostic',
            isA<Diagnostic>()
                .having((d) => d.code, 'code', DiagnosticCode.missingAuthorizer)
                .having(
                  (d) => d.message,
                  'message',
                  contains('Query.secret, Query.vault'),
                ),
          ),
        ),
      );
    });

    test('public rules alone need no authorizer', () {
      final b = ExecutableSchemaBuilder<Caller>();
      final query = b.object<Object?>(
        'Query',
        options: const ObjectOptions(
          authorization: Authorization.public(),
        ),
        fields: (t) => [t.field('a', b.string).pure((_) => 'a')],
      );
      expect(b.build(query: query).authorizer, isNull);
    });
  });
}
