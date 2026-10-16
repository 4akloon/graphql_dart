import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import 'support/counting_storage.dart';
import 'support/multipart_body.dart';
import 'support/upload_http_fixture.dart';

/// What a disk storage throws when the disk is full.
final class DiskFull implements Exception {
  const DiskFull();
}

void main() {
  MultipartBody request() => MultipartBody()
      .field(
        'operations',
        jsonEncode({
          'query': r'mutation ($f: [Upload!]!) { uploadMany(files: $f) }',
          'variables': {
            'f': [null, null],
          },
        }),
      )
      .field('map', '{"0":["variables.f.0"],"1":["variables.f.1"]}')
      .file('0', utf8.encode('a'))
      .file('1', utf8.encode('b'));

  Future<void> expectServerFault(Exception failure) async {
    final errors = <Object>[];
    final fixture = UploadHttpFixture(
      storage: CountingStorage(storeFailure: failure, failingCall: 2),
    );
    final response = await fixture
        .handler(
          onError: (error, stackTrace, reported) {
            errors.add(error);
            return null;
          },
        )
        .handle(fixture.post(request()));
    expect((response.status, await fixture.code(response)), (500, 'GQL330'));
    expect(errors.length, 1, reason: 'the hook saw the failure once');
    expect(errors.single.toString(), contains(failure.runtimeType.toString()));
    expect(fixture.storage.released, 1, reason: 'the first file is released');
    expect(fixture.storage.held, isEmpty);
    expect(fixture.uploads.registry.length, 0);
  }

  group('a storage that fails', () {
    test('is a server fault, not a bad request', () {
      return expectServerFault(const DiskFull());
    });

    test('with a TimeoutException is a server fault, not a 408', () {
      return expectServerFault(TimeoutException('disk'));
    });

    test('with a FormatException is a server fault, not a 400', () {
      return expectServerFault(const FormatException('disk'));
    });
  });

  test('a failing release is reported and the others still run', () async {
    final errors = <Object>[];
    final fixture = UploadHttpFixture(releaseThrows: true);
    final response = await fixture
        .handler(
          onError: (error, stackTrace, reported) {
            errors.add(error);
            return null;
          },
        )
        .handle(fixture.post(request()));
    expect(response.status, 200);
    expect(fixture.storage.released, 2);
    expect(errors, hasLength(2));
    expect(errors, everyElement(isA<ReleaseFailed>()));
  });
}
