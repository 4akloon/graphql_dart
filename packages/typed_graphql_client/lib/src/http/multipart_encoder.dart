import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../upload/upload_file.dart';
import '../upload/upload_files.dart';

/// Writes a request with files as the `multipart/form-data` body of the
/// GraphQL multipart request specification (spec section 9, R8.4): an
/// `operations` part with each file's marker replaced by null, a `map`
/// part from part names to variable paths, then one part per file.
@internal
final class MultipartEncoder(
  /// Draws the boundary.
  final Random random,
) {
  /// Creates an encoder.
  this;

  static const String _boundaryCharacters =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  static const List<int> _lineEnd = [13, 10];

  /// The body of [request] with [files]: its content type, length and
  /// bytes. A marker [files] does not list, or a listed file no variable
  /// holds, is an [ArgumentError].
  ({String contentType, int length, Stream<List<int>> body}) encode(
    GraphQLRequest request,
    UploadFiles files,
  ) {
    final operations = request.toJson().toJson();
    final paths = _MarkerWalk(files).run(operations);
    final boundary = String.fromCharCodes([
      for (var i = 0; i < 32; i++)
        _boundaryCharacters.codeUnitAt(
          random.nextInt(_boundaryCharacters.length),
        ),
    ]);
    final fields = utf8.encode(
      '${_fieldPart(boundary, 'operations', jsonEncode(operations))}'
      '${_fieldPart(boundary, 'map', jsonEncode(_map(files, paths)))}',
    );
    final heads = [
      for (final (index, file) in files.files.indexed)
        utf8.encode(_fileHead(boundary, index, file)),
    ];
    final closing = utf8.encode('--$boundary--\r\n');
    var length = fields.length + closing.length;
    for (final (index, file) in files.files.indexed) {
      length += heads[index].length + file.length + _lineEnd.length;
    }
    return (
      contentType: 'multipart/form-data; boundary=$boundary',
      length: length,
      body: _body(fields, heads, files.files, closing),
    );
  }

  Map<String, List<String>> _map(
    UploadFiles files,
    Map<UploadFile, List<String>> paths,
  ) => {
    for (final (index, file) in files.files.indexed)
      '$index': paths[file] ?? const [],
  };

  String _fieldPart(String boundary, String name, String json) =>
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="$name"\r\n'
      'Content-Type: application/json\r\n'
      '\r\n'
      '$json\r\n';

  String _fileHead(String boundary, int index, UploadFile file) =>
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="$index"; '
      'filename="${file.filename}"\r\n'
      'Content-Type: ${file.contentType}\r\n'
      '\r\n';

  Stream<List<int>> _body(
    List<int> fields,
    List<List<int>> heads,
    List<UploadFile> files,
    List<int> closing,
  ) async* {
    yield fields;
    for (final (index, file) in files.indexed) {
      yield heads[index];
      yield* file.open();
      yield _lineEnd;
    }
    yield closing;
  }
}

/// One walk over the variables of a request, breadth first with a queue
/// (no recursion), that replaces each file marker by null and records
/// where it was.
final class _MarkerWalk {
  _MarkerWalk(this.files);

  final UploadFiles files;
  final Map<UploadFile, List<String>> _paths = {};
  final ListQueue<(Object?, String)> _pending = ListQueue();

  /// The paths of each file in [operations], which it changes in place.
  Map<UploadFile, List<String>> run(Map<String, Object?> operations) {
    _pending.add((operations['variables'], 'variables'));
    while (_pending.isNotEmpty) {
      final (value, path) = _pending.removeFirst();
      switch (value) {
        case Map<String, Object?>():
          for (final key in value.keys.toList()) {
            value[key] = _visit(value[key], '$path.$key');
          }
        case List<Object?>():
          for (var i = 0; i < value.length; i++) {
            value[i] = _visit(value[i], '$path.$i');
          }
      }
    }
    for (final file in files.files) {
      if (!_paths.containsKey(file)) {
        throw ArgumentError.value(
          file,
          'files',
          'No variable holds this file: list only the files the variables use',
        );
      }
    }
    return _paths;
  }

  Object? _visit(Object? value, String path) {
    if (value is String && value.startsWith(UploadFile.markerPrefix)) {
      final file = files.withMarker(value);
      if (file == null) {
        throw ArgumentError.value(
          value,
          path,
          'The variables hold a file the context does not list: add it to '
          'the UploadFiles entry',
        );
      }
      (_paths[file] ??= []).add(path);
      return null;
    }
    _pending.add((value, path));
    return value;
  }
}
