import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_graphql_server/src/upload/memory_upload.dart';
import 'package:typed_graphql_server/src/upload/upload_registry.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  Upload upload(String name) => MemoryUpload(name, 'text/plain', Uint8List(0));

  group('UploadRegistry', () {
    test('a token is upload: and 32 lower-case hex digits', () {
      final token = UploadRegistry().register(upload('a'));
      expect(token, matches(RegExp(r'^upload:[0-9a-f]{32}$')));
    });

    test('two registrations get different tokens', () {
      final registry = UploadRegistry();
      expect(
        registry.register(upload('a')),
        isNot(registry.register(upload('a'))),
      );
    });

    test('lookup finds the registered upload', () {
      final registry = UploadRegistry();
      final file = upload('a');
      expect(registry.lookup(registry.register(file)), same(file));
    });

    test('lookup of an unknown token is null', () {
      expect(UploadRegistry().lookup('upload:nothing'), isNull);
    });

    test('remove forgets the tokens given and keeps the others', () {
      final registry = UploadRegistry();
      final gone = registry.register(upload('a'));
      final kept = registry.register(upload('b'));
      registry.remove([gone]);
      expect(registry.lookup(gone), isNull);
      expect(registry.lookup(kept), isNotNull);
      expect(registry.length, 1);
    });

    test('remove ignores a token that is not registered', () {
      final registry = UploadRegistry()..remove(['upload:nothing']);
      expect(registry.length, 0);
    });
  });
}
