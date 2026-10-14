import '../ast/name.dart';
import '../ast/type_system_definition.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'type_member_parser.dart';
import 'value_parser.dart';

/// Parses schema, type and directive definitions (spec §3).
final class TypeSystemParser {
  /// Creates a parser reading from [cursor].
  TypeSystemParser(this.cursor, this.values, this.directives, this.members);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The shared members of types.
  final TypeMemberParser members;

  /// The keywords that start a type-system definition.
  static const Set<String> keywords = {
    'schema',
    'scalar',
    'type',
    'interface',
    'union',
    'enum',
    'input',
    'directive',
  };

  /// The September2025 directive locations (spec §3.13).
  static const Set<String> locations = {
    'QUERY',
    'MUTATION',
    'SUBSCRIPTION',
    'FIELD',
    'FRAGMENT_DEFINITION',
    'FRAGMENT_SPREAD',
    'INLINE_FRAGMENT',
    'VARIABLE_DEFINITION',
    'SCHEMA',
    'SCALAR',
    'OBJECT',
    'FIELD_DEFINITION',
    'ARGUMENT_DEFINITION',
    'INTERFACE',
    'UNION',
    'ENUM',
    'ENUM_VALUE',
    'INPUT_OBJECT',
    'INPUT_FIELD_DEFINITION',
  };

  /// The definition that [keyword], one of [keywords], starts, after an
  /// optional description.
  TypeSystemDefinition definition(String keyword) => switch (keyword) {
    'schema' => _schema(),
    'scalar' => _scalar(),
    'type' => _object(),
    'interface' => _interface(),
    'union' => _union(),
    'enum' => _enum(),
    'input' => _inputObject(),
    'directive' => _directive(),
    _ => throw ArgumentError.value(keyword, 'keyword', 'not in keywords'),
  };

  SchemaDefinition _schema() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('schema');
    final directiveList = directives.directives(isConst: true);
    final operationTypes = cursor.many(
      .braceLeft,
      members.operationType,
      .braceRight,
    );
    return SchemaDefinition(
      description: description,
      directives: directiveList,
      operationTypes: operationTypes,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ScalarTypeDefinition _scalar() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('scalar');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    return ScalarTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ObjectTypeDefinition _object() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('type');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    return ObjectTypeDefinition(
      name,
      description: description,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InterfaceTypeDefinition _interface() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('interface');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    return InterfaceTypeDefinition(
      name,
      description: description,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  UnionTypeDefinition _union() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('union');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final types = members.unionMembers();
    return UnionTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      types: types,
      start: start,
      end: cursor.lastEnd,
    );
  }

  EnumTypeDefinition _enum() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('enum');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final enumValues = members.enumValues();
    return EnumTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      values: enumValues,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InputObjectTypeDefinition _inputObject() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('input');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final fields = members.inputFields();
    return InputObjectTypeDefinition(
      name,
      description: description,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  DirectiveDefinition _directive() {
    final start = cursor.token.start;
    final description = values.description();
    cursor.expectKeyword('directive');
    cursor.expect(.at);
    final name = cursor.name();
    final arguments = members.arguments();
    final isRepeatable = cursor.expectOptionalKeyword('repeatable');
    cursor.expectKeyword('on');
    final locations = cursor.delimitedMany(.pipe, _location);
    return DirectiveDefinition(
      name,
      description: description,
      arguments: arguments,
      isRepeatable: isRepeatable,
      locations: locations,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// `DirectiveLocation`: one of [locations].
  Name _location() {
    final token = cursor.token;
    final name = cursor.name();
    if (!locations.contains(name.value)) {
      cursor.unexpected(token);
    }
    return name;
  }
}
