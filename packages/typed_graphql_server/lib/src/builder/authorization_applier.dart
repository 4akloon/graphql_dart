import 'package:typed_graphql/typed_graphql.dart';

import '../authorization/authorization.dart';
import '../authorization/authorizer.dart';
import '../execution/schema_bindings.dart';
import 'field_def.dart';
import 'field_guard.dart';
import 'field_lane.dart';
import 'schema_build_error.dart';

/// Gives every object field its effective rule and guards the fields that
/// need the authorizer (R4.19, spec 12). Run after the middleware is
/// composed, so the check sits outside the chain, and before introspection
/// is added, which is never guarded.
///
/// The effective rule of an object's field is the rule on its definition
/// there (its own, or the interface field it inherits whole), else the
/// object type's. A field an object redeclares does not take the
/// interface's rule: an interface rule guards the implementations that
/// inherit the field.
final class AuthorizationApplier<C> {
  /// Applies the rules, checking with [_authorizer]; null when the build
  /// has none.
  AuthorizationApplier(this._authorizer);

  final Authorizer<C>? _authorizer;

  /// [bindings] with the rules applied; throws [SchemaBuildError] (`GQL304`)
  /// when a field is guarded and there is no authorizer.
  SchemaBindings apply(SchemaBindings bindings) {
    final unguardable = <String>[];
    final fields = {
      for (final MapEntry(key: typeName, value: own) in bindings.fields.entries)
        typeName: {
          for (final MapEntry(key: name, value: field) in own.entries)
            name: _applyTo(
              typeName,
              field,
              bindings.objects[typeName]?.options.authorization,
              unguardable,
            ),
        },
    };
    if (unguardable.isNotEmpty) {
      unguardable.sort();
      throw SchemaBuildError([
        Diagnostic(
          .missingAuthorizer,
          .error,
          'Fields are guarded by an authorization rule but the build has no '
          'authorizer (BuildOptions.authorizer): ${unguardable.join(', ')}.',
        ),
      ]);
    }
    return bindings.withFields(fields);
  }

  FieldDef<Object?, Object?> _applyTo(
    String typeName,
    FieldDef<Object?, Object?> field,
    Authorization? typeRule,
    List<String> unguardable,
  ) {
    final rule = field.authorization ?? typeRule;
    if (rule is! RequiredAuthorization) {
      return rule == null ? field : field.withLane(field.lane, rule);
    }
    final authorizer = _authorizer;
    if (authorizer == null) {
      unguardable.add('$typeName.${field.name}');
      return field;
    }
    final guard = FieldGuard<C>(authorizer, rule.requirements);
    return field.withLane(switch (field.lane) {
      PureLane(:final read) => ResolverLane(
        guard.guard<Object?>((parent, arguments, context, info) {
          return read(parent);
        }),
      ),
      ResolverLane(:final resolve) => ResolverLane(guard.guard(resolve)),
      SubscribeLane(:final source, :final resolve) => SubscribeLane(
        guard.guard(source),
        guard.guard(resolve),
      ),
      final DeclaredOnlyLane lane => lane,
    }, rule);
  }
}
