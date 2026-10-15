import '../language/ast/argument.dart';
import '../language/ast/directive.dart';
import '../language/ast/executable_definition.dart';
import '../language/ast/name.dart';
import '../language/ast/node.dart';
import '../language/ast/object_field.dart';
import '../language/ast/selection.dart';
import '../language/ast/selection_set.dart';
import '../language/ast/type_ref.dart';
import '../language/ast/value.dart';
import '../language/ast/variable_definition.dart';
import '../schema/model/input_value.dart';
import '../schema/model/schema_directive.dart';
import '../schema/model/schema_enum_value.dart';
import '../schema/model/schema_field.dart';
import '../schema/model/schema_type.dart';
import '../schema/relations/type_comparator.dart';
import '../schema/schema.dart';
import 'meta_fields.dart';

/// The types around the node a walk is at (R3.2), graphql-js's
/// `TypeInfo`: [enter] and [leave] keep stacks of the output types, the
/// parent types, the field definitions, the input types and the default
/// values, and the current directive, argument and enum value.
///
/// `DocumentValidator` updates one for each run before the rules enter a
/// node and after they leave it, and rules read it through
/// `ValidationContext.typeInfo`. Each getter is null where the document
/// names something the schema does not have.
///
/// {@category validation}
final class TypeInfo {
  /// Creates the state of a walk over documents for [schema].
  TypeInfo(this.schema);

  /// The schema whose types are looked up.
  final Schema schema;

  static const TypeComparator _types = TypeComparator();

  final List<TypeRef?> _outputTypes = [];
  final List<SchemaType?> _parentTypes = [];
  final List<TypeRef?> _inputTypes = [];
  final List<SchemaField?> _fieldDefinitions = [];
  final List<Value?> _defaultValues = [];
  SchemaDirective? _directive;
  InputValue? _argument;
  SchemaEnumValue? _enumValue;

  /// The output type of the current field, fragment or operation.
  TypeRef? get type => _outputTypes.lastOrNull;

  /// The composite type whose selection set holds the current node.
  SchemaType? get parentType => _parentTypes.lastOrNull;

  /// The definition of the current field, meta-fields included.
  SchemaField? get fieldDefinition => _fieldDefinitions.lastOrNull;

  /// The input type of the current value: of a variable definition, an
  /// argument, a list item or an input object field.
  TypeRef? get inputType => _inputTypes.lastOrNull;

  /// The input type that holds [inputType]: the list or input object
  /// around the current value.
  TypeRef? get parentInputType =>
      _inputTypes.length < 2 ? null : _inputTypes[_inputTypes.length - 2];

  /// The default value of the current argument or input field; null in a
  /// list and where there is none.
  Value? get defaultValue => _defaultValues.lastOrNull;

  /// The definition of the current directive.
  SchemaDirective? get directive => _directive;

  /// The definition of the current argument, of a field or a directive.
  InputValue? get argument => _argument;

  /// The definition of the current enum value.
  SchemaEnumValue? get enumValue => _enumValue;

  /// Moves into [node], before a visitor enters it.
  void enter(Node node) {
    switch (node) {
      case SelectionSet():
        _parentTypes.add(switch (_namedOf(type)) {
          final named? when named.isCompositeType => named,
          _ => null,
        });
      case Field(:final name):
        _enterField(name.value);
      case Directive(:final name):
        _directive = schema.directiveNamed(name.value);
      case OperationDefinition(:final operation):
        _outputTypes.add(_root(schema.rootTypeName(operation)));
      case InlineFragment(:final typeCondition):
        _outputTypes.add(_outputOrNull(typeCondition ?? _namedTypeOf(type)));
      case FragmentDefinition(:final typeCondition):
        _outputTypes.add(_outputOrNull(typeCondition));
      case VariableDefinition(type: final declared):
        _inputTypes.add(schema.isInputType(declared) ? declared : null);
      case Argument(:final name):
        _enterArgument(name.value);
      case ListValue():
        _enterListValue();
      case ObjectField(:final name):
        _enterObjectField(name.value);
      case EnumValue(:final value):
        _enumValue = switch (_namedOf(inputType)) {
          final EnumType type => type.valueNamed(value),
          _ => null,
        };
      case _:
        break;
    }
  }

  /// Moves out of [node], after a visitor leaves it.
  void leave(Node node) {
    switch (node) {
      case SelectionSet():
        _parentTypes.removeLast();
      case Field():
        _fieldDefinitions.removeLast();
        _outputTypes.removeLast();
      case Directive():
        _directive = null;
      case OperationDefinition() || InlineFragment() || FragmentDefinition():
        _outputTypes.removeLast();
      case VariableDefinition():
        _inputTypes.removeLast();
      case Argument():
        _argument = null;
        _defaultValues.removeLast();
        _inputTypes.removeLast();
      case ListValue() || ObjectField():
        _defaultValues.removeLast();
        _inputTypes.removeLast();
      case EnumValue():
        _enumValue = null;
      case _:
        break;
    }
  }

  void _enterField(String name) {
    final definition = switch (parentType) {
      final parent? => MetaFields.fieldOf(schema, parent, name),
      null => null,
    };
    _fieldDefinitions.add(definition);
    _outputTypes.add(_outputOrNull(definition?.type));
  }

  void _enterArgument(String name) {
    final argument = switch (directive) {
      final directive? => directive.argumentNamed(name),
      null => fieldDefinition?.argumentNamed(name),
    };
    _argument = argument;
    _defaultValues.add(argument?.defaultValue);
    _inputTypes.add(_inputOrNull(argument?.type));
  }

  void _enterListValue() {
    final listType = switch (inputType) {
      NonNullType(type: final inner) => inner,
      final other => other,
    };
    // A list position never has a default value.
    _defaultValues.add(null);
    _inputTypes.add(
      _inputOrNull(switch (listType) {
        ListType(type: final item) => item,
        _ => null,
      }),
    );
  }

  void _enterObjectField(String name) {
    final field = switch (_namedOf(inputType)) {
      final InputObjectType object => object.fieldNamed(name),
      _ => null,
    };
    _defaultValues.add(field?.defaultValue);
    _inputTypes.add(_inputOrNull(field?.type));
  }

  TypeRef? _root(String? name) => switch (name) {
    final name? when schema.typeNamed(name) is ObjectType => NamedType(
      Name(name),
    ),
    _ => null,
  };

  TypeRef? _outputOrNull(TypeRef? type) =>
      type != null && schema.isOutputType(type) ? type : null;

  TypeRef? _inputOrNull(TypeRef? type) =>
      type != null && schema.isInputType(type) ? type : null;

  NamedType? _namedTypeOf(TypeRef? type) =>
      type == null ? null : _types.namedType(type);

  SchemaType? _namedOf(TypeRef? type) => switch (_namedTypeOf(type)) {
    final named? => schema.typeNamed(named.name.value),
    null => null,
  };
}
