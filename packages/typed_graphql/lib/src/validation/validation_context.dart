import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/diagnostic_sink.dart';
import '../diagnostics/source.dart';
import '../diagnostics/source_span.dart';
import '../language/ast/document.dart';
import '../language/ast/executable_definition.dart';
import '../language/ast/node.dart';
import '../language/visitor/ast_visitor.dart';
import '../schema/schema.dart';
import 'type_info.dart';
import 'usage_index.dart';
import 'validation_walk.dart';
import 'variable_usage.dart';

/// What the rules of one validation run share (R3.2, R3.6): the schema,
/// the document, the [typeInfo] of the walk, the sink their diagnostics
/// go to, the step budget, and the fragments and variable usages of the
/// document.
///
/// `DocumentValidator` makes one for each run and gives it to each rule's
/// `createVisitor`.
///
/// {@category validation}
final class ValidationContext {
  /// Creates the context of a run over [document], reporting into a sink.
  ///
  /// Diagnostics get spans in `source` when it is given, the text
  /// [document] was parsed from. [maxSteps] bounds the work beyond one
  /// walk (see [spend]).
  ValidationContext(
    this.schema,
    this.document,
    this._sink, {
    this._source,
    this.includesSuggestions = true,
    this.maxSteps = defaultMaxSteps,
  }) : typeInfo = TypeInfo(schema) {
    _usages = UsageIndex(typeInfo, spend, fragmentNamed);
  }

  /// The default of [maxSteps].
  static const int defaultMaxSteps = 1000000;

  /// The schema the document is validated against.
  final Schema schema;

  /// The document being validated.
  final Document document;

  /// The types around the node the walk is at.
  final TypeInfo typeInfo;

  /// Whether messages may suggest names ("Did you mean ..."), graphql-js's
  /// `hideSuggestions` negated; a production server turns them off
  /// (R5.15).
  final bool includesSuggestions;

  /// The most steps [spend] allows before the run stops.
  final int maxSteps;

  final DiagnosticSink _sink;
  final Source? _source;
  // Set in the constructor body: the index needs this context's methods.
  late final UsageIndex _usages;
  Map<String, FragmentDefinition>? _fragments;
  int _steps = 0;
  bool _isOverBudget = false;

  /// The most errors the run keeps; a rule that gathers its reports
  /// before it flushes them stops gathering there.
  int get maxErrors => _sink.maxErrors;

  /// Whether the run stops: the error limit or the step budget was
  /// reached. Reports are then ignored.
  bool get isAborted => _sink.isFull || _isOverBudget;

  /// Reports an error with [code] and [message] at the first of [nodes],
  /// the others being related places, as graphql-js lists an error's
  /// nodes. Ignored once the run [isAborted].
  void report(DiagnosticCode code, String message, List<Node> nodes) {
    if (isAborted) {
      return;
    }
    final spans = [
      if (_source case final source?)
        for (final node in nodes) SourceSpan(source, node.start, node.end),
    ];
    _sink.report(
      Diagnostic(
        code,
        .error,
        message,
        span: spans.firstOrNull,
        related: spans.skip(1).toList(),
      ),
    );
  }

  /// Charges [steps] units of work to the run's budget; false once the
  /// budget is spent.
  ///
  /// Work that grows faster than the document (an operation's fragment
  /// closure, field merging) is charged, so a document shaped to make it
  /// explode ends with one [DiagnosticCode.documentTooComplex] error
  /// instead of running for minutes.
  bool spend(int steps) {
    _steps += steps;
    if (_steps > maxSteps && !_isOverBudget) {
      _sink.report(
        Diagnostic(
          .documentTooComplex,
          .error,
          'The document is too complex to validate: it needs more than '
          '$maxSteps steps.',
          span: switch (_source) {
            final source? => SourceSpan(source, document.start, document.end),
            null => null,
          },
        ),
      );
      _isOverBudget = true;
    }
    return !_isOverBudget;
  }

  /// The fragment definition named [name]; the last one when several
  /// share it, as graphql-js's `getFragment`.
  FragmentDefinition? fragmentNamed(String name) => (_fragments ??= {
    for (final definition in document.definitions)
      if (definition is FragmentDefinition) definition.name.value: definition,
  })[name];

  /// The variable usages directly in [definition], in document order.
  ///
  /// This and the other usage queries answer once the walk has left the
  /// document, so a rule asks them in its `leave` of the [Document]; a
  /// [StateError] before that.
  List<VariableUsage> variableUsagesOf(ExecutableDefinition definition) =>
      _usages.variableUsagesOf(definition);

  /// The fragments [operation] spreads, directly or through other
  /// fragments, each once.
  List<FragmentDefinition> recursivelyReferencedFragments(
    OperationDefinition operation,
  ) => _usages.recursivelyReferencedFragments(operation);

  /// The variable usages in [operation] and in every fragment it reaches.
  List<VariableUsage> recursiveVariableUsages(OperationDefinition operation) =>
      _usages.recursiveVariableUsages(operation);

  /// The visitor that runs [visitors] in one walk with this context:
  /// it keeps [typeInfo] and the usage index up to date around them and
  /// stops the walk once the run [isAborted].
  AstVisitor visitorFor(List<AstVisitor> visitors) =>
      ValidationWalk(this, _usages, visitors);
}
