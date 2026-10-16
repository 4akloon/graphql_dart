import 'package:test/test.dart';
import 'package:typed_graphql_server/src/http/accept_negotiation.dart';
import 'package:typed_graphql_server/src/http/response_media_type.dart';

void main() {
  const negotiation = AcceptNegotiation(ResponseMediaType.values);

  test('chooses graphql-response+json for */*', () {
    expect(
      negotiation.choose('*/*'),
      ResponseMediaType.graphqlResponseJson,
    );
  });

  test('chooses graphql-response+json for application/*', () {
    expect(
      negotiation.choose('application/*'),
      ResponseMediaType.graphqlResponseJson,
    );
  });

  test('chooses json when only application/json is accepted', () {
    expect(negotiation.choose('application/json'), ResponseMediaType.json);
  });

  test('chooses graphql-response+json for the spec recommended header', () {
    expect(
      negotiation.choose(
        'application/graphql-response+json, application/json;q=0.9',
      ),
      ResponseMediaType.graphqlResponseJson,
    );
  });

  test('chooses json when it has the higher quality', () {
    expect(
      negotiation.choose(
        'application/graphql-response+json;q=0.5, application/json',
      ),
      ResponseMediaType.json,
    );
  });

  test('excludes a type whose quality is 0', () {
    expect(
      negotiation.choose('application/graphql-response+json;q=0, */*'),
      ResponseMediaType.json,
    );
  });

  test('lets the most specific range decide', () {
    expect(
      negotiation.choose('application/*;q=0.1, application/json'),
      ResponseMediaType.json,
    );
  });

  test('lets a specific q=0 beat a wildcard that accepts', () {
    expect(
      negotiation.choose('*/*, application/json;q=0'),
      ResponseMediaType.graphqlResponseJson,
    );
  });

  test('gives null when only an unoffered type is accepted', () {
    expect(negotiation.choose('text/html'), isNull);
  });

  test('gives null when everything is excluded', () {
    expect(negotiation.choose('*/*;q=0'), isNull);
  });

  test('skips invalid ranges', () {
    expect(
      negotiation.choose('nonsense, application/json;q=7, application/json'),
      ResponseMediaType.json,
    );
  });

  test('gives null when every range is invalid', () {
    expect(negotiation.choose('nonsense, a/b;q=7'), isNull);
  });

  test('treats a missing header as application/json', () {
    expect(negotiation.choose(null), ResponseMediaType.json);
  });

  test('treats a blank header as application/json', () {
    expect(negotiation.choose('  '), ResponseMediaType.json);
  });

  test('gives null for a missing header when json is not offered', () {
    const only = AcceptNegotiation([ResponseMediaType.graphqlResponseJson]);
    expect(only.choose(null), isNull);
  });

  test('breaks a tie in favour of the earlier offered type', () {
    expect(
      negotiation.choose('application/json, application/graphql-response+json'),
      ResponseMediaType.graphqlResponseJson,
    );
  });

  test('answers quickly for ten thousand ranges', () {
    final header = List.filled(10000, 'text/html;q=0.1').join(',');
    expect(negotiation.choose('$header,application/json'), isNotNull);
  });

  test('chooses the event stream when only it is accepted', () {
    expect(
      negotiation.choose('text/event-stream'),
      ResponseMediaType.eventStream,
    );
  });

  test('chooses the event stream when it has the higher quality', () {
    expect(
      negotiation.choose('application/json;q=0.5, text/event-stream'),
      ResponseMediaType.eventStream,
    );
  });

  test('offers the event stream last, so a wildcard does not pick it', () {
    expect(
      negotiation.choose('text/*'),
      ResponseMediaType.eventStream,
    );
    expect(negotiation.choose('*/*'), ResponseMediaType.graphqlResponseJson);
  });

  test('words the offered types for a message', () {
    expect(
      negotiation.description,
      'application/graphql-response+json, application/json and '
      'text/event-stream',
    );
    expect(
      const AcceptNegotiation([
        ResponseMediaType.graphqlResponseJson,
        ResponseMediaType.json,
      ]).description,
      'application/graphql-response+json and application/json',
    );
  });
}
