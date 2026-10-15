import 'package:typed_graphql/typed_graphql.dart';

import 'directive_nodes.dart';
import 'field_def.dart';
import 'input_value_assembler.dart';

/// Turns a [FieldDef] into a core [SchemaField].
final class FieldAssembler {
  /// Creates the assembler; argument defaults go through [_inputs].
  FieldAssembler(this._inputs);

  final InputValueAssembler _inputs;

  /// The schema field for [field] of the type named [typeName].
  SchemaField assemble(FieldDef<Object?, Object?> field, String typeName) =>
      SchemaField(
        field.name,
        field.type.typeRef,
        description: field.description,
        arguments: [
          for (final arg in field.args)
            _inputs.assemble(arg, '$typeName.${field.name}(${arg.name}:)'),
        ],
        appliedDirectives: const DirectiveNodes().withDeprecation(
          field.directives,
          field.deprecationReason,
        ),
      );
}
