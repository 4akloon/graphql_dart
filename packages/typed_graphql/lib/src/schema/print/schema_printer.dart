import '../schema.dart';
import 'type_printer.dart';

/// Prints a schema as SDL, as graphql-js's `printSchema` does (spec §5;
/// R2.5): definitions separated by a blank line, in declaration order,
/// descriptions as block strings where they can be.
///
/// Unlike graphql-js, every applied directive is printed as written, so
/// SDL to schema to SDL loses nothing.
final class const SchemaPrinter() {
  /// Creates a printer.
  this;

  static const TypePrinter _types = TypePrinter();

  /// [schema] as SDL, without a trailing line break.
  String print(Schema schema) => schema.types.map(_types.type).join('\n\n');
}
