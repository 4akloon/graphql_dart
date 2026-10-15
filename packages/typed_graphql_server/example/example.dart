import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Book {
  const Book(this.title, this.pages);

  final String title;
  final int? pages;
}

Future<void> main() async {
  // Declare the schema in typed Dart: a wrong result type does not compile.
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<Book>(
    'Book',
    fields: (t) => [
      t.field('title', b.string).pure((book) => book.title),
      t.field('pages', b.int.nullable).pure((book) => book.pages),
    ],
  );
  final limit = Arg('limit', b.int, defaultValue: 10);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('books', b.list(book), args: [limit])
          .resolve(
            (parent, args, context, info) =>
                const [Book('Dune', 412), Book('Emma', null)].take(
                  args.get(limit),
                ),
          ),
    ],
  );
  final schema = b.build(query: query);

  // Parse and validate a request against the schema: a problem is a
  // diagnostic, never an exception.
  final source = Source('{ books(limit: 2) { title pages } }');
  final document = const Parser().parse(source).requireDocument();
  final checked = const DocumentValidator().validate(
    schema.schema,
    document,
    source: source,
  );
  if (checked case final ValidDocument valid) {
    // Execute it: the response is a value that writes itself as JSON.
    final response = await schema.execute(
      valid,
      context: null,
      options: ExecutionOptions(source: source),
    );
    stdout.writeln(response.toJson());
  }
}
