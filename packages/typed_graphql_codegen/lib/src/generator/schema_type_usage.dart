import 'package:typed_graphql/typed_graphql.dart';

/// Finds the schema types the documents use, which are the only ones
/// generated (spec §7, "pruned").
///
/// Starts from the named type of every variable and of every selected field,
/// keeps the enums and input objects, and follows the fields of each input
/// object with a work list: input types may be cyclic.
final class const SchemaTypeUsage(final Schema schema) {
  /// Creates the finder for [schema].
  this;

  /// The enums and input objects [document] uses, sorted by name.
  List<SchemaType> of(Document document) {
    final collector = _NamedTypes(schema);
    const AstWalker().walk(document, collector);
    final used = <String, SchemaType>{};
    final pending = [...collector.types];
    while (pending.isNotEmpty) {
      final type = pending.removeLast();
      if (used.containsKey(type.name)) continue;
      switch (type) {
        case EnumType():
          used[type.name] = type;
        case InputObjectType(:final fields):
          used[type.name] = type;
          pending.addAll(_typesOf(fields));
        case _:
      }
    }
    return [
      for (final entry
          in used.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        entry.value,
    ];
  }

  Iterable<SchemaType> _typesOf(List<InputValue> fields) => [
    for (final field in fields) ?schema.namedTypeOf(field.type),
  ];
}

/// Collects the named types of variables and fields in one walk.
final class _NamedTypes extends AstVisitor {
  _NamedTypes(this._schema) : _info = TypeInfo(_schema);

  final Schema _schema;
  final TypeInfo _info;
  final List<SchemaType> types = [];

  @override
  VisitAction enter(Node node) {
    _info.enter(node);
    final TypeRef? type = switch (node) {
      VariableDefinition(:final type) => type,
      Field() => _info.type,
      _ => null,
    };
    if (type == null) return VisitAction.next;
    if (_schema.namedTypeOf(type) case final named?) types.add(named);
    return VisitAction.next;
  }

  @override
  void leave(Node node) => _info.leave(node);
}
