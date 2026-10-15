import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _path = 'typed_graphql.yaml';
const _codec = '    codec: package:a/a.dart#C\n';

void main() {
  List<String> problems(String text) {
    final result = CodegenConfig.parse(text, path: _path);
    if (result is! ConfigFailure) fail('expected failure, got $result');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  String scalar(String body) => 'schema: s.graphql\nscalars:\n  Moment:\n$body';

  group('scalars', () {
    test('a scalar name must be a GraphQL name', () {
      expect(problems('schema: s.graphql\nscalars:\n  1Bad: {}\n'), [
        '$_path:3:3: error GQL501: A scalar name must be a GraphQL name.',
      ]);
    });

    test('a scalar must be a map', () {
      expect(problems('schema: s.graphql\nscalars:\n  Moment: x\n'), [
        "$_path:3:11: error GQL501: Scalar 'Moment' must be a map with "
            "'type' and 'codec'.",
      ]);
    });

    test('scalars must be a map', () {
      expect(problems('schema: s.graphql\nscalars: x\n'), [
        "$_path:2:10: error GQL501: 'scalars' must be a map of scalar names.",
      ]);
    });

    test('a missing codec is reported at the scalar', () {
      expect(problems(scalar('    type: Uri\n')), [
        "$_path:4:5: error GQL501: Scalar 'Moment' needs a 'codec'.",
      ]);
    });

    test('a missing type is reported at the scalar', () {
      expect(problems(scalar(_codec)), [
        "$_path:4:5: error GQL501: Scalar 'Moment' needs a 'type'.",
      ]);
    });

    test('an unknown scalar key', () {
      expect(problems(scalar('    type: Uri\n$_codec    extra: 1\n')), [
        "$_path:6:5: error GQL501: Scalar 'Moment' has the unknown key "
            "'extra'; the keys are 'codec' and 'type'.",
      ]);
    });

    test('a bare name outside dart:core needs a library', () {
      expect(problems(scalar('    type: Money\n$_codec')), [
        "$_path:4:11: error GQL501: 'type' names 'Money' without a "
            "library; write 'package:...#Money'.",
      ]);
    });

    test('a bare codec is rejected', () {
      expect(problems(scalar('    type: Uri\n    codec: UrlCodec\n')), [
        "$_path:5:12: error GQL501: 'codec' names 'UrlCodec' without a "
            "library; write 'package:...#UrlCodec'.",
      ]);
    });

    test('a codec in dart:core has no library', () {
      expect(problems(scalar('    type: Uri\n    codec: dart:core#Codec\n')), [
        "$_path:5:12: error GQL501: 'codec' must name a library.",
      ]);
    });

    test('a library that is not a package or dart: library', () {
      expect(problems(scalar('    type: x/y.dart#T\n$_codec')), [
        "$_path:4:11: error GQL501: 'type' must be '<library>#<Name>', "
            "such as 'package:my_app/codecs.dart#MyType'.",
      ]);
    });

    test('a private name', () {
      expect(
        problems(scalar('    type: Uri\n    codec: package:a/a.dart#_Codec\n')),
        [
          "$_path:5:12: error GQL501: 'codec' must be '<library>#<Name>', "
              "such as 'package:my_app/codecs.dart#MyType'.",
        ],
      );
    });

    test('a type that is not a string', () {
      expect(problems(scalar('    type: 5\n$_codec')), [
        "$_path:4:11: error GQL501: 'type' must be a string.",
      ]);
    });
  });

  group('several problems', () {
    test('are reported together in document order', () {
      expect(
        problems(
          'schema: /abs\n'
          'bogus: 1\n'
          'schema_types: x.txt\n'
          'documents: []\n',
        ),
        [
          "$_path:1:9: error GQL501: 'schema' must be a relative path.",
          "$_path:2:1: error GQL501: Unknown key 'bogus'; the keys are "
              "'documents', 'headers', 'persisted_operations', 'scalars', "
              "'schema', 'schema_types'.",
          "$_path:3:15: error GQL501: 'schema_types' must end with '.dart'.",
          "$_path:4:12: error GQL501: 'documents' must not be an empty list.",
        ],
      );
    });
  });
}
