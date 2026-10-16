import 'dart:math';

import 'package:meta/meta.dart';

import 'upload.dart';

/// The uploads of the requests being served, by the token that stands for
/// each in the request's variables.
///
/// The scalar codec has no request context, so a token is the only way a
/// value reaches the right file. A token is 128 random bits: a client cannot
/// guess another request's.
@internal
final class UploadRegistry {
  /// Creates an empty registry.
  UploadRegistry() : _random = Random.secure();

  final Random _random;
  final Map<String, Upload> _uploads = {};

  /// Registers [upload] and returns its new token.
  String register(Upload upload) {
    var token = _newToken();
    while (_uploads.containsKey(token)) {
      token = _newToken();
    }
    _uploads[token] = upload;
    return token;
  }

  /// The upload registered under [token], or null.
  Upload? lookup(String token) => _uploads[token];

  /// Forgets the uploads registered under [tokens].
  void remove(Iterable<String> tokens) {
    for (final token in tokens) {
      _uploads.remove(token);
    }
  }

  /// The number of uploads registered.
  int get length => _uploads.length;

  String _newToken() {
    final digits = StringBuffer('upload:');
    for (var index = 0; index < 16; index++) {
      digits.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return digits.toString();
  }
}
