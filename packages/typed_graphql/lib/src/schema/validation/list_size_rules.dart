import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../model/applied_directive.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'validation_report.dart';

/// The rules of an applied `@listSize` (IBM cost draft): a list field or
/// `sizedFields`, slicing arguments that are `Int` arguments, sized fields
/// that are list fields, and no `assumedSize` that slicing arguments make
/// ambiguous.
final class ListSizeRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of the `@listSize` applied to [field], whose
  /// schema coordinate is [coordinate].
  void check(String coordinate, SchemaField field) {
    for (final directive in field.appliedDirectives) {
      if (directive.name != 'listSize') {
        continue;
      }
      final sizedFields = _names(directive, 'sizedFields');
      final slicing = _names(directive, 'slicingArguments');
      if (sizedFields.isEmpty && !_isList(field.type)) {
        report.error(
          .listSizeOnNonList,
          '@listSize on "$coordinate" requires a list field or sizedFields.',
          [directive.span],
        );
      }
      _slicing(coordinate, field, directive, slicing);
      _sized(coordinate, field, directive, sizedFields);
      _assumedSize(coordinate, field, directive, slicing);
    }
  }

  void _slicing(
    String coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> names,
  ) {
    for (final name in names) {
      final type = field.argumentNamed(name)?.type;
      if (type == null || !_isInt(type)) {
        report.error(
          .invalidSlicingArgument,
          'The slicing argument "$name" of @listSize on "$coordinate" is '
          'not an Int argument of the field.',
          [directive.span],
        );
      }
    }
  }

  void _sized(
    String coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> names,
  ) {
    if (names.isEmpty) {
      return;
    }
    final returned = schema.namedTypeOf(field.type);
    final fields = switch (returned) {
      ObjectType(:final fields) || InterfaceType(:final fields) => fields,
      _ => const <SchemaField>[],
    };
    for (final name in names) {
      final sized = fields.where((candidate) => candidate.name == name);
      if (sized.isEmpty || !_isList(sized.first.type)) {
        report.error(
          .invalidSizedField,
          'The sized field "$name" of @listSize on "$coordinate" is not a '
          'list field of "${const TypeComparator().namedTypeName(field.type)}".',
          [directive.span],
        );
      }
    }
  }

  void _assumedSize(
    String coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> slicing,
  ) {
    if (directive.argument('assumedSize') is! IntValue || slicing.isEmpty) {
      return;
    }
    final isOneRequired = switch (directive.argument(
      'requireOneSlicingArgument',
    )) {
      BooleanValue(value: false) => false,
      _ => true,
    };
    final hasDefault = slicing.any(
      (name) => field.argumentNamed(name)?.defaultValue != null,
    );
    if (isOneRequired || hasDefault) {
      report.error(
        .conflictingAssumedSize,
        '@listSize on "$coordinate" gives assumedSize with slicing '
        'arguments, which needs requireOneSlicingArgument: false and '
        'slicing arguments without default values.',
        [directive.span],
      );
    }
  }

  // An argument that is not a list of strings is a GQL124 already.
  List<String> _names(AppliedDirective directive, String argument) {
    if (directive.argument(argument) case ListValue(:final values)) {
      return [
        for (final value in values)
          if (value case StringValue(:final value)) value,
      ];
    }
    return const [];
  }

  // Loops, not recursion: a wrapper chain can be deep.
  TypeRef _unwrapNonNull(TypeRef type) {
    var current = type;
    while (current is NonNullType) {
      current = current.type;
    }
    return current;
  }

  bool _isList(TypeRef type) => _unwrapNonNull(type) is ListType;

  bool _isInt(TypeRef type) => switch (_unwrapNonNull(type)) {
    NamedType(:final name) => name.value == 'Int',
    _ => false,
  };
}
