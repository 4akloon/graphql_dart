import '../ast/directive.dart';
import '../ast/name.dart';
import '../ast/type_system_definition.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'type_member_parser.dart';
import 'value_parser.dart';

/// Parses schema, type and directive definitions (spec §3).
final class TypeSystemParser {
  /// Creates a parser reading from [cursor].
  TypeSystemParser(
    this.cursor,
    this.values,
    this.directives,
    this.members, {
    required this.allowsDirectiveExtensions,
  });

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// The shared members of types.
  final TypeMemberParser members;

  /// Whether a directive definition may carry directives and name the
  /// `DIRECTIVE_DEFINITION` location (working draft).
  final bool allowsDirectiveExtensions;

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

  /// The working draft's location for directives on a directive
  /// definition.
  static const String directiveDefinitionLocation = 'DIRECTIVE_DEFINITION';

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
    final directiveList = _directivesOfDirective();
    final isRepeatable = cursor.expectOptionalKeyword('repeatable');
    cursor.expectKeyword('on');
    final locations = cursor.delimitedMany(.pipe, _location);
    return DirectiveDefinition(
      name,
      description: description,
      arguments: arguments,
      directives: directiveList,
      isRepeatable: isRepeatable,
      locations: locations,
      start: start,
      end: cursor.lastEnd,
    );
  }

  /// The working draft's `Directives[Const]?` of a directive definition.
  List<Directive> _directivesOfDirective() {
    if (cursor.peek(.at) && !allowsDirectiveExtensions) {
      cursor.fail(
        .workingDraftFeatureDisabled,
        'Directives on a directive definition are a working-draft feature; '
        'enable them with ParserOptions.allowDirectiveExtensions.',
      );
    }
    return directives.directives(isConst: true);
  }

  /// `DirectiveLocation`: one of [locations], or the working draft's
  /// [directiveDefinitionLocation].
  Name _location() {
    final token = cursor.token;
    final name = cursor.name();
    if (name.value == directiveDefinitionLocation) {
      if (!allowsDirectiveExtensions) {
        cursor.fail(
          .workingDraftFeatureDisabled,
          'The $directiveDefinitionLocation location is a working-draft '
          'feature; enable it with ParserOptions.allowDirectiveExtensions.',
          at: token,
        );
      }
    } else if (!locations.contains(name.value)) {
      cursor.unexpected(token);
    }
    return name;
  }
}
