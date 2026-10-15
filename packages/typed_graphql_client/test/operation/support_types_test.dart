import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class _Ping extends GraphQLQuery<String> {
  const _Ping();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Ping',
    type: OperationType.query,
    text: 'query Ping{ping}',
    sha256: 'abc',
  );

  @override
  JsonObject get variablesJson => JsonObject({'id': const JsonString('1')});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const ScalarDataCodec(StringCodec()).decode(data['ping']!);
}

void main() {
  group('DataContext.flag', () {
    test('is the value that was sent', () {
      final context = DataContext(JsonObject({'on': const JsonBool(true)}));
      expect(context.flag('on'), isTrue);
    });

    test('is the default when the variable was not sent', () {
      final context = DataContext(JsonObject(const {}), const {'on': true});
      expect(context.flag('on'), isTrue);
    });

    test('is false when there is no value and no default', () {
      expect(DataContext(JsonObject(const {})).flag('on'), isFalse);
    });

    test('is the default when the value is not a Boolean', () {
      final context = DataContext(
        JsonObject({'on': const JsonString('yes')}),
        const {'on': true},
      );
      expect(context.flag('on'), isTrue);
    });

    test('is the default when there are no variables', () {
      expect(const DataContext(null, {'on': true}).flag('on'), isTrue);
    });
  });

  group('DataEquality', () {
    const equality = DataEquality();
    final a = [
      [1, 2],
      [3],
    ];
    final b = [
      [1, 2],
      [3],
    ];
    final first = [1];
    final second = [1];

    test('compares nested lists item by item', () {
      expect(equality.equals(a, b), isTrue);
    });

    test('tells nested lists with different items apart', () {
      expect(
        equality.equals(a, [
          [1, 2],
          [4],
        ]),
        isFalse,
      );
    });

    test('hashes equal nested lists alike', () {
      expect(equality.hash(a), equality.hash(b));
    });

    test('compares present optionals of equal lists as equal', () {
      expect(
        equality.equals(Optional.present(first), Optional.present(second)),
        isTrue,
      );
    });

    test('hashes equal present optionals alike', () {
      expect(
        equality.hash(Optional.present(first)),
        equality.hash(Optional.present(second)),
      );
    });

    test('tells present from absent', () {
      expect(
        equality.equals(
          const Optional<List<int>>.absent(),
          Optional.present(first),
        ),
        isFalse,
      );
    });

    test('compares absent with absent', () {
      expect(
        equality.equals(
          const Optional<int>.absent(),
          const Optional<int>.absent(),
        ),
        isTrue,
      );
    });

    test('hashes absent optionals alike', () {
      expect(
        equality.hash(const Optional<int>.absent()),
        equality.hash(const Optional<int>.absent()),
      );
    });
  });

  group('DataFormatException', () {
    test('inside prepends a segment to the path', () {
      final exception = const DataFormatException('bad', [
        PathIndex(1),
      ]).inside(const PathKey('items'));
      expect(exception.path, [const PathKey('items'), const PathIndex(1)]);
    });

    test('inside keeps the message', () {
      expect(
        const DataFormatException('bad').inside(const PathIndex(0)).message,
        'bad',
      );
    });
  });

  group('GraphQLOperation', () {
    final request = const _Ping().toRequest();

    test('toRequest sends the document text', () {
      expect(request.query, 'query Ping{ping}');
    });

    test('toRequest sends the operation name', () {
      expect(request.operationName, 'Ping');
    });

    test('toRequest sends the variables', () {
      expect(request.variables, JsonObject({'id': const JsonString('1')}));
    });

    test('is exhaustive over its three kinds', () {
      const GraphQLOperation<Object> operation = _Ping();
      final kind = switch (operation) {
        GraphQLQuery() => 'query',
        GraphQLMutation() => 'mutation',
        GraphQLSubscription() => 'subscription',
      };
      expect(kind, 'query');
    });
  });
}
