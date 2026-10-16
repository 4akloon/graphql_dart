import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/transport_errors.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';

void main() {
  const errors = TransportErrors(false);

  String text(HttpResponseData response) =>
      utf8.decode((response.body as FixedBody).bytes);

  group('refusal', () {
    test('writes one error with the code in its extensions', () {
      final response = errors.refusal(
        415,
        DiagnosticCode.unsupportedMediaType,
        'Wrong type.',
      );
      expect(response.status, 415);
      expect(
        text(response),
        '{"errors":[{"message":"Wrong type.",'
        '"extensions":{"code":"GQL421"}}]}',
      );
    });

    test('is application/json, never graphql-response+json', () {
      final response = errors.refusal(
        400,
        DiagnosticCode.malformedRequestBody,
        'Bad.',
      );
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
    });

    test('adds the headers it is given', () {
      final response = errors.refusal(
        405,
        DiagnosticCode.unsupportedHttpMethod,
        'No.',
        headers: {'Allow': 'GET, POST'},
      );
      expect(response.headers['allow'], 'GET, POST');
    });
  });

  group('unexpected', () {
    test('is a 500 with GQL330 and the message of the error', () {
      final response = errors.unexpected(StateError('boom'));
      expect(response.status, 500);
      expect(text(response), contains('"code":"GQL330"'));
      expect(text(response), contains('Bad state: boom'));
    });

    test('hides the message when errors are masked', () {
      final response = const TransportErrors(
        true,
      ).unexpected(StateError('boom'));
      expect(text(response), isNot(contains('boom')));
      expect(text(response), contains('Unexpected error.'));
    });

    test('masks an error whose toString throws', () {
      final response = errors.unexpected(const UnprintableError());
      expect(response.status, 500);
      expect(text(response), contains('Unexpected error.'));
    });

    test('is application/json', () {
      expect(
        errors.unexpected(StateError('x')).headers['content-type'],
        'application/json; charset=utf-8',
      );
    });
  });
}
