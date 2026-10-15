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
  /// §3.9, `EnumValue`); schema validation reports one in a schema built
  /// in code.
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
  /// is ignored. Schema validation reports a repeat in a schema built in
  /// code.
  duplicateTypeName('GQL101'),

  /// `GQL102`: a second directive definition with the name of a directive
  /// already defined in the document or in the schema being extended; the
  /// second is ignored. Schema validation reports a repeat in a schema
  /// built in code.
  duplicateDirectiveName('GQL102'),

  /// `GQL103`: a definition or an extension of a built-in: a built-in
  /// scalar, an introspection type or a built-in directive (R2.6); it is
  /// ignored. Schema validation reports a built-in name declared in a
  /// schema built in code.
  builtInRedefinition('GQL103'),

  /// `GQL104`: a second field or input field with one name in a type, its
  /// extensions included; the second is ignored. Schema validation
  /// reports a repeat in a schema built in code.
  duplicateFieldName('GQL104'),

  /// `GQL105`: a second argument with one name in a field or a directive
  /// definition; the second is ignored. Schema validation reports a
  /// repeat in a schema built in code.
  duplicateArgumentName('GQL105'),

  /// `GQL106`: a second value with one name in an enum type, its
  /// extensions included; the second is ignored. Schema validation
  /// reports a repeat in a schema built in code.
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
  extensionKindMismatch('GQL110'),

  /// `GQL111`: a schema without a query root type (spec §3.3.1).
  missingQueryRootType('GQL111'),

  /// `GQL112`: a root operation type that is not an object type, such as
  /// `query: SomeInterface` (spec §3.3.1).
  rootTypeNotObject('GQL112'),

  /// `GQL113`: one object type that is the root type of two operations
  /// (spec §3.3.1).
  sharedRootType('GQL113'),

  /// `GQL114`: a name of a type, field, argument, enum value or directive
  /// that begins with `__`, which introspection reserves (spec §3.4).
  reservedName('GQL114'),

  /// `GQL115`: a name that is empty or not of the name syntax
  /// `[_A-Za-z][_0-9A-Za-z]*` (spec §2.1.9), in a schema built in code.
  invalidName('GQL115'),

  /// `GQL116`: a reference to a type the schema does not have: the type
  /// of a field, an argument or an input field, an implemented interface,
  /// a union member or a root type (spec §3.4).
  unknownType('GQL116'),

  /// `GQL117`: a directive applied to a schema element that the schema
  /// does not define (spec §3.13).
  unknownDirective('GQL117'),

  /// `GQL118`: a directive applied at a location its definition does not
  /// list, such as `@deprecated` on an object type (spec §3.13).
  misplacedDirective('GQL118'),

  /// `GQL119`: a directive that is not `repeatable` applied twice to one
  /// schema element (spec §3.13).
  repeatedDirective('GQL119'),

  /// `GQL120`: an applied directive given one argument twice
  /// (spec §5.4.2).
  duplicateDirectiveArgument('GQL120'),

  /// `GQL121`: an applied directive given an argument its definition
  /// does not have (spec §5.4.1).
  unknownDirectiveArgument('GQL121'),

  /// `GQL122`: an applied directive without a required argument: one of
  /// non-null type and without a default value (spec §5.4.2.1).
  missingDirectiveArgument('GQL122'),

  /// `GQL123`: a default value of an argument or an input field that is
  /// not a value of its type (spec §3.6.1, §3.10).
  invalidDefaultValue('GQL123'),

  /// `GQL124`: an argument of an applied directive whose value is not a
  /// value of the argument's type (spec §5.6.1).
  invalidDirectiveArgumentValue('GQL124'),

  /// `GQL125`: an object or interface type without fields (spec §3.6,
  /// §3.7).
  missingFields('GQL125'),

  /// `GQL126`: a field whose type is an input object type (spec §3.6).
  notOutputType('GQL126'),

  /// `GQL127`: an argument or an input field whose type is an object,
  /// interface or union type (spec §3.6.1, §3.10).
  notInputType('GQL127'),

  /// `GQL128`: a required argument or input field (non-null, without
  /// a default value) marked `@deprecated` (spec §3.6.1, §3.10).
  deprecatedRequiredInput('GQL128'),

  /// `GQL129`: a directive definition without locations, which only
  /// a schema built in code can have (spec §3.13).
  missingDirectiveLocations('GQL129'),

  /// `GQL130`: a directive definition that references itself, directly
  /// or through the types and directives it references (spec §3.13).
  directiveSelfReference('GQL130'),

  /// `GQL131`: an object or interface type that implements a type
  /// that is not an interface type (spec §3.6, §3.7).
  implementsNonInterface('GQL131'),

  /// `GQL132`: an interface type that implements itself, directly or
  /// through the interfaces it inherits (spec §3.7).
  circularImplementation('GQL132'),

  /// `GQL133`: an object or interface type that names one interface twice
  /// among the interfaces it implements (spec §3.6, §3.7).
  repeatedInterface('GQL133'),

  /// `GQL134`: a type that implements an interface but not the
  /// interfaces that interface implements (spec §3.7).
  missingTransitiveInterface('GQL134'),

  /// `GQL135`: a type without a field of an interface it implements
  /// (spec §3.6.3 `IsValidImplementation`).
  missingInterfaceField('GQL135'),

  /// `GQL136`: a field whose type is not a subtype of the type of
  /// the interface field it implements (spec §3.6.3
  /// `IsValidImplementationFieldType`).
  invalidImplementationFieldType('GQL136'),

  /// `GQL137`: a field without an argument of the interface field it
  /// implements (spec §3.6.3).
  missingInterfaceArgument('GQL137'),

  /// `GQL138`: an argument whose type is not the type of the same
  /// argument of the interface field (spec §3.6.3).
  invalidImplementationArgumentType('GQL138'),

  /// `GQL139`: a required argument of a field that the interface field
  /// it implements does not have (spec §3.6.3).
  requiredExtraArgument('GQL139'),

  /// `GQL140`: a deprecated field that implements an interface
  /// field that is not deprecated (spec §3.6.3).
  deprecatedImplementationField('GQL140'),

  /// `GQL141`: a union type without member types (spec §3.8).
  missingUnionMembers('GQL141'),

  /// `GQL142`: a union type that names one member type twice
  /// (spec §3.8).
  repeatedUnionMember('GQL142'),

  /// `GQL143`: a union member that is not an object type (spec §3.8).
  nonObjectUnionMember('GQL143'),

  /// `GQL144`: an enum type without values (spec §3.9).
  missingEnumValues('GQL144'),

  /// `GQL145`: an input object type without fields (spec §3.10).
  missingInputFields('GQL145'),

  /// `GQL146`: a field of a `@oneOf` input object type of non-null
  /// type (spec §3.10.1).
  nonNullOneOfField('GQL146'),

  /// `GQL147`: a field of a `@oneOf` input object type with a default
  /// value (spec §3.10.1).
  defaultedOneOfField('GQL147'),

  /// `GQL148`: an input object type that cannot be given a finite
  /// value: it reaches itself through non-null fields, or through every
  /// field of a `@oneOf` type (spec §3.10.1 `InputObjectHasUnbreakableCycle`).
  infiniteInputValue('GQL148'),

  /// `GQL149`: an input field whose default value contains itself,
  /// directly or through the default values of other fields (spec §3.10).
  defaultValueCycle('GQL149'),

  /// `GQL150`: an introspection result that is not an object with a
  /// `__schema` object, such as a whole response instead of its `data`
  /// (spec §4).
  invalidIntrospectionResult('GQL150'),

  /// `GQL151`: a member an introspection result must have that is
  /// absent or null, such as the `fields` of an `OBJECT` type (spec §4.2).
  missingIntrospectionMember('GQL151'),

  /// `GQL152`: a type in an introspection result whose `kind` is absent
  /// or not a named type kind (spec §4.2.1).
  unknownIntrospectionKind('GQL152'),

  /// `GQL153`: a member of an introspection result of the wrong JSON
  /// type, a default value that is not a constant GraphQL value, an
  /// unknown directive location or a `NON_NULL` inside a `NON_NULL`
  /// (spec §4.2).
  malformedIntrospectionMember('GQL153'),

  /// `GQL154`: a type reference in an introspection result to a type its
  /// `types` do not list: the query was not a full one (spec §4.2).
  unknownIntrospectionType('GQL154'),

  /// `GQL155`: a list or non-null type reference in an introspection
  /// result without its `ofType`: the type is deeper than the query read
  /// (spec §4.2), or a chain of more than 100 wrappers, the most a query
  /// can read.
  introspectionTypeTooDeep('GQL155'),

  /// `GQL156`: the `weight` of an applied `@cost` that is not a GraphQL
  /// number (an integer or float literal written as text), reported when
  /// the schema includes the cost directives (IBM cost draft).
  invalidCostWeight('GQL156'),

  /// `GQL157`: a `@cost` on a field of an interface or on one of its
  /// arguments; the draft applies it to the fields of the implementing
  /// types. This is stricter than the draft, which only advises against it:
  /// the cost of an abstract type is the heaviest of its possible types.
  misplacedCost('GQL157'),

  /// `GQL158`: a `@listSize` on a field whose type is not a list and that
  /// names no `sizedFields`.
  listSizeOnNonList('GQL158'),

  /// `GQL159`: a name in the `slicingArguments` of a `@listSize` that is
  /// not an argument of type `Int` or `Int!` of the field.
  invalidSlicingArgument('GQL159'),

  /// `GQL160`: a name in the `sizedFields` of a `@listSize` that is not a
  /// list field of the field's object or interface return type.
  invalidSizedField('GQL160'),

  /// `GQL161`: a `@listSize` that gives `assumedSize` together with
  /// slicing arguments, without `requireOneSlicingArgument: false` and
  /// slicing arguments that have no default value.
  conflictingAssumedSize('GQL161'),

  /// `GQL200`: a type system definition or extension in a document sent
  /// for execution (spec §5.1.1).
  executableDefinitions('GQL200'),

  /// `GQL201`: an operation whose type has no root type in the schema,
  /// such as a mutation against a schema without one (spec §5.2.1.1).
  knownOperationTypes('GQL201'),

  /// `GQL202`: two operations with the same name (spec §5.2.2.1).
  uniqueOperationNames('GQL202'),

  /// `GQL203`: an anonymous operation beside another operation
  /// (spec §5.2.3.1).
  loneAnonymousOperation('GQL203'),

  /// `GQL204`: a subscription that selects more than one top-level field,
  /// an introspection field at the top level, or uses `@skip` or
  /// `@include` there (spec §5.2.4.1).
  singleFieldSubscriptions('GQL204'),

  /// `GQL205`: a field the parent type does not define and that is no
  /// meta-field (spec §5.3.1).
  fieldsOnCorrectType('GQL205'),

  /// `GQL206`: two fields with one response name that cannot be merged:
  /// different fields or arguments under one parent, or different
  /// response shapes (spec §5.3.2).
  overlappingFieldsCanBeMerged('GQL206'),

  /// `GQL207`: a leaf field with a selection, or a composite field without
  /// one (spec §5.3.3).
  scalarLeafs('GQL207'),

  /// `GQL208`: an argument that the field or directive does not define
  /// (spec §5.4.1).
  knownArgumentNames('GQL208'),

  /// `GQL209`: a field or directive that names an argument more than once
  /// (spec §5.4.2).
  uniqueArgumentNames('GQL209'),

  /// `GQL210`: a non-null argument without a default value that a field or
  /// directive does not provide (spec §5.4.3).
  providedRequiredArguments('GQL210'),

  /// `GQL211`: two fragment definitions with the same name (spec
  /// §5.5.1.1).
  uniqueFragmentNames('GQL211'),

  /// `GQL212`: a type name in a type condition or a variable definition
  /// that the schema does not define (spec §5.5.1.2, §5.8.1).
  knownTypeNames('GQL212'),

  /// `GQL213`: a fragment or inline fragment whose type condition is not
  /// an object, interface or union type (spec §5.5.1.3).
  fragmentsOnCompositeTypes('GQL213'),

  /// `GQL214`: a fragment definition that no operation spreads, directly or
  /// through other fragments (spec §5.5.1.4).
  noUnusedFragments('GQL214'),

  /// `GQL215`: a fragment spread whose fragment the document does not
  /// define (spec §5.5.2.1).
  knownFragmentNames('GQL215'),

  /// `GQL216`: a fragment that spreads itself, directly or through other
  /// fragments (spec §5.5.2.2).
  noFragmentCycles('GQL216'),

  /// `GQL217`: a fragment spread or inline fragment whose type condition
  /// can never apply to the parent type (spec §5.5.2.3).
  possibleFragmentSpreads('GQL217'),

  /// `GQL218`: a value literal that is not a value of the input type
  /// expected at its position (spec §5.6.1).
  valuesOfCorrectType('GQL218'),

  /// `GQL219`: an input object literal that gives a field its type does
  /// not define (spec §5.6.2).
  inputObjectFieldNames('GQL219'),

  /// `GQL220`: an input object literal that gives a field more than once
  /// (spec §5.6.3).
  uniqueInputFieldNames('GQL220'),

  /// `GQL221`: an input object literal that omits a required field of its
  /// type (spec §5.6.4).
  inputObjectRequiredFields('GQL221'),

  /// `GQL222`: a directive the schema does not define (spec §5.7.1).
  knownDirectives('GQL222'),

  /// `GQL223`: a directive applied at a location its definition does not
  /// list (spec §5.7.2).
  directivesInValidLocations('GQL223'),

  /// `GQL224`: a non-repeatable directive applied more than once at one
  /// location (spec §5.7.3).
  uniqueDirectivesPerLocation('GQL224'),

  /// `GQL225`: an operation that declares two variables with one name
  /// (spec §5.8.1).
  uniqueVariableNames('GQL225'),

  /// `GQL226`: a variable whose type is not an input type (spec §5.8.2).
  variablesAreInputTypes('GQL226'),

  /// `GQL227`: a variable an operation uses, directly or through
  /// fragments, without declaring it (spec §5.8.3).
  noUndefinedVariables('GQL227'),

  /// `GQL228`: a variable an operation declares and never uses, directly or
  /// through fragments (spec §5.8.4).
  noUnusedVariables('GQL228'),

  /// `GQL229`: a variable used where its type is not allowed, or a nullable
  /// variable used for a field of a `@oneOf` input object (spec §5.8.5).
  variablesInAllowedPosition('GQL229'),

  /// `GQL230`: validating a document needed more work than the
  /// validator's step budget allows, such as fragments that expand to
  /// more fields than the budget, or many operations each spreading a
  /// long chain of fragments. Validation stops there.
  documentTooComplex('GQL230'),

  /// `GQL231`: a problem a custom validation rule reports (R3.6); its
  /// message says what the rule checks.
  customRuleViolation('GQL231'),

  /// `GQL232`: an operation whose deepest field, fragments expanded, is
  /// deeper than the maximum `MaxDepthRule` allows.
  maxDepthExceeded('GQL232'),

  /// `GQL233`: an operation with more aliased fields, fragments expanded,
  /// than the maximum `MaxAliasesRule` allows.
  maxAliasesExceeded('GQL233'),

  /// `GQL234`: an operation with more directives, fragments expanded, than
  /// the maximum `MaxDirectivesRule` allows.
  maxDirectivesExceeded('GQL234'),

  /// `GQL235`: a field that returns an introspection type, such as
  /// `__schema`, in a document checked by `NoIntrospectionRule`.
  introspectionDisabled('GQL235'),

  /// `GQL236`: a `__schema` or `__type` field with a path through three or
  /// more of `fields`, `interfaces`, `possibleTypes` and `inputFields`,
  /// fragments expanded (`MaxIntrospectionDepthRule`).
  maxIntrospectionDepthExceeded('GQL236'),

  /// `GQL237`: a field with `@listSize(slicingArguments:)` that is not given
  /// exactly one of its slicing arguments (`SlicingArgumentsRule`).
  slicingArgumentsRequired('GQL237'),

  /// `GQL238`: an operation whose field cost or type cost is more than the
  /// maximum `MaxCostRule` allows.
  maxCostExceeded('GQL238'),

  /// `GQL500`: a `typed_graphql.yaml` that is not valid YAML; the message is
  /// the YAML parser's.
  configSyntax('GQL500'),

  /// `GQL501`: a missing, unknown or mistyped key, or a malformed path or Dart
  /// reference, in the code generator's configuration.
  invalidConfig('GQL501'),

  /// `GQL502`: a schema file the code generator cannot read as a schema: not
  /// JSON, or JSON that is not an object.
  invalidSchemaInput('GQL502'),

  /// `GQL503`: an operation without a name in a document the code generator
  /// reads; its classes are named after the operation.
  anonymousOperation('GQL503'),

  /// `GQL504`: a construct the code generator does not support yet: `@defer`,
  /// `@stream`, an introspection field (`__schema`, `__type`), or a
  /// subscription root that spreads (directly or inside an inline fragment) a
  /// fragment which plans as a sealed base class; it would need `__typename`,
  /// which a subscription cannot select. A plain inline fragment is fine.
  unsupportedInDocument('GQL504'),

  /// `GQL505`: the configuration maps a scalar the schema does not have as a
  /// custom scalar: unknown, not a scalar, or built in.
  unknownScalarMapping('GQL505'),

  /// `GQL506`: no document matches the configuration's `documents`; reported
  /// as a warning.
  noDocuments('GQL506'),

  /// `GQL507`: the code generator would declare one Dart name twice, such as
  /// an enum `Role` and an input object `RoleKnown`, two members of one
  /// generated class, or two generated files at one path; reported at the
  /// second declaration, related to the first.
  generatedNameCollision('GQL507'),

  /// `GQL508`: a name the code generator would declare hides a Dart type the
  /// generated code uses, such as `List` or a `dart:core` type a scalar is
  /// mapped to.
  reservedTypeName('GQL508'),

  /// `GQL509`: `check` found a generated file that is missing or differs from
  /// what `generate` would write; reported without a span.
  outputOutdated('GQL509'),

  /// `GQL510`: a file the command line must read, such as the configuration,
  /// the schema or a document, or the schema URL, cannot be read; reported
  /// without a span.
  inputUnreadable('GQL510'),

  /// `GQL511`: an operation or fragment whose selections would make the code
  /// generator declare more classes than its fixed limit (10000); reported at
  /// the operation or fragment name.
  tooManyGeneratedClasses('GQL511'),
}
