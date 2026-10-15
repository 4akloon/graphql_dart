import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../model/applied_directive.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../model/string_list_argument.dart';
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

  // The names of the list fields of each returned type, built once per
  // run: a `sizedFields` of many names costs one lookup each.
  final Map<SchemaType, Set<String>> _listFieldNames = {};

  /// Reports the problems of the `@listSize` applied to [field], whose
  /// schema coordinate [coordinate] builds; it is called only to report.
  void check(String Function() coordinate, SchemaField field) {
    for (final directive in field.appliedDirectives) {
      if (report.isFull) {
        return;
      }
      if (directive.name != 'listSize') {
        continue;
      }
      final arguments = StringListArgument(directive);
      final sizedFields = arguments.named('sizedFields');
      final slicing = arguments.named('slicingArguments');
      if (sizedFields.isEmpty && !_isList(field.type)) {
        report.error(
          .listSizeOnNonList,
          '@listSize on "${coordinate()}" requires a list field or '
          'sizedFields.',
          [directive.span],
        );
      }
      _slicing(coordinate, field, directive, slicing);
      _sized(coordinate, field, directive, sizedFields);
      _assumedSize(coordinate, field, directive, slicing);
    }
  }

  void _slicing(
    String Function() coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> names,
  ) {
    for (final name in names) {
      if (report.isFull) {
        return;
      }
      final type = field.argumentNamed(name)?.type;
      if (type == null || !_isInt(type)) {
        report.error(
          .invalidSlicingArgument,
          'The slicing argument "$name" of @listSize on "${coordinate()}" is '
          'not an Int argument of the field.',
          [directive.span],
        );
      }
    }
  }

  void _sized(
    String Function() coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> names,
  ) {
    if (names.isEmpty) {
      return;
    }
    final listFields = _listFieldsOf(schema.namedTypeOf(field.type));
    for (final name in names) {
      if (report.isFull) {
        return;
      }
      if (!listFields.contains(name)) {
        report.error(
          .invalidSizedField,
          'The sized field "$name" of @listSize on "${coordinate()}" is not '
          'a list field of '
          '"${const TypeComparator().namedTypeName(field.type)}".',
          [directive.span],
        );
      }
    }
  }

  Set<String> _listFieldsOf(SchemaType? returned) {
    if (returned == null) {
      return const {};
    }
    return _listFieldNames[returned] ??= switch (returned) {
      ObjectType(:final fields) || InterfaceType(:final fields) => {
        for (final candidate in fields)
          if (_isList(candidate.type)) candidate.name,
      },
      _ => const <String>{},
    };
  }

  void _assumedSize(
    String Function() coordinate,
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
        '@listSize on "${coordinate()}" gives assumedSize with slicing '
        'arguments, which needs requireOneSlicingArgument: false and '
        'slicing arguments without default values.',
        [directive.span],
      );
    }
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
