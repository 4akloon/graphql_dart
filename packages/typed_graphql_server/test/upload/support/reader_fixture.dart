import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/request_decoding.dart';
import 'package:typed_graphql_server/src/upload/multipart_reader.dart';
import 'package:typed_graphql_server/src/upload/multipart_result.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'counting_storage.dart';
import 'multipart_body.dart';

/// A [MultipartReader] over a counting storage, with small limits, and the
/// helpers the reader tests share.
final class ReaderFixture {
  ReaderFixture({
    bool releaseThrows = false,
    UploadLimits limits = const UploadLimits(
      maxFiles: 3,
      maxFileBytes: 20,
      maxRequestBytes: 2000,
      maxFieldBytes: 200,
    ),
  }) : storage = CountingStorage(
         releaseThrows: releaseThrows,
       ) {
    uploads = Uploads(storage: storage, limits: limits);
  }

  /// An `operations` value with one upload variable.
  static const String operations =
      r'{"query":"mutation ($f: Upload!) { upload(file: $f) }",'
      '"variables":{"f":null}}';

  /// An `operations` value with a list of two upload variables.
  static const String listOperations =
      '{"query":"q","variables":{"files":[null,null]}}';

  final CountingStorage storage;

  /// The release failures the reader reported.
  final List<Object> releaseErrors = [];

  // `late`: assigned in the constructor body, which needs `storage` first.
  late final Uploads uploads;

  /// A request with one file at `variables.f`.
  MultipartBody valid() => MultipartBody()
      .field('operations', operations)
      .field('map', '{"0":["variables.f"]}')
      .file('0', utf8.encode('hello'));

  Future<MultipartResult> read(
    Stream<List<int>> body, {
    Duration timeout = const Duration(seconds: 5),
    int maxJsonDepth = 64,
    CancelSignal? cancelSignal,
    String boundary = 'testBoundary',
  }) => MultipartReader(
    uploads,
    maxJsonDepth: maxJsonDepth,
    bodyTimeout: timeout,
    onReleaseError: (error, stackTrace) => releaseErrors.add(error),
  ).read(body, boundary, cancelSignal: cancelSignal);

  Future<MultipartResult> readBody(MultipartBody body, {int? chunkSize}) =>
      read(body.stream(chunkSize: chunkSize));

  Future<DecodingRefusal> refusalOf(Future<MultipartResult> result) async =>
      switch (await result) {
        MultipartRefusal(:final refusal) => refusal,
        MultipartContent() => throw StateError('expected a refusal'),
      };

  Future<MultipartContent> contentOf(Future<MultipartResult> result) async =>
      switch (await result) {
        MultipartContent() && final content => content,
        MultipartRefusal(:final refusal) => throw StateError(refusal.message),
      };

  void expectRefusal(
    DecodingRefusal actual,
    int status,
    DiagnosticCode code,
    String message,
  ) {
    expect(actual.status, status);
    expect(actual.code, code);
    expect(actual.message, message);
  }

  /// Expects that no file is held by the storage or the registry.
  void expectNothingKept() {
    expect(storage.held, isEmpty);
    expect(uploads.registry.length, 0);
  }
}
