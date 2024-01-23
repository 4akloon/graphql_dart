import 'field_definition.dart';
import 'type.dart';
import 'type_definition.dart';

abstract interface class ImplementingTypeDefinition<T extends TypeDefinition>
    implements TypeDefinition<T> {
  List<GType> get implementz;

  List<FieldDefinition> get fieldDefinitions;
}
