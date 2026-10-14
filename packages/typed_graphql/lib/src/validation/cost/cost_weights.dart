import 'dart:math';

import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../schema/model/applied_directive.dart';
import '../../schema/model/input_value.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import 'list_size_setting.dart';

/// The `@cost` weights and `@listSize` settings of a schema's elements, each
/// parsed once.
///
/// Elements compare by identity, so a map keyed by element is a cache. A
/// weight that is not a finite number is the element's default weight: the
/// schema check reports it.
final class CostWeights(
  /// The schema whose elements are weighed.
  final Schema schema,
) {
  /// Creates empty caches for [schema].
  this;

  final Map<Object, double> _weights = {};
  final Map<SchemaField, ListSizeSetting?> _settings = {};

  /// The weight of [type].
  double ofType(SchemaType type) {
    if (_weights[type] case final known?) {
      return known;
    }
    final weight = switch (type) {
      ObjectType() => _declared(type.appliedDirectives) ?? 1.0,
      ScalarType() || EnumType() => _declared(type.appliedDirectives) ?? 0.0,
      InterfaceType() || UnionType() => _heaviest(type),
      InputObjectType() => 0.0,
    };
    return _weights[type] = weight;
  }

  /// The weight of [field]: its `@cost`, else its returned type's weight.
  double ofField(SchemaField field) =>
      _ofElement(field, field.appliedDirectives, field.type);

  /// The weight of an argument or input field.
  double ofInputValue(InputValue value) =>
      _ofElement(value, value.appliedDirectives, value.type);

  /// The weight of the named type [type] wraps; 0 when it is unknown.
  double ofNamedTypeIn(TypeRef type) => switch (schema.namedTypeOf(type)) {
    final named? => ofType(named),
    null => 0.0,
  };

  /// The `@listSize` of [field]; null when it has none.
  ListSizeSetting? listSizeOf(SchemaField field) {
    if (_settings.containsKey(field)) {
      return _settings[field];
    }
    return _settings[field] = ListSizeSetting.read(field.appliedDirectives);
  }

  double _ofElement(
    Object element,
    List<AppliedDirective> directives,
    TypeRef type,
  ) {
    if (_weights[element] case final known?) {
      return known;
    }
    return _weights[element] = _declared(directives) ?? ofNamedTypeIn(type);
  }

  // The draft's upper bound: an abstract type weighs as its heaviest
  // possible type.
  double _heaviest(SchemaType type) {
    var heaviest = 0.0;
    for (final possible in schema.possibleTypes(type)) {
      heaviest = max(heaviest, ofType(possible));
    }
    return heaviest;
  }

  double? _declared(List<AppliedDirective> directives) {
    for (final directive in directives) {
      if (directive.name == 'cost') {
        final weight = switch (directive.argument('weight')) {
          StringValue(:final value) => double.tryParse(value),
          _ => null,
        };
        return weight != null && weight.isFinite ? weight : null;
      }
    }
    return null;
  }
}
