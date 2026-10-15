import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/server/document_entry.dart';

import 'support/compiler_fixture.dart';

void main() {
  final compiler = const CompilerFixture().compiler;

  List<GraphQLError> errorsOf(String text) => switch (compiler.compile(
    text,
    'hash',
  )) {
    RejectedEntry(:final errors) => errors,
    AcceptedEntry() => throw StateError('expected a rejection'),
  };

  test('a valid text is accepted with its source', () {
    final entry = compiler.compile('{ a }', 'hash');
    expect(entry, isA<AcceptedEntry>());
    expect((entry as AcceptedEntry).source.body, '{ a }');
  });

  test('the entry keeps the hash it was given', () {
    expect(compiler.compile('{ a }', 'the-hash').hash, 'the-hash');
  });

  test('a syntax error becomes an error with its code and location', () {
    expect(errorsOf('{ a'), [
      GraphQLError(
        'Expected Name, found <EOF>.',
        locations: [const SourceLocation(1, 4)],
        extensions: JsonObject({'code': const JsonString('GQL007')}),
      ),
    ]);
  });

  test('a validation error becomes an error with its code and location', () {
    expect(errorsOf('{ b }'), [
      GraphQLError(
        'Cannot query field "b" on type "Query". Did you mean "a"?',
        locations: [const SourceLocation(1, 3)],
        extensions: JsonObject({'code': const JsonString('GQL205')}),
      ),
    ]);
  });
}
