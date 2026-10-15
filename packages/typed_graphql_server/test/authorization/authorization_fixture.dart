import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The request's context: the roles of the caller.
final class Caller {
  const Caller([this.roles = const {}]);

  final Set<String> roles;
}

/// Allows a field when the caller has every required role; records the
/// coordinate of each access it is asked about.
class RoleAuthorizer implements Authorizer<Caller> {
  final List<String> calls = [];
  final List<FieldAccess<Caller>> accesses = [];

  @override
  FutureOr<AuthorizationDecision> authorize(FieldAccess<Caller> access) {
    calls.add('${access.info.parentTypeName}.${access.info.fieldName}');
    accesses.add(access);
    return decide(access);
  }

  FutureOr<AuthorizationDecision> decide(FieldAccess<Caller> access) =>
      access.requirements.every(access.context.roles.contains)
      ? const Allow()
      : const Deny();
}

/// Decides after a delay, with a message.
final class SlowAuthorizer extends RoleAuthorizer {
  @override
  FutureOr<AuthorizationDecision> decide(FieldAccess<Caller> access) async {
    await Future<void>.delayed(Duration.zero);
    return access.requirements.every(access.context.roles.contains)
        ? const Allow()
        : const Deny(message: 'Slow no.');
  }
}

/// Throws on every access.
final class ThrowingAuthorizer extends RoleAuthorizer {
  @override
  FutureOr<AuthorizationDecision> decide(FieldAccess<Caller> access) =>
      throw StateError('policy store down');
}

sealed class Entity {
  const Entity();
}

final class Memo extends Entity {
  const Memo();
}

final class Note extends Entity {
  const Note();
}

/// The schema of the authorization tests; the authorizer is a parameter.
final class AuthorizationFixture {
  AuthorizationFixture(this.authorizer) {
    built = _build(authorizer);
  }

  final Authorizer<Caller>? authorizer;
  late final ExecutableSchema<Caller> built;

  /// The builder with the types; `build` is the caller's.
  static ExecutableSchema<Caller> _build(Authorizer<Caller>? authorizer) {
    final b = ExecutableSchemaBuilder<Caller>();
    final name = Arg('name', b.string);
    final account = b.object<Object?>(
      'Account',
      options: ObjectOptions(authorization: Authorization.requires(['owner'])),
      fields: (t) => [
        t.field('id', b.string).pure((_) => 'a1'),
        t
            .field('motto', b.string)
            .withAuthorization(const Authorization.public())
            .pure((_) => 'free'),
        t
            .field('vip', b.string.nullable)
            .withAuthorization(Authorization.requires(['vip']))
            .pure((_) => 'gold'),
      ],
    );
    final entity = b.interface<Entity>(
      'Entity',
      fields: (t) => [
        t
            .field('title', b.string)
            .withAuthorization(Authorization.requires(['reader']))
            .pure((_) => 'inherited'),
      ],
    );
    final memo = b.object<Memo>(
      'Memo',
      interfaces: [entity],
      fields: (t) => [t.field('size', b.int).pure((_) => 1)],
    );
    final note = b.object<Note>(
      'Note',
      interfaces: [entity],
      fields: (t) => [
        t.field('title', b.string).pure((_) => 'redeclared'),
        t.field('size', b.int).pure((_) => 2),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('open', b.string).pure((_) => 'open'),
        t
            .field('secret', b.string.nullable)
            .withAuthorization(Authorization.requires(['admin']))
            .pure((_) => 'secret'),
        t
            .field('vault', b.string)
            .withAuthorization(Authorization.requires(['admin']))
            .pure((_) => 'vault'),
        t
            .field('shown', b.string)
            .withAuthorization(const Authorization.public())
            .pure((_) => 'shown'),
        t
            .field('greet', b.string.nullable, args: [name])
            .withAuthorization(Authorization.requires(['user', 'staff']))
            .resolve(
              (parent, args, context, info) async => 'hi ${args.get(name)}',
            ),
        t.field('account', account.nullable).resolve((p, a, c, i) => 1),
        t.field('memo', memo).pure((_) => const Memo()),
        t.field('note', note).pure((_) => const Note()),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('tick', b.int)
            .withAuthorization(Authorization.requires(['admin']))
            .subscribe((p, a, c, i) => Stream.fromIterable([1, 2, 3])),
      ],
    );
    return b.build(
      query: query,
      subscription: subscription,
      options: BuildOptions<Caller>(authorizer: authorizer),
    );
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  ValidDocument validDocument(String text) =>
      ValidDocument.assumeValid(built.schema, parse(text));

  /// The response to [text] as JSON, for a caller with [roles].
  Future<Map<String, Object?>> run(
    String text, {
    Set<String> roles = const {},
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final payload = await built.execute(
      validDocument(text),
      context: Caller(roles),
      options: options,
    );
    return payload.toJson().toJson();
  }
}
