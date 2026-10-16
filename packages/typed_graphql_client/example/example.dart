// Runs a query and a subscription through a GraphQLClient whose link is a
// MockLink, so no network is needed. The operations are written by hand here;
// typed_graphql_codegen generates them from .graphql documents. Output goes
// through the zone, which keeps the program free of dart:io.
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class HelloQuery extends GraphQLQuery<String> {
  const HelloQuery();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Hello',
    type: OperationType.query,
    text: 'query Hello{hello}',
    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<String> decodeData(JsonObject data) => switch (data['hello']) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected a string', path: [PathKey('hello')]),
  };
}

final class TicksSubscription extends GraphQLSubscription<int> {
  const TicksSubscription();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Ticks',
    type: OperationType.subscription,
    text: 'subscription Ticks{ticks}',
    sha256: '14c970476cf383579b21ff6dbb8326a9f2e3ea340def21bcb5bf9cf9b1af1f38',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<int> decodeData(JsonObject data) => switch (data['ticks']) {
    JsonNumber(:final asInt?) => DecodeSuccess(asInt),
    _ => const DecodeFailure('expected an integer', path: [PathKey('ticks')]),
  };
}

Future<void> main() async {
  Stream<LinkResult> ticks() async* {
    for (var tick = 1; tick <= 3; tick++) {
      yield LinkPayload(
        ExecutionResult(JsonObject({'ticks': JsonNumber(tick)})),
      );
    }
  }

  final link = MockLink()
    ..addData(JsonObject({'hello': const JsonString('world')}))
    ..addStream(ticks());
  final client = GraphQLClient(link: link);

  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
    Zone.current.print('hello: $data');
  }
  await for (final response in client.subscribe(const TicksSubscription())) {
    if (response case GraphQLData(:final data)) {
      Zone.current.print('tick: $data');
    }
  }
}
