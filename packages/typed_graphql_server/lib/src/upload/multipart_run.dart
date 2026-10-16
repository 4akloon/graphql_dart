import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/request_decoding.dart';
import 'byte_limit.dart';
import 'byte_limit_exceeded.dart';
import 'content_disposition.dart';
import 'multipart_result.dart';
import 'stored_uploads.dart';
import 'upload_map.dart';
import 'upload_map_parser.dart';
import 'upload_map_result.dart';
import 'uploads.dart';
import 'watched_body.dart';

/// A refusal on its way out of [MultipartRun]: every step of the run is a
/// sequence of reads that can end the request, and this carries the reason
/// to the one place that answers it.
final class _Refused implements Exception {
  const _Refused(this.status, this.code, this.message);

  _Refused.malformed(String message)
    : this(400, DiagnosticCode.malformedMultipartRequest, message);

  final int status;
  final DiagnosticCode code;
  final String message;
}

/// One reading of the parts of a multipart request, in the order the
/// specification fixes: `operations`, `map`, then the files.
@internal
final class MultipartRun {
  /// Creates a run that stores files in [uploads], reads [watch]'s parts and
  /// parses JSON nested at most [maxJsonDepth] deep.
  MultipartRun(this._uploads, this._watch, this._maxJsonDepth)
    : stored = StoredUploads(_uploads);

  final Uploads _uploads;
  final WatchedBody _watch;
  final int _maxJsonDepth;

  /// The files stored so far, which the caller releases.
  final StoredUploads stored;

  /// Reads every part of [parts], never throwing for a request that is wrong;
  /// the failure of the body itself is thrown.
  Future<MultipartResult> consume(Stream<MimeMultipart> parts) async {
    final iterator = StreamIterator(parts);
    try {
      final operations = await _readJson(iterator, 'first', 'operations');
      final mapValue = await _readJson(iterator, 'second', 'map');
      final map = switch (UploadMapParser(
        _uploads.limits.maxFiles,
      ).parse(mapValue, operations)) {
        UploadMapValid(:final map) => map,
        UploadMapInvalid(:final refusal) => throw _Refused(
          refusal.status,
          refusal.code,
          refusal.message,
        ),
      };
      final tokens = await _readFiles(iterator, map);
      return MultipartContent(map.apply(operations, tokens), stored);
    } on _Refused catch (refused) {
      return MultipartRefusal(
        DecodingRefusal(refused.status, refused.code, refused.message),
      );
    } finally {
      await iterator.cancel();
    }
  }

  Future<JsonValue> _readJson(
    StreamIterator<MimeMultipart> iterator,
    String ordinal,
    String name,
  ) async {
    final mustBe = _Refused.malformed(
      'The $ordinal field of a multipart request must be $name.',
    );
    if (!await _watch.guard(iterator.moveNext())) throw mustBe;
    final part = iterator.current;
    if (_dispositionOf(part).name != name) throw mustBe;
    final maxBytes = _uploads.limits.maxFieldBytes;
    final limit = ByteLimit(maxBytes);
    final bytes = BytesBuilder(copy: false);
    try {
      await limit.bind(_watch.track(part)).forEach(bytes.add);
    } on ByteLimitExceeded catch (error) {
      if (!identical(error.origin, limit)) rethrow;
      throw _Refused(
        413,
        DiagnosticCode.uploadTooLarge,
        'The $name field is larger than $maxBytes bytes.',
      );
    }
    return _decodeJson(bytes.takeBytes(), name);
  }

  JsonValue _decodeJson(Uint8List bytes, String name) {
    final invalid = _Refused.malformed('The $name field is not valid JSON.');
    final String text;
    try {
      text = const Utf8Decoder().convert(bytes);
    } on FormatException {
      throw invalid;
    }
    return switch (JsonReader(maxDepth: _maxJsonDepth).parse(text)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure() => throw invalid,
    };
  }

  Future<Map<String, String>> _readFiles(
    StreamIterator<MimeMultipart> iterator,
    UploadMap map,
  ) async {
    final expected = {for (final entry in map.entries) entry.field};
    final tokens = <String, String>{};
    while (await _watch.guard(iterator.moveNext())) {
      final part = iterator.current;
      final disposition = _dispositionOf(part);
      if (!expected.contains(disposition.name) ||
          tokens.containsKey(disposition.name)) {
        throw _Refused.malformed(
          'The request contains a file the map does not name.',
        );
      }
      tokens[disposition.name] = await _store(part, disposition);
    }
    if (tokens.length != expected.length) {
      throw _Refused.malformed(
        'The map names a file the request does not contain.',
      );
    }
    return tokens;
  }

  Future<String> _store(
    MimeMultipart part,
    ContentDisposition disposition,
  ) async {
    final maxBytes = _uploads.limits.maxFileBytes;
    final limit = ByteLimit(maxBytes);
    try {
      final upload = await _uploads.storage.store(
        disposition.filename ?? '',
        part.headers['content-type'] ?? 'application/octet-stream',
        limit.bind(_watch.track(part)),
      );
      return stored.add(upload);
    } on ByteLimitExceeded catch (error) {
      if (!identical(error.origin, limit)) rethrow;
      throw _Refused(
        413,
        DiagnosticCode.uploadTooLarge,
        'A file is larger than $maxBytes bytes.',
      );
    }
  }

  ContentDisposition _dispositionOf(MimeMultipart part) =>
      ContentDisposition.parse(part.headers['content-disposition']) ??
      (throw _Refused.malformed(
        'A multipart field must have a content-disposition of form-data '
        'with a name.',
      ));
}
