/// The catalog of diagnostic codes: one value per problem, each with a
/// stable [id] and a doc comment that says when it is reported.
///
/// An id is `GQL` and three digits; the hundreds digit is the area:
///
/// | Ids | Area | Codes added by |
/// |---|---|---|
/// | `GQL0xx` | lexer and syntax | M2 |
/// | `GQL1xx` | type system: building and validating a schema | M3 |
/// | `GQL2xx` | operation validation (the doc comment names the spec rule) | M4 |
/// | `GQL3xx` | coercion and execution | M5 |
/// | `GQL4xx` | transports and protocols | M6, M7 |
/// | `GQL5xx` | code generation | M8, M10 |
///
/// `GQL000` belongs to no area: any sink reports it when its limit is
/// reached. Values are sorted by [id]. An id is public API: it is never
/// renumbered, reused or removed. Stages add codes in minor versions, so do
/// not switch over this enum exhaustively: match the codes you handle and
/// add a wildcard case.
///
/// {@category diagnostics}
enum DiagnosticCode(
  /// The stable id, such as `GQL000`, shown in messages and documentation.
  final String id,
) {
  /// `GQL000`: a sink kept as many errors as its limit allows and dropped
  /// the rest. It is reported once, at the place of the first dropped
  /// error; the run behind the sink should stop.
  diagnosticLimitReached('GQL000'),

  /// `GQL001`: a character that starts no token, such as `~`, a single
  /// quote or `..`. In a schema coordinate, any character but a name, `.`,
  /// `(`, `)`, `:` and `@`, white space included.
  unexpectedCharacter('GQL001'),

  /// `GQL002`: a code unit that is not part of a Unicode scalar value: a
  /// surrogate without its pair, in or outside a string (spec §2.1.1).
  invalidCharacter('GQL002'),

  /// `GQL003`: a malformed number, such as `007`, `1.`, `.5`, `1e` or a
  /// name glued to a number (`1a`).
  invalidNumber('GQL003'),

  /// `GQL004`: a string or block string without its closing quotes; a
  /// quoted string also ends at a line break.
  unterminatedString('GQL004'),

  /// `GQL005`: an escape sequence that is not `\"`, `\\`, `\/`, `\b`,
  /// `\f`, `\n`, `\r`, `\t` or a Unicode escape of a scalar value.
  invalidEscapeSequence('GQL005'),

  /// `GQL006`: a document with more tokens than the limit; the rest is not
  /// read.
  tokenLimitExceeded('GQL006'),

  /// `GQL007`: the parser needed a certain token, such as `:` or a name,
  /// and found another.
  expectedToken('GQL007'),

  /// `GQL008`: a token that cannot appear where it is, such as `)` at the
  /// start of a value or an unknown definition keyword.
  unexpectedToken('GQL008'),

  /// `GQL009`: a variable inside a constant value, such as a default value
  /// or an argument of a type-system directive.
  variableInConstant('GQL009'),

  /// `GQL010`: selection sets, lists, objects and list types nested deeper
  /// than the parser's `maxDepth`; the definition is dropped.
  depthLimitExceeded('GQL010'),

  /// `GQL011`: a description where none is allowed: before a shorthand
  /// query `{ ... }` or before something that is not a definition.
  misplacedDescription('GQL011'),

  /// `GQL012`: an empty selection set, `{ }`, which only the working
  /// draft allows (`ParserOptions.allowEmptySelectionSets`).
  emptySelectionSet('GQL012'),

  /// `GQL013`: an enum value named `true`, `false` or `null` (spec
  /// §3.9, `EnumValue`).
  reservedEnumValueName('GQL013'),

  /// `GQL014`: working-draft grammar that the parser's options leave off:
  /// a directive extension, directives on a directive definition or the
  /// `DIRECTIVE_DEFINITION` location without
  /// `ParserOptions.allowDirectiveExtensions`.
  workingDraftFeatureDisabled('GQL014'),

  /// `GQL100`: an operation or a fragment in a document built into a
  /// schema; it is ignored.
  executableDefinitionInSchema('GQL100'),

  /// `GQL101`: a second type definition with the name of a type already
  /// defined in the document or in the schema being extended; the second
  /// is ignored.
  duplicateTypeName('GQL101'),

  /// `GQL102`: a second directive definition with the name of a directive
  /// already defined in the document or in the schema being extended; the
  /// second is ignored.
  duplicateDirectiveName('GQL102'),

  /// `GQL103`: a definition or an extension of a built-in: a built-in
  /// scalar, an introspection type or a built-in directive (R2.6); it is
  /// ignored.
  builtInRedefinition('GQL103'),

  /// `GQL104`: a second field or input field with one name in a type, its
  /// extensions included; the second is ignored.
  duplicateFieldName('GQL104'),

  /// `GQL105`: a second argument with one name in a field or a directive
  /// definition; the second is ignored.
  duplicateArgumentName('GQL105'),

  /// `GQL106`: a second value with one name in an enum type, its
  /// extensions included; the second is ignored.
  duplicateEnumValueName('GQL106'),

  /// `GQL107`: a second schema definition, or one in a document that
  /// extends a schema with root types; it is ignored.
  duplicateSchemaDefinition('GQL107'),

  /// `GQL108`: a second root type for one operation, in the schema
  /// definition, its extensions or the schema being extended; the second
  /// is ignored.
  duplicateOperationType('GQL108'),

  /// `GQL109`: an extension of a type or a directive (`extend directive`)
  /// that neither the document nor the schema being extended defines; it
  /// is ignored.
  unknownExtensionTarget('GQL109'),

  /// `GQL110`: an extension of a type of another kind, such as
  /// `extend input` of an object type; it is ignored.
  extensionKindMismatch('GQL110');
}
