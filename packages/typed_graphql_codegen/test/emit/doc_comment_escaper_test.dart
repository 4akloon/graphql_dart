import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/doc_comment_escaper.dart';

void main() {
  const escaper = DocCommentEscaper();

  const cases = <String, String>{
    'Returns a List<User>.': 'Returns a List`<User>`.',
    'Map<String, List<User>> nested': 'Map`<String, List<User>>` nested',
    '<b>bold</b>': '`<b>`bold`</b>`',
    'Already `List<User>` quoted': 'Already `List<User>` quoted',
    'a < b and c': 'a < b and c',
    r'Plain [x] with $5 and */': r'Plain [x] with $5 and */',
    'Unclosed <User': 'Unclosed <User',
  };

  for (final MapEntry(key: input, value: expected) in cases.entries) {
    test('escape of $input', () => expect(escaper.escape(input), expected));
  }
}
