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

  // Serve it: the server parses and validates the document (cached),
  // applies the limits of its profile (production unless you pick one),
  // builds the context and executes. It knows nothing of HTTP.
  final server = GraphQLServer<Object?>(
    schema: schema,
    contextFactory: (request) => null,
  );
  final response = await server.handle(
    ServerRequest(
      params: const GraphQLRequest(
        query: '{ books(limit: 2) { title pages } }',
      ),
      info: RequestInfo(
        method: 'POST',
        uri: Uri.parse('http://localhost/graphql'),
        headers: {'content-type': 'application/json'},
      ),
    ),
  );

  // The response is a value: an outcome a transport maps to a status, and
  // a body that writes itself as JSON.
  if (response case SingleResponse(:final outcome, :final body)) {
    stdout.writeln(outcome.name);
    stdout.writeln(body);
  }
}
