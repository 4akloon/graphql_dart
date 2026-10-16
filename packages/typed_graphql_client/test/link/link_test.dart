import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// Adds its [name] to the `x-trail` header, then forwards.
final class TrailLink extends Link {
  const TrailLink(this.name);

  final String name;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    final headers =
        request.context.entry<RequestHeaders>() ?? RequestHeaders(const {});
    final trail = headers.values['x-trail'];
    return forward(
      request.withContext(
        request.context.withEntry(
          headers.withHeader('x-trail', trail == null ? name : '$trail,$name'),
        ),
      ),
    );
  }
}

/// Answers with the request's `x-trail` header as `data.trail`.
final class EchoLink extends Link {
  const EchoLink();

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    final trail = request.context.entry<RequestHeaders>()?.values['x-trail'];
    return Stream.value(
      LinkPayload(ExecutionResult(JsonObject({'trail': JsonString('$trail')}))),
    );
  }
}

void main() {
  final request = LinkRequest.of(const HelloQuery());

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  Future<String> trailOf(Stream<LinkResult> results) async =>
      switch (await results.single) {
        LinkPayload(payload: ExecutionResult(:final data?)) =>
          (data['trail']! as JsonString).value,
        final other => fail('unexpected $other'),
      };

  test('from runs the links in order', () async {
    final link = Link.from([
      const TrailLink('a'),
      const TrailLink('b'),
      const EchoLink(),
    ]);
    expect(await trailOf(link.request(request, unterminated)), 'a,b');
  });

  test('from of one link is that link', () {
    const link = EchoLink();
    expect(Link.from([link]), same(link));
  });

  test('from of no link is an ArgumentError', () {
    expect(() => Link.from([]), throwsArgumentError);
  });

  test('the last link of a chain forwards to the chain\'s forward', () async {
    final inner = Link.from([const TrailLink('a'), const TrailLink('b')]);
    final outer = Link.from([inner, const TrailLink('c'), const EchoLink()]);
    expect(await trailOf(outer.request(request, unterminated)), 'a,b,c');
  });

  test('a chain that ends with a middle link reaches forward', () {
    final link = Link.from([const TrailLink('a'), const TrailLink('b')]);
    expect(link.request(request, unterminated).first, throwsStateError);
  });
}
