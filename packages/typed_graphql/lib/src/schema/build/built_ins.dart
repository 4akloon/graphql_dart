import '../../diagnostics/source.dart';
import '../../language/ast/document.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/parser/parse_result.dart';
import '../../language/parser/parser.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import 'built_in_sdl.dart';
import 'element_reader.dart';
import 'node_spans.dart';
import 'type_reader.dart';

/// The definitions every schema has without declaring them (spec §3.5,
/// §3.13, §4.5; R2.6): the five scalars, the five directives and the
/// introspection types, and the opt-in `@defer` and `@stream`.
///
/// They are read once from [BuiltInSdl] and have no spans. `Schema` finds
/// the scalars and directives by name; the SDL printer prints them only
/// when asked.
///
/// {@category schema}
final class const BuiltIns() {
  /// Creates the accessor; the definitions are shared.
  this;

  static const TypeReader _reader = TypeReader(ElementReader(NodeSpans(null)));

  static final Document _document = switch (const Parser().parse(
    Source(const BuiltInSdl().text, name: 'built-ins'),
  )) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };

  static final List<SchemaType> _types = [
    for (final definition in _document.definitions.whereType<TypeDefinition>())
      _reader.type(definition),
  ];

  static final List<SchemaDirective> _allDirectives = [
    for (final definition
        in _document.definitions.whereType<DirectiveDefinition>())
      _reader.elements.directive(definition),
  ];

  static final List<ScalarType> _scalars = List.unmodifiable(
    _types.whereType<ScalarType>(),
  );

  static final SchemaDirective _defer = _directiveNamed('defer');

  static final SchemaDirective _stream = _directiveNamed('stream');

  // The five specified directives are all but the two opt-in ones, so the
  // SDL order of `@defer` and `@stream` cannot swap them.
  static final List<SchemaDirective> _directives = List.unmodifiable(
    _allDirectives.where(
      (directive) => directive != _defer && directive != _stream,
    ),
  );

  static SchemaDirective _directiveNamed(String name) =>
      _allDirectives.singleWhere((directive) => directive.name == name);

  static final List<SchemaType> _introspectionTypes = List.unmodifiable(
    _types.where((type) => type is! ScalarType),
  );

  /// `String`, `Int`, `Float`, `Boolean` and `ID`, in that order.
  List<ScalarType> get scalars => _scalars;

  /// `@include`, `@skip`, `@deprecated`, `@specifiedBy` and `@oneOf`, in
  /// that order.
  List<SchemaDirective> get directives => _directives;

  /// `@defer`, added to a schema only by an opt-in.
  SchemaDirective get defer => _defer;

  /// `@stream`, added to a schema only by an opt-in.
  SchemaDirective get stream => _stream;

  /// `__Schema`, `__Type`, `__TypeKind`, `__Field`, `__InputValue`,
  /// `__EnumValue`, `__Directive` and `__DirectiveLocation`, in that order.
  List<SchemaType> get introspectionTypes => _introspectionTypes;

  /// The built-in scalar named [name]; null when there is none.
  ScalarType? scalarNamed(String name) {
    for (final scalar in scalars) {
      if (scalar.name == name) {
        return scalar;
      }
    }
    return null;
  }

  /// The built-in scalar or introspection type named [name]; null when
  /// there is none.
  SchemaType? typeNamed(String name) {
    for (final type in _types) {
      if (type.name == name) {
        return type;
      }
    }
    return null;
  }

  /// The built-in directive named [name], among [directives]; null when
  /// there is none (`@defer` and `@stream` are not built in by default).
  SchemaDirective? directiveNamed(String name) {
    for (final directive in directives) {
      if (directive.name == name) {
        return directive;
      }
    }
    return null;
  }

  /// Whether [name] is a built-in directive: one of [directives], or
  /// `defer` or `stream` when [includesDeferAndStream].
  bool isBuiltInDirective(
    String name, {
    required bool includesDeferAndStream,
  }) =>
      directiveNamed(name) != null ||
      (includesDeferAndStream && (name == 'defer' || name == 'stream'));
}
