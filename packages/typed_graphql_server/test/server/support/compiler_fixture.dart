import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/server/document_compiler.dart';
import 'package:typed_graphql_server/src/server/document_result.dart';

/// A small valid schema and compilers over it.
final class CompilerFixture {
  const CompilerFixture();

  ValidSchema get schema {
    final source = Source('type Query { a: Int }');
    final document = const Parser().parse(source).requireDocument();
    final built = const SchemaBuilder().fromSdl(document, source: source);
    return switch (built) {
      BuildSuccess(:final schema) =>
        const SchemaValidator().validate(schema) as ValidSchema,
      BuildFailure() => throw StateError('the fixture schema must build'),
    };
  }

  DocumentCompiler get compiler =>
      DocumentCompiler(const Parser(), const DocumentValidator(), schema);

  /// A compiler that counts its calls.
  CountingCompiler get countingCompiler => CountingCompiler(compiler);
}

final class CountingCompiler extends DocumentCompiler {
  CountingCompiler(DocumentCompiler inner)
    : super(inner.parser, inner.validator, inner.schema);

  int calls = 0;

  @override
  DocumentResult compile(String text, String hash) {
    calls++;
    return super.compile(text, hash);
  }
}
