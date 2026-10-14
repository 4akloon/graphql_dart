import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'sdl.dart';

/// The result of building an SDL text, for a schema test.
final class Built {
  /// Builds [text] with [builder].
  Built(String text, {SchemaBuilder builder = const SchemaBuilder()})
    : this._(Sdl(text), builder);

  Built._(Sdl sdl, SchemaBuilder builder)
    : result = builder.fromSdl(sdl.document, source: sdl.source);

  /// What the builder returned.
  final BuildResult result;

  /// The schema; fails the test when the build failed.
  Schema get schema => switch (result) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// The partial schema; fails the test when the build succeeded.
  Schema get partial => switch (result) {
    BuildSuccess() => fail('expected build errors'),
    BuildFailure(:final partial) => partial,
  };

  /// Each diagnostic as `line:column id message`.
  List<String> get errors => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];

  /// The names of the declared types, in order.
  List<String> get typeNames => [
    for (final type in _built.types) type.name,
  ];

  Schema get _built => switch (result) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final partial) => partial,
  };
}
