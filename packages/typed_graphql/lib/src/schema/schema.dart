import '../diagnostics/source_span.dart';
import '../language/ast/operation_type.dart';
import 'build/built_ins.dart';
import 'model/applied_directive.dart';
import 'model/schema_directive.dart';
import 'model/schema_type.dart';

/// A GraphQL schema (spec §3.3; R2.1): its named types, its directive
/// definitions and its root operation types, immutable.
///
/// It holds what was declared, in declaration order; the built-in scalars,
/// directives and introspection types of [BuiltIns] exist in every schema
/// and are found by [typeNamed] and [directiveNamed] without being listed.
/// Building does not validate: a reference may name a type that does not
/// exist, and a root may name a type of the wrong kind.
///
/// {@category schema}
final class Schema({
  List<SchemaType> types = const [],
  List<SchemaDirective> directives = const [],

  /// The name of the query root type; null when there is none.
  final String? queryTypeName,

  /// The name of the mutation root type; null when there is none.
  final String? mutationTypeName,

  /// The name of the subscription root type; null when there is none.
  final String? subscriptionTypeName,

  /// The description of the schema definition, if any.
  final String? description,
  List<AppliedDirective> appliedDirectives = const [],

  /// Whether `@defer` and `@stream` exist in this schema (an opt-in, as
  /// graphql-js defines them; R2.6).
  final bool includesDeferAndStream = false,

  /// Where the schema definition was; null without one.
  final SourceSpan? span,
}) {
  /// Creates a schema.
  this;

  /// The declared named types, in declaration order; built-ins are not
  /// listed.
  final List<SchemaType> types = List.unmodifiable(types);

  /// The declared directive definitions, in declaration order; built-ins
  /// are not listed.
  final List<SchemaDirective> directives = List.unmodifiable(directives);

  /// The directives applied to the schema definition and its extensions.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  // Only for lookups, never iterated. Built from the end, so the first of
  // two types with one name wins, as the builder keeps the first.
  final Map<String, SchemaType> _typesByName = {
    for (final type in types.reversed) type.name: type,
  };

  // Same rule as _typesByName: the first declared directive wins.
  final Map<String, SchemaDirective> _directivesByName = {
    for (final directive in directives.reversed) directive.name: directive,
  };

  /// The declared type named [name], else the built-in scalar or
  /// introspection type; null when there is none.
  SchemaType? typeNamed(String name) {
    if (_typesByName[name] case final type?) {
      return type;
    }
    return const BuiltIns().typeNamed(name);
  }

  /// The declared directive named [name], else the built-in one; null
  /// when there is none.
  SchemaDirective? directiveNamed(String name) {
    if (_directivesByName[name] case final directive?) {
      return directive;
    }
    const builtIns = BuiltIns();
    return switch (name) {
      'defer' when includesDeferAndStream => builtIns.defer,
      'stream' when includesDeferAndStream => builtIns.stream,
      _ => builtIns.directiveNamed(name),
    };
  }

  /// The name of the root type of [operation]; null when there is none.
  String? rootTypeName(OperationType operation) => switch (operation) {
    .query => queryTypeName,
    .mutation => mutationTypeName,
    .subscription => subscriptionTypeName,
  };
}
