import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  // Every syntax error in one pass, each with a stable code and a place.
  final broken = Source('query { a(x: ) }', name: 'bad.graphql');
  if (parser.parse(broken) case ParseFailure(:final diagnostics)) {
    diagnostics.forEach(stdout.writeln);
  }

  // A document prints back the way graphql-js prints it.
  final query = Source('query Hero{hero{name}}', name: 'hero.graphql');
  if (parser.parse(query) case ParseSuccess(:final document)) {
    stdout.writeln(const Printer().print(document));
  }

  // SDL builds a schema; a problem in it is a diagnostic, not an exception.
  final sdl = Source('type Query { hero: String }', name: 'schema.graphql');
  final result = const SchemaBuilder().fromSdl(
    parser.parse(sdl).requireDocument(),
    source: sdl,
  );
  switch (result) {
    case BuildSuccess(:final schema):
      stdout.writeln('query root: ${schema.queryTypeName}');
      // A request is checked against a valid schema by the spec's rules.
      final request = Source('{ heroes }', name: 'request.graphql');
      if (const SchemaValidator().validate(schema)
          case final ValidSchema valid) {
        final checked = const DocumentValidator().validate(
          valid,
          parser.parse(request).requireDocument(),
          source: request,
        );
        if (checked case InvalidDocument(:final diagnostics)) {
          diagnostics.forEach(stdout.writeln);
        }
      }
    case BuildFailure(:final diagnostics):
      diagnostics.forEach(stdout.writeln);
  }
}
