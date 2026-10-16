import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  test('every failure kind has its code', () {
    final failures = <ClientFailure, DiagnosticCode>{
      const NetworkFailure(FormatException('x')): DiagnosticCode.networkFailure,
      HttpStatusFailure(502): DiagnosticCode.httpErrorStatus,
      ResponseFormatFailure(DiagnosticCode.responseTooLarge, 'too long'):
          DiagnosticCode.responseTooLarge,
      DataFormatFailure(const DecodeFailure('expected a string')):
          DiagnosticCode.dataShapeMismatch,
      const RequestCancelled(): DiagnosticCode.requestCancelled,
      const RequestTimedOut(Duration(seconds: 1)):
          DiagnosticCode.requestTimedOut,
      const UnsupportedOperation(
        DiagnosticCode.linkEndedWithoutResult,
        'no result',
      ): DiagnosticCode.linkEndedWithoutResult,
      const SocketFailure(DiagnosticCode.socketClosed, 'closed'):
          DiagnosticCode.socketClosed,
      const EventStreamFailure('unknown event'):
          DiagnosticCode.malformedEventStream,
      const AuthenticationFailure(FormatException('x')):
          DiagnosticCode.authenticationFailed,
    };
    for (final MapEntry(key: failure, value: code) in failures.entries) {
      expect(failure.code, code, reason: '$failure');
    }
  });

  test('toString is the id and the message', () {
    expect(
      HttpStatusFailure(503).toString(),
      'GQL461: The server answered with HTTP status 503.',
    );
  });

  test('a network failure names its cause', () {
    expect(
      const NetworkFailure(FormatException('reset')).message,
      'The request failed: FormatException: reset',
    );
  });

  test('a cancelled request names its reason when it has one', () {
    expect(const RequestCancelled().message, 'The request was cancelled.');
    expect(
      const RequestCancelled('left').message,
      'The request was cancelled: left',
    );
  });

  test('a data format failure prints the path of the decode failure', () {
    final failure = DataFormatFailure(
      const DecodeFailure('expected a string', path: [PathKey('name')]),
    );
    expect(
      failure.message,
      r'The data does not fit the operation: $.name: expected a string',
    );
  });

  test('the lists and maps a failure holds cannot be modified', () {
    final status = HttpStatusFailure(500, headers: {'a': 'b'});
    final format = ResponseFormatFailure(
      DiagnosticCode.malformedResponse,
      'bad',
      path: [const PathKey('data')],
    );
    final data = DataFormatFailure(
      const DecodeFailure('bad'),
      errors: [GraphQLError('boom')],
    );
    expect(() => status.headers['c'] = 'd', throwsUnsupportedError);
    expect(() => format.path.add(const PathIndex(0)), throwsUnsupportedError);
    expect(data.errors.clear, throwsUnsupportedError);
  });
}
