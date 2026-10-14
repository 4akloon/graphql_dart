import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'schema_port.dart';

/// graphql-js's `buildClientSchema` test helpers: `cycleIntrospection` and
/// introspection results as plain Dart objects a test edits before it
/// builds them, as graphql-js's tests edit the JSON.
final class IntrospectionPort {
  /// Creates the helpers; they keep no state.
  const IntrospectionPort();

  static const SchemaPort _schemas = SchemaPort();

  /// graphql-js's `cycleIntrospection`: [sdl] built, written as
  /// introspection, built back and printed; the client schema must write
  /// the same introspection as the server schema.
  String cycle(String sdl) {
    final initial = _schemas.build(sdl).toIntrospection();
    final client = this.client(initial);
    expect(client.toIntrospection(), initial);
    return _schemas.print(client);
  }

  /// graphql-js's `introspectionFromSchema` on `buildSchema(sdl)`, as plain
  /// maps and lists to edit.
  Map<String, Object?> introspectionOf(
    String sdl, [
    IntrospectionQuery query = IntrospectionQuery.full,
  ]) => _schemas.build(sdl).toIntrospection(query).toJson();

  /// The `__schema` object of [introspection].
  Map<String, Object?> schemaIn(Map<String, Object?> introspection) =>
      introspection['__schema']! as Map<String, Object?>;

  /// The entry of `__schema.types` in [introspection] named [name].
  Map<String, Object?> typeIn(
    Map<String, Object?> introspection,
    String name,
  ) => (schemaIn(introspection)['types']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((type) => type['name'] == name);

  /// [introspection] (a [JsonValue] or plain Dart objects) built.
  BuildResult buildResult(Object? introspection) =>
      const SchemaBuilder().fromIntrospection(switch (introspection) {
        final JsonValue value => value,
        _ => switch (const JsonReader().read(introspection)) {
          DecodeSuccess(:final value) => value,
          DecodeFailure() => fail('Not JSON: $introspection'),
        },
      });

  /// graphql-js's `buildClientSchema`: [introspection] built; fails the
  /// test on a diagnostic.
  Schema client(Object? introspection) => switch (buildResult(introspection)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// The diagnostics of building [introspection], each as its code id and
  /// message.
  List<String> errors(Object? introspection) => [
    for (final diagnostic in buildResult(introspection).diagnostics)
      '${diagnostic.code.id} ${diagnostic.message}',
  ];
}
