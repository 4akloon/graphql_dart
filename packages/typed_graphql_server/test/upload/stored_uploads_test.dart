import 'package:test/test.dart';
import 'package:typed_graphql_server/src/upload/stored_uploads.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A bug in a storage, as opposed to a failure of its medium.
final class StorageBug extends Error {}

/// A storage whose release number [errorCall] throws [StorageBug] and whose
/// release number [exceptionCall] throws an [Exception].
final class FaultyStorage implements UploadStorage {
  FaultyStorage({this.errorCall = 0, this.exceptionCall = 0});

  final int errorCall;
  final int exceptionCall;
  int released = 0;

  @override
  Future<Upload> store(
    String filename,
    String mediaType,
    Stream<List<int>> content,
  ) => const MemoryUploadStorage().store(filename, mediaType, content);

  @override
  Future<void> release(Upload upload) async {
    released++;
    if (released == errorCall) throw StorageBug();
    if (released == exceptionCall) throw const FormatException('disk');
  }
}

void main() {
  Future<StoredUploads> filled(
    FaultyStorage storage,
    List<Object> reported,
  ) async {
    final stored = StoredUploads(
      Uploads(storage: storage),
      (error, stackTrace) => reported.add(error),
    );
    for (var i = 0; i < 3; i++) {
      stored.add(
        await storage.store('f', 'text/plain', Stream.value([i])),
      );
    }
    return stored;
  }

  test(
    'an Error in the first release still releases the rest, then goes up',
    () async {
      final storage = FaultyStorage(errorCall: 1);
      final reported = <Object>[];
      final stored = await filled(storage, reported);
      await expectLater(stored.release(), throwsA(isA<StorageBug>()));
      expect(storage.released, 3);
      expect(reported, isEmpty);
      expect(stored.length, 0);
    },
  );

  test('an Exception is reported and does not stop the others', () async {
    final storage = FaultyStorage(exceptionCall: 2);
    final reported = <Object>[];
    final stored = await filled(storage, reported);
    await stored.release();
    expect(storage.released, 3);
    expect(reported, [isA<FormatException>()]);
  });

  test('the first Error wins when two releases fail with one', () async {
    final storage = FaultyStorage(errorCall: 1, exceptionCall: 3);
    final reported = <Object>[];
    final stored = await filled(storage, reported);
    await expectLater(stored.release(), throwsA(isA<StorageBug>()));
    expect(reported, [isA<FormatException>()]);
  });
}
