import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('GraphQLException', () {
    test('is an Exception', () {
      expect(const GraphQLException('x'), isA<Exception>());
    });

    test('toString is the message', () {
      expect(const GraphQLException('Not allowed.').toString(), 'Not allowed.');
    });

    test('keeps its extensions', () {
      final exception = GraphQLException(
        'x',
        extensions: JsonObject({'code': const JsonString('E')}),
      );
      expect(exception.extensions, JsonObject({'code': const JsonString('E')}));
    });

    test('has no extensions by default', () {
      expect(const GraphQLException('x').extensions, isNull);
    });
  });
}
