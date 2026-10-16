import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  group('UploadFile', () {
    test('fromBytes copies the bytes and knows their length', () async {
      final bytes = [1, 2, 3];
      final file = UploadFile.fromBytes(bytes, filename: 'a.bin');
      bytes[0] = 9;
      expect(file.length, 3);
      expect(await file.open().expand((chunk) => chunk).toList(), [1, 2, 3]);
    });

    test('fromBytes can be opened again', () async {
      final file = UploadFile.fromBytes([1], filename: 'a.bin');
      await file.open().drain<void>();
      expect(await file.open().expand((chunk) => chunk).toList(), [1]);
    });

    test('fromStream opens a new stream each time', () async {
      var opened = 0;
      final file = UploadFile.fromStream(
        () {
          opened++;
          return Stream.value([7]);
        },
        length: 1,
        filename: 'a.bin',
      );
      await file.open().drain<void>();
      await file.open().drain<void>();
      expect(opened, 2);
    });

    test('has the default content type', () {
      expect(
        UploadFile.fromBytes(const [], filename: 'a').contentType,
        'application/octet-stream',
      );
    });

    test('each file has its own marker', () {
      final a = UploadFile.fromBytes(const [], filename: 'a');
      final b = UploadFile.fromBytes(const [], filename: 'a');
      expect(a.marker, isNot(b.marker));
      expect(a.marker, startsWith(UploadFile.markerPrefix));
    });
  });

  group('UploadFileCodec', () {
    test('writes a file as its marker', () {
      final file = UploadFile.fromBytes(const [], filename: 'a');
      expect(const UploadFileCodec().encode(file), JsonString(file.marker));
    });

    test('never reads a file', () {
      expect(
        const UploadFileCodec().decode(const JsonString('x')),
        isA<DecodeFailure>(),
      );
    });
  });

  group('UploadFiles', () {
    test('finds a file by its marker', () {
      final a = UploadFile.fromBytes(const [], filename: 'a');
      final b = UploadFile.fromBytes(const [], filename: 'b');
      final files = UploadFiles([a, b]);
      expect(files.withMarker(b.marker), same(b));
      expect(files.withMarker('other'), isNull);
    });

    test('is a context entry', () {
      final context = LinkContext([UploadFiles(const [])]);
      expect(context.entry<UploadFiles>(), isNotNull);
    });
  });
}
