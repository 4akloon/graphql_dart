import 'package:meta/meta.dart';

import 'upload.dart';
import 'uploads.dart';

/// The files one request has stored: what the registry and the storage hold
/// for it, and the means to let both go.
@internal
final class StoredUploads {
  /// Creates an empty set of files kept in the registry and storage of
  /// [uploads].
  StoredUploads(this._uploads);

  final Uploads _uploads;
  final List<(String, Upload)> _entries = [];

  /// Registers [upload] and returns the token that stands for it in the
  /// request's variables.
  String add(Upload upload) {
    final token = _uploads.registry.register(upload);
    _entries.add((token, upload));
    return token;
  }

  /// The tokens of the files, in the order they were stored.
  List<String> get tokens => [for (final (token, _) in _entries) token];

  /// The number of files stored.
  int get length => _entries.length;

  /// Forgets every token and releases every file, whatever a release does.
  Future<void> release() async {
    final entries = [..._entries];
    _entries.clear();
    _uploads.registry.remove([for (final (token, _) in entries) token]);
    for (final (_, upload) in entries) {
      try {
        await _uploads.storage.release(upload);
      } on Object {
        // A storage that fails to release must not change the response that
        // is already decided, and the other files still need their release.
      }
    }
  }
}
