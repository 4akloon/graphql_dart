import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class Tag extends ContextEntry {
  const Tag(this.name);

  final String name;
}

final class OtherTag extends Tag {
  const OtherTag(super.name);
}

void main() {
  group('LinkContext', () {
    test('an empty context has no entry', () {
      expect(const LinkContext.empty().entry<Tag>(), isNull);
    });

    test('entry gives the last entry of the type', () {
      final context = LinkContext([const Tag('a'), const Tag('b')]);
      expect(context.entry<Tag>()?.name, 'b');
    });

    test(
      'entry does not find a subtype, as withEntry does not replace one',
      () {
        final context = LinkContext([const OtherTag('a')]);
        expect(context.entry<Tag>(), isNull);
        expect(context.entry<OtherTag>()?.name, 'a');
      },
    );

    test('withEntry replaces the entries of the same exact type', () {
      final context = LinkContext([
        const Tag('a'),
        const OtherTag('b'),
      ]).withEntry(const Tag('c'));
      expect(
        [
          for (final entry in context.entries) (entry as Tag).name,
        ],
        ['b', 'c'],
      );
    });

    test('withEntry leaves the original unchanged', () {
      final original = LinkContext([const Tag('a')]);
      original.withEntry(const Tag('b'));
      expect(original.entry<Tag>()?.name, 'a');
    });

    test('the entries cannot be modified', () {
      final context = LinkContext([const Tag('a')]);
      expect(() => context.entries.add(const Tag('b')), throwsUnsupportedError);
    });
  });

  group('RequestHeaders', () {
    test('lower-cases the names', () {
      expect(RequestHeaders({'X-Trace': '1'}).values, {'x-trace': '1'});
    });

    test('withHeader replaces a value whatever its case', () {
      final headers = RequestHeaders({
        'Authorization': 'a',
      }).withHeader('AUTHORIZATION', 'b');
      expect(headers.values, {'authorization': 'b'});
    });
  });

  test('HttpResponseInfo copies its headers', () {
    final headers = {'etag': '1'};
    final info = HttpResponseInfo(200, headers: headers);
    headers['etag'] = '2';
    expect(info.headers, {'etag': '1'});
  });
}
