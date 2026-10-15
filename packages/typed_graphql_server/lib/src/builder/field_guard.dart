import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../authorization/authorization_decision.dart';
import '../authorization/authorizer.dart';
import '../authorization/field_access.dart';
import '../execution/field_info.dart';
import '../execution/graphql_exception.dart';
import 'arguments.dart';

/// Wraps the functions of one guarded field so the authorizer decides
/// first (R4.19, spec 12).
final class FieldGuard<C> {
  /// Guards with [_authorizer] a field that needs [_requirements].
  FieldGuard(this._authorizer, this._requirements);

  final Authorizer<C> _authorizer;
  final List<String> _requirements;

  /// [call] preceded by the authorizer: a [Deny] throws, so the outcome is
  /// the field's error. A synchronous decision keeps the call synchronous.
  FutureOr<T> Function(
    Object? parent,
    Arguments arguments,
    Object? context,
    FieldInfo info,
  )
  guard<T>(
    FutureOr<T> Function(
      Object? parent,
      Arguments arguments,
      Object? context,
      FieldInfo info,
    )
    call,
  ) => (parent, arguments, context, info) {
    final decision = _authorizer.authorize(
      FieldAccess<C>(
        parent: parent,
        arguments: arguments,
        context: context as C,
        info: info,
        requirements: _requirements,
      ),
    );
    FutureOr<T> proceed(AuthorizationDecision settled) {
      _requireAllowed(settled, info);
      return call(parent, arguments, context, info);
    }

    return decision is Future<AuthorizationDecision>
        ? decision.then(proceed)
        : proceed(decision);
  };

  void _requireAllowed(AuthorizationDecision decision, FieldInfo info) {
    if (decision case Deny(:final message)) {
      throw GraphQLException(
        message ??
            'Not authorized to access ${info.parentTypeName}.'
                '${info.fieldName}.',
        extensions: JsonObject({
          'code': JsonString(DiagnosticCode.notAuthorized.id),
        }),
      );
    }
  }
}
