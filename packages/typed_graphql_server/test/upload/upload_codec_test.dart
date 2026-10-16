import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/upload/memory_upload.dart';
import 'package:typed_graphql_server/src/upload/upload_codec.dart';
import 'package:typed_graphql_server/src/upload/upload_registry.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final registry = UploadRegistry();
  final file = MemoryUpload('a.txt', 'text/plain', Uint8List(0));
  final token = registry.register(file);
  final codec = UploadCodec(registry);

  group('UploadCodec', () {
    test('decodes a registered token to its upload', () {
      expect(codec.decode(JsonString(token)), DecodeSuccess<Upload>(file));
    });

    test('refuses a string that is not a registered token', () {
      final result = codec.decode(const JsonString('upload:unknown'));
      expect(
        result,
        const DecodeFailure('Upload value is not a file of this request.'),
      );
    });

    test('refuses a value that is not a string', () {
      expect(codec.decode(JsonNumber(1)), isA<DecodeFailure>());
    });

    test('refuses null', () {
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('encoding is an ArgumentError', () {
      expect(
        () => codec.encode(file),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Upload is an input-only scalar.',
          ),
        ),
      );
    });

    test('Uploads.codec reads the registry of its Uploads', () {
      final uploads = Uploads();
      final own = uploads.registry.register(file);
      expect(
        uploads.codec.decode(JsonString(own)),
        isA<DecodeSuccess<Upload>>(),
      );
    });
  });
}
