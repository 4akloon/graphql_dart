import 'package:typed_graphql/typed_graphql.dart';

import 'dart_writer.dart';
import 'enum_emitter.dart';
import 'generated_header.dart';
import 'imports.dart';
import 'input_object_emitter.dart';
import 'type_mapper.dart';

/// Writes the schema-types library: the enums and input objects the
/// documents use (spec §7).
///
/// {@category codegen}
final class SchemaTypesEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const SchemaTypesEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  /// The text of the library for [types], generated from the file [source].
  ///
  /// [types] are written in the order given; with none, the library holds
  /// only its header and imports nothing.
  String emit(List<SchemaType> types, {required String source}) {
    final imports = Imports();
    final body = DartWriter();
    for (final (int index, SchemaType type) in types.indexed) {
      if (index > 0) body.line();
      switch (type) {
        case EnumType():
          const EnumEmitter().emit(type, body);
        case InputObjectType():
          InputObjectEmitter(mapper).emit(type, body, imports);
        case _:
          throw ArgumentError.value(type, 'types', 'is not an enum or input');
      }
    }
    if (types.isNotEmpty) {
      imports.package(
        'package:typed_graphql_client/typed_graphql_client.dart',
        prefix: 'client',
      );
    }
    if (types.any((type) => type is InputObjectType)) {
      imports.package(
        'package:typed_graphql/typed_graphql.dart',
        prefix: 'graphql',
      );
    }
    final head = DartWriter();
    const GeneratedHeader().write(head, source: source);
    imports.write(head);
    head.line();
    return types.isEmpty ? head.text : '${head.text}\n${body.text}';
  }
}
