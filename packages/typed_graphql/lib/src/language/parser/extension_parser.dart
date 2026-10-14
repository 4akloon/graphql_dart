import '../ast/node.dart';
import '../ast/type_system_extension.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'type_member_parser.dart';

/// Parses `extend` definitions of the schema and of types (spec §3.3.2,
/// §3.4.3): the parts of the matching definition, at least one present.
final class ExtensionParser {
  /// Creates a parser reading from [cursor].
  ExtensionParser(this.cursor, this.directives, this.members);

  /// The token stream.
  final TokenCursor cursor;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The shared members of types.
  final TypeMemberParser members;

  /// The extension that `extend` at the cursor starts; the keyword after
  /// it says which.
  TypeSystemExtension extension() {
    final keyword = cursor.lookahead();
    return switch ((keyword.kind, keyword.value)) {
      (.name, 'schema') => _schema(),
      (.name, 'scalar') => _scalar(),
      (.name, 'type') => _object(),
      (.name, 'interface') => _interface(),
      (.name, 'union') => _union(),
      (.name, 'enum') => _enum(),
      (.name, 'input') => _inputObject(),
      _ => cursor.unexpected(keyword),
    };
  }

  SchemaExtension _schema() {
    final start = _extend('schema');
    final directiveList = directives.directives(isConst: true);
    final operationTypes = cursor.optionalMany(
      .braceLeft,
      members.operationType,
      .braceRight,
    );
    _requireAny([directiveList, operationTypes]);
    return SchemaExtension(
      directives: directiveList,
      operationTypes: operationTypes,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ScalarTypeExtension _scalar() {
    final start = _extend('scalar');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    _requireAny([directiveList]);
    return ScalarTypeExtension(
      name,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  ObjectTypeExtension _object() {
    final start = _extend('type');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    _requireAny([interfaces, directiveList, fields]);
    return ObjectTypeExtension(
      name,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InterfaceTypeExtension _interface() {
    final start = _extend('interface');
    final name = cursor.name();
    final interfaces = members.interfaces();
    final directiveList = directives.directives(isConst: true);
    final fields = members.fields();
    _requireAny([interfaces, directiveList, fields]);
    return InterfaceTypeExtension(
      name,
      interfaces: interfaces,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  UnionTypeExtension _union() {
    final start = _extend('union');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final types = members.unionMembers();
    _requireAny([directiveList, types]);
    return UnionTypeExtension(
      name,
      directives: directiveList,
      types: types,
      start: start,
      end: cursor.lastEnd,
    );
  }

  EnumTypeExtension _enum() {
    final start = _extend('enum');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final values = members.enumValues();
    _requireAny([directiveList, values]);
    return EnumTypeExtension(
      name,
      directives: directiveList,
      values: values,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InputObjectTypeExtension _inputObject() {
    final start = _extend('input');
    final name = cursor.name();
    final directiveList = directives.directives(isConst: true);
    final fields = members.inputFields();
    _requireAny([directiveList, fields]);
    return InputObjectTypeExtension(
      name,
      directives: directiveList,
      fields: fields,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// Consumes `extend` and [keyword]; returns where the extension starts.
  int _extend(String keyword) {
    final start = cursor.token.start;
    cursor.expectKeyword('extend');
    cursor.expectKeyword(keyword);
    return start;
  }

  /// Fails at the current token when every part is absent: an extension
  /// that adds nothing is a syntax error, as in graphql-js.
  void _requireAny(List<List<Node>> parts) {
    if (parts.every((part) => part.isEmpty)) {
      cursor.unexpected();
    }
  }
}
