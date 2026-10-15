import 'package:typed_graphql/typed_graphql.dart';

/// A direct reading of spec §5.3.2 "Field Selection Merging" (the
/// FieldsInSetCanMerge and SameResponseShape algorithms), comparing every
/// pair: slow, and the reference the real rule is tested against.
final class NaiveFieldMerging(
  final Schema schema,
  final Document document, {

  /// How many levels of subfields are compared; null for all of them. A
  /// document with fragment cycles has infinitely many, so it needs one.
  final int? maxDepth,
}) {
  /// Creates the reference for [document] over [schema].
  this;

  int _depth = 0;

  late final Map<String, FragmentDefinition> _fragments = {
    for (final definition in document.definitions)
      if (definition case final FragmentDefinition fragment)
        fragment.name.value: fragment,
  };

  /// Whether every selection set of the document can be merged.
  bool get isValid {
    final pending = <(SelectionSet, SchemaType?)>[
      for (final definition in document.definitions)
        ?switch (definition) {
          OperationDefinition() => (
            definition.selectionSet,
            schema.typeNamed('Query'),
          ),
          FragmentDefinition() => (
            definition.selectionSet,
            schema.typeNamed(definition.typeCondition.name.value),
          ),
          _ => null,
        },
    ];
    while (pending.isNotEmpty) {
      final (selectionSet, parent) = pending.removeLast();
      if (!_canMerge(_collect(selectionSet, parent, {}))) return false;
      for (final selection in selectionSet.selections) {
        switch (selection) {
          case Field(:final name, selectionSet: final inner?):
            if (_fieldsOf(parent)[name.value] case final definition?) {
              pending.add((inner, _named(definition.type)));
            }
          case Field():
            break;
          case InlineFragment(:final typeCondition, :final selectionSet):
            pending.add((
              selectionSet,
              typeCondition == null
                  ? parent
                  : schema.typeNamed(typeCondition.name.value),
            ));
          case FragmentSpread():
            break;
        }
      }
    }
    return true;
  }

  SchemaType? _named(TypeRef type) => switch (type) {
    ListType(:final type) => _named(type),
    NonNullType(:final type) => _named(type),
    NamedType(:final name) => schema.typeNamed(name.value),
  };

  Map<String, SchemaField> _fieldsOf(SchemaType? type) => switch (type) {
    ObjectType() => {for (final field in type.fields) field.name: field},
    InterfaceType() => {for (final field in type.fields) field.name: field},
    _ => const {},
  };

  List<(Field, SchemaType?)> _collect(
    SelectionSet selectionSet,
    SchemaType? parent,
    Set<String> seen,
  ) {
    final fields = <(Field, SchemaType?)>[];
    for (final selection in selectionSet.selections) {
      switch (selection) {
        case Field():
          fields.add((selection, parent));
        case InlineFragment(:final typeCondition, :final selectionSet):
          final type = typeCondition == null
              ? parent
              : schema.typeNamed(typeCondition.name.value);
          fields.addAll(_collect(selectionSet, type, seen));
        case FragmentSpread(:final name):
          final fragment = _fragments[name.value];
          if (fragment != null && seen.add(name.value)) {
            final type = schema.typeNamed(fragment.typeCondition.name.value);
            fields.addAll(_collect(fragment.selectionSet, type, seen));
          }
      }
    }
    return fields;
  }

  SchemaField? _definition((Field, SchemaType?) item) =>
      _fieldsOf(item.$2)[item.$1.name.value];

  List<(Field, SchemaType?)> _subfields(List<(Field, SchemaType?)> items) {
    final fields = <(Field, SchemaType?)>[];
    final seen = <String>{};
    for (final item in items) {
      final definition = _definition(item);
      if (item.$1.selectionSet case final inner? when definition != null) {
        fields.addAll(_collect(inner, _named(definition.type), seen));
      }
    }
    return fields;
  }

  Map<String, List<(Field, SchemaType?)>> _byResponseName(
    List<(Field, SchemaType?)> items,
  ) {
    final groups = <String, List<(Field, SchemaType?)>>{};
    for (final item in items) {
      final field = item.$1;
      (groups[field.alias?.value ?? field.name.value] ??= []).add(item);
    }
    return groups;
  }

  String _shape(TypeRef type) {
    final buffer = StringBuffer();
    var current = type;
    while (true) {
      switch (current) {
        case ListType(:final type):
          buffer.write('[');
          current = type;
        case NonNullType(:final type):
          buffer.write('!');
          current = type;
        case NamedType(:final name):
          final named = schema.typeNamed(name.value);
          buffer.write(named != null && named.isLeafType ? name.value : '{}');
          return buffer.toString();
      }
    }
  }

  bool _sameShape((Field, SchemaType?) first, (Field, SchemaType?) second) {
    final (one, other) = (_definition(first), _definition(second));
    if (one == null || other == null) return true;
    if (_shape(one.type) != _shape(other.type)) return false;
    final (oneType, otherType) = (_named(one.type), _named(other.type));
    if (oneType == null || otherType == null) return true;
    if (!oneType.isCompositeType || !otherType.isCompositeType) return true;
    final merged = _subfields([first, second]);
    if (_isTooDeep) return true;
    _depth++;
    final isSame = _sameShapeInGroups(merged);
    _depth--;
    return isSame;
  }

  bool get _isTooDeep => switch (maxDepth) {
    final limit? => _depth >= limit,
    null => false,
  };

  bool _sameShapeInGroups(List<(Field, SchemaType?)> merged) {
    for (final group in _byResponseName(merged).values) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          if (!_sameShape(group[i], group[j])) return false;
        }
      }
    }
    return true;
  }

  String _arguments(Field field) {
    final sorted = [...field.arguments]
      ..sort((a, b) => a.name.value.compareTo(b.name.value));
    return [
      for (final argument in sorted)
        '${argument.name.value}:${_value(argument.value)}',
    ].join(',');
  }

  String _value(Value value) => switch (value) {
    ObjectValue(:final fields) =>
      '{${([...fields]..sort((a, b) => a.name.value.compareTo(b.name.value))).map((field) => '${field.name.value}:${_value(field.value)}').join(',')}}',
    ListValue(:final values) => '[${values.map(_value).join(',')}]',
    _ => const Printer().print(value),
  };

  bool _canMerge(List<(Field, SchemaType?)> items) {
    for (final group in _byResponseName(items).values) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          if (!_pairCanMerge(group[i], group[j])) return false;
        }
      }
    }
    return true;
  }

  bool _pairCanMerge((Field, SchemaType?) first, (Field, SchemaType?) second) {
    if (!_sameShape(first, second)) return false;
    final mayBeSame =
        identical(first.$2, second.$2) ||
        first.$2 is! ObjectType ||
        second.$2 is! ObjectType;
    if (!mayBeSame) return true;
    if (first.$1.name.value != second.$1.name.value ||
        _arguments(first.$1) != _arguments(second.$1)) {
      return false;
    }
    if (_isTooDeep) return true;
    _depth++;
    final canMerge = _canMerge(_subfields([first, second]));
    _depth--;
    return canMerge;
  }
}
