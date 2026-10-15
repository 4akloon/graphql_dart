# M4 Operation validation: stage design

Status: written for the owner's review 2026-10-15 (the open questions are at
the end). Every decision below was checked by implementing both plans on a
scratch branch, one commit per plan task, with every suite green on the VM,
AOT, dart2js and dart2wasm. Refines section 3 "Operation validation" and section 5 "Cost
analysis" of [the architecture](2026-10-13-typed-graphql-design.md) and never
overrides them silently. Deviations from it are listed in section 14.
Requirements: R0.3, R0.5, R0.7, R3.1–R3.6, R3.8, R10.3, R10.4, R11.1–R11.3
([requirements](../../requirements.md)).

## 1. Scope and delivery

M4 builds the `validation/` layer of `packages/typed_graphql` and grows
`packages/typed_graphql_conformance`. One spec, **two plans**, merged one after
the other:

| Plan | Content |
|---|---|
| **M4a** | The rule framework (`ValidationRule`, `ValidationContext`, `TypeInfo`, `DocumentValidator`, the sealed `DocumentValidationResult` with `ValidDocument` / `InvalidDocument`); the 30 rules of Section 5 with `GQL200`–`GQL229`; the step budget (`GQL230`) and the custom-rule code (`GQL231`); conformance table `mapping/validation.csv` and the ported graphql-js rule suites; the hostile-document tests of section 9; the Validation guide, its dartdoc category, the example, README, CHANGELOG, `CLAUDE.md` |
| **M4b** | The opt-in limit rules (`MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule`); the opt-in built-in `@cost` / `@listSize` directives with their schema checks; the `CostAnalysis` and the `MaxCostRule`; the document fuzzers; the guide's "Limits" and "Cost" sections |

Out of scope: the `@defer` / `@stream` rules (R3.7, M14), fragment arguments
(roadmap "Later"), `NoDeprecatedCustomRule` (open question 5), the SDL
validation rules of graphql-js (`validateSDL`: M3's `SchemaBuilder` and
`SchemaValidator` own them), coercion of variable values (M5).

## 2. Layering

`validation/` is the top core layer (diagnostics < language < protocol <
schema < validation). It may import every lower layer and imports no platform
library and no package but `meta`. Folders:

| Folder | Holds |
|---|---|
| `validation/` | `DocumentValidator`, `DocumentValidationResult`, `ValidationRule`, `ValidationContext`, `TypeInfo`, `VariableUsage`, the walk and the usage index |
| `validation/rules/` | the 30 rule classes and their private collaborators |
| `validation/overlap/` | the collaborators of `OverlappingFieldsCanBeMergedRule` (section 6) |
| `validation/limits/` | the M4b limit rules |
| `validation/cost/` | `CostAnalysis`, `MaxCostRule` and their collaborators |

The did-you-mean suggestions (graphql-js's `suggestionList`, `didYouMean`,
`LexicalDistance`, `naturalCompare`, `orList`) are message text, so they live
in `diagnostics/` as the internal `Suggestions`; `schema/validation/`'s value
checker uses them too (section 5, `ValuesOfCorrectTypeRule`).

## 3. Framework (M4a; R3.2, R3.4, R3.6)

**Rules.** `abstract class ValidationRule` is a const, configurable value with
one method, `AstVisitor createVisitor(ValidationContext context)`. A run asks
every rule for a fresh visitor, so a rule object holds configuration only
(`MaxDepthRule(maxDepth: 10)`) and is shared between runs and isolates. A
visitor overrides `enter` / `leave` and tells nodes apart with a `switch` over
the sealed node families. This is the custom-rule API (R3.6): a custom rule is
a `ValidationRule` like the built-in ones and reports through the context.

**One walk** (R3.2). `DocumentValidator.validate` walks the document once with
`AstWalker` and a `ValidationWalk` visitor that:
- updates `TypeInfo` before the rules enter a node and after they leave it, as
  graphql-js's `visitWithTypeInfo` does (and leaves it at once when every rule
  skips the node);
- passes the node to a `ParallelVisitor` of the internal `UsageIndex`
  (first) and the rules' visitors, in the rules' order;
- does not walk the descriptions of operations, fragments and variable
  definitions (spec §2.2: they do not change the meaning of a document;
  graphql-js's `validate` sees none, since its `parse` drops them by
  default), so a custom rule never meets a description;
- returns `VisitAction.stop` once the context is aborted (the error limit or
  the step budget is reached), as graphql-js aborts at `maxErrors`.

**`TypeInfo`** (public; graphql-js's `TypeInfo`): the output type
(`TypeRef? type`), the composite `parentType`, the `fieldDefinition`, the input
type and its parent (`inputType`, `parentInputType`), the location's
`defaultValue`, the current `directive`, `argument` and `enumValue`, kept as
stacks and updated by `enter(Node)` / `leave(Node)`. Root types and inline
fragments without a type condition get a synthesized `NamedType`. The
meta-fields `__typename`, `__schema` and `__type` resolve to field definitions
of the internal `MetaFields` (`__schema` and `__type` only on the query root,
as graphql-js's `getFieldDef`).

**`ValidationContext`** (public, made by the validator for each run):
`schema`, `document`, `typeInfo`, `includesSuggestions`; `report(code,
message, nodes)`, which makes an error diagnostic at the first node with the
other nodes as related spans (spans only when the run has a `Source`);
`isAborted`; `spend(steps)` for the step budget (section 8);
`fragmentNamed(name)`; and, from `leave(Document)` on, the usage index:
`variableUsagesOf(definition)`, `recursiveVariableUsages(operation)` and
`recursivelyReferencedFragments(operation)`. `VariableUsage` is graphql-js's
record: the `Variable` node, its input `type`, its `parentType` and the
location's `defaultValue`.

The usage index replaces graphql-js's re-walks: `UsageIndex` records, during
the one walk, each executable definition's variable usages (with `TypeInfo`'s
input type at the variable) and its fragment spreads. Rules that need the
closure of an operation (graphql-js does it at `leave(OperationDefinition)`,
re-walking fragments that may come later in the document) do it at
`leave(Document)`, operations in document order.

**Validator and result** (R3.4).

```dart
const DocumentValidator({
  List<ValidationRule> rules = DocumentValidator.recommendedRules,
  int maxErrors = 100,          // graphql-js's maxErrors
  bool includesSuggestions = true,  // graphql-js's !hideSuggestions (R5.15)
  int maxSteps = ValidationContext.defaultMaxSteps,  // 1 000 000
});
DocumentValidationResult validate(ValidSchema schema, Document document,
    {Source? source});
```

`DocumentValidationResult` is sealed: `ValidDocument` | `InvalidDocument`. Both
hold the `ValidSchema` and the `Document`; `InvalidDocument` holds the
diagnostics. `ValidDocument` has a private constructor: only `validate` and
`ValidDocument.assumeValid(schema, document)` (for trusted documents, as
`ValidSchema.assumeValid`) make one. The executor (M5) compares
`validDocument.schema.schema` with its own schema by identity and throws
`ArgumentError` on a mismatch. `specifiedRules` is the 30 rules in graphql-js's
`specifiedRules` order without the defer/stream rules, each split rule right
after the rule it was split from. `recommendedRules` (M4b) is
`specifiedRules` followed by `MaxIntrospectionDepthRule`, graphql-js's
recommended set and the default (open question 2, owner answer). Bad
input never throws (R0.3); a rule that throws is a bug.

## 4. Diagnostics

One code per rule of Section 5, in spec order, each with its spec section in
the doc comment; the message is graphql-js's text where graphql-js has the
check, so the ported suites compare messages unchanged.

| Code | Spec | Rule class |
|---|---|---|
| `GQL200` | §5.1.1 Executable Definitions | `ExecutableDefinitionsRule` |
| `GQL201` | §5.2.1.1 Operation Type Existence | `KnownOperationTypesRule` |
| `GQL202` | §5.2.2.1 Operation Name Uniqueness | `UniqueOperationNamesRule` |
| `GQL203` | §5.2.3.1 Lone Anonymous Operation | `LoneAnonymousOperationRule` |
| `GQL204` | §5.2.4.1 Single Root Field | `SingleFieldSubscriptionsRule` |
| `GQL205` | §5.3.1 Field Selections | `FieldsOnCorrectTypeRule` |
| `GQL206` | §5.3.2 Field Selection Merging | `OverlappingFieldsCanBeMergedRule` |
| `GQL207` | §5.3.3 Leaf Field Selections | `ScalarLeafsRule` |
| `GQL208` | §5.4.1 Argument Names | `KnownArgumentNamesRule` |
| `GQL209` | §5.4.2 Argument Uniqueness | `UniqueArgumentNamesRule` |
| `GQL210` | §5.4.3 Required Arguments | `ProvidedRequiredArgumentsRule` |
| `GQL211` | §5.5.1.1 Fragment Name Uniqueness | `UniqueFragmentNamesRule` |
| `GQL212` | §5.5.1.2 Fragment Spread Type Existence | `KnownTypeNamesRule` |
| `GQL213` | §5.5.1.3 Fragments on Object, Interface or Union Types | `FragmentsOnCompositeTypesRule` |
| `GQL214` | §5.5.1.4 Fragments Must Be Used | `NoUnusedFragmentsRule` |
| `GQL215` | §5.5.2.1 Fragment Spread Target Defined | `KnownFragmentNamesRule` |
| `GQL216` | §5.5.2.2 Fragment Spreads Must Not Form Cycles | `NoFragmentCyclesRule` |
| `GQL217` | §5.5.2.3 Fragment Spread Is Possible | `PossibleFragmentSpreadsRule` |
| `GQL218` | §5.6.1 Values of Correct Type | `ValuesOfCorrectTypeRule` |
| `GQL219` | §5.6.2 Input Object Field Names | `InputObjectFieldNamesRule` |
| `GQL220` | §5.6.3 Input Object Field Uniqueness | `UniqueInputFieldNamesRule` |
| `GQL221` | §5.6.4 Input Object Required Fields | `InputObjectRequiredFieldsRule` |
| `GQL222` | §5.7.1 Directives Are Defined | `KnownDirectivesRule` |
| `GQL223` | §5.7.2 Directives Are in Valid Locations | `DirectivesInValidLocationsRule` |
| `GQL224` | §5.7.3 Directives Are Unique per Location | `UniqueDirectivesPerLocationRule` |
| `GQL225` | §5.8.1 Variable Uniqueness | `UniqueVariableNamesRule` |
| `GQL226` | §5.8.2 Variables Are Input Types | `VariablesAreInputTypesRule` |
| `GQL227` | §5.8.3 All Variable Uses Defined | `NoUndefinedVariablesRule` |
| `GQL228` | §5.8.4 All Variables Used | `NoUnusedVariablesRule` |
| `GQL229` | §5.8.5 All Variable Usages Are Allowed | `VariablesInAllowedPositionRule` |
| `GQL230` | — | the step budget was spent (section 8) |
| `GQL231` | — | reported by a custom rule (R3.6) |

M4b adds, for the opt-in rules (sections 10 and 11):

| Code | Name | Reported by |
|---|---|---|
| `GQL232` | `maxDepthExceeded` | `MaxDepthRule` |
| `GQL233` | `maxAliasesExceeded` | `MaxAliasesRule` |
| `GQL234` | `maxDirectivesExceeded` | `MaxDirectivesRule` |
| `GQL235` | `introspectionDisabled` | `NoIntrospectionRule` |
| `GQL236` | `maxIntrospectionDepthExceeded` | `MaxIntrospectionDepthRule` |
| `GQL237` | `slicingArgumentsRequired` | `SlicingArgumentsRule` |
| `GQL238` | `maxCostExceeded` | `MaxCostRule` |

and, for the schema checks of the cost directives (a type-system problem,
reported by `SchemaValidator`): `GQL156` `invalidCostWeight`, `GQL157`
`misplacedCost`, `GQL158` `listSizeOnNonList`, `GQL159`
`invalidSlicingArgument`, `GQL160` `invalidSizedField`, `GQL161`
`conflictingAssumedSize`. `GQL000` is the error limit as everywhere.

## 5. The 30 rules (M4a; R3.1)

Each rule is a class in `validation/rules/` named as graphql-js names it, so the
ported suites and users' knowledge carry over; the doc comment names the spec
section. graphql-js folds four spec rules into others; M4 splits them out, so
there are exactly 30 classes:

- §5.6.2 and §5.6.4 are in graphql-js's `ValuesOfCorrectTypeRule` (through
  `validateInputLiteral`). `InputObjectFieldNamesRule` reports the unknown
  fields and `InputObjectRequiredFieldsRule` the missing required fields;
  `ValuesOfCorrectTypeRule` keeps the rest (leaf values, non-null, lists,
  objects, OneOf). The three ask the shared `ValueChecker` and keep the
  problems of their kind.
- §5.7.2 is in graphql-js's `KnownDirectivesRule`; `DirectivesInValidLocationsRule`
  reports the misplaced directives.
- §5.5.1.2 is graphql-js's `KnownTypeNamesRule`, which also reports unknown
  variable types; the class keeps that (graphql-js's
  `VariablesAreInputTypesRule` skips unknown types, so nothing is reported
  twice).

Each rule reports in graphql-js's order for that rule. The rules that need an
operation's closure (`NoUndefinedVariablesRule`, `NoUnusedVariablesRule`,
`VariablesInAllowedPositionRule`) and `OverlappingFieldsCanBeMergedRule` report
at `leave(Document)`; diagnostics of different rules are therefore not always
interleaved as graphql-js interleaves them (deviation 3).

`ValuesOfCorrectTypeRule` and its two siblings check a value where it starts
(an argument, a variable's default value) with the M3b `ValueChecker`, which
gains three options: variables are allowed (graphql-js's static
`validateInputLiteral`), did-you-mean suggestions for unknown input fields and
enum values, and a kind on each `ValueProblem`. Suggestions everywhere follow
`includesSuggestions`.

## 6. Field selection merging (M4a; R3.3)

graphql-js compares fields pairwise, quadratic in a selection set (#2185), and
checks every fragment again at every spread. M4 uses the Sangria / XING
decomposition, which is linear in the size of the document with its fragments
expanded once per root. The code is in `validation/overlap/`.

- **Origins and roots.** During the walk the rule records, for each `Field`, a
  `FieldOrigin`: its parent type (`TypeInfo.parentType`). The work runs at
  `leave(Document)` (`FieldMerging`), one root at a time in document order: each
  operation, and each fragment definition that no earlier root expanded. A
  fragment's own conflicts are found wherever it is expanded, so a chain of
  100000 fragments is merged once, not once per link (3n steps instead of
  n²/2).
- **Items and work.** A `MergeItem` is a field node with its definition, its
  parent item and its `FragmentTrail`, the fragments spread on the way to it
  from its collection level (a persistent linked list, so a 100000-deep chain
  costs linear memory). `SelectionCollector` groups the items of some selection
  sets by response name: the sets' own fields and inline fragments first,
  depth first, then each spread fragment, depth first, each at most once per
  collection and never one already on the path (a recursive spread ends there).
  A group of items is one `MergeWork`.
- **Two checks per work** (`MergeSplit`). *Same response shape*: items are
  classed by `FieldShape` (list and non-null wrappers and the leaf type name,
  or `{}` for a composite; an item without a definition joins every class).
  *Same for common parents*: items are split by concrete parent type, an
  abstract parent joining every group, and in a group classed by field name
  and `ArgumentText` (a canonical text: sorted arguments and object fields,
  built without recursion). Each item is paired with the first item of every
  other class seen before it, so the pairs are linear. When both checks keep
  the work whole, its sub-selections are collected once; otherwise the
  name-check parts and the shape-check parts descend separately. An explicit
  stack of steps (enter fragments, visit work, leave fragments) replaces
  recursion.
- **Judging a pair** (`ConflictJudge`). The two chains are followed up to the
  nearest pair of distinct ancestors (graphql-js's "nearest common ancestor").
  A pair below ancestors that already differ in name or arguments is dropped
  (graphql-js does not compare their subfields). Exclusivity (different object
  parents) accumulates down the chain and turns off the name and arguments
  checks, as in graphql-js. The reason follows graphql-js's precedence: field
  name, arguments, return types (printed by the language `Printer`). Pairs are
  deduplicated by their unordered pair of top fields over the whole run.
- **Reporting as graphql-js** (`ConflictTree`, `ConflictReports`). Conflicts
  under one top pair form one diagnostic: the nested `subfields "x" conflict
  because …` reasons joined by " and ", the locations of the first chain then
  of the second. A conflict's position is the selection set where graphql-js
  finds it: the innermost fragment both fields are spread through, else their
  parent field's selection set, else the root's. All reports are flushed once
  at the end, ordered by position and then by discovery; definitions do not
  overlap, so this also orders them by definition. Reporting stops once
  `maxErrors` conflicts are known (`ValidationContext.maxErrors`).
- **Bounds.** Each collected item and each judged chain step is charged to the
  step budget (section 8): a document whose fragments expand exponentially
  ends with `GQL230`, not a hang. The subfields of a field that is alone in
  its set are descended once per root and check kind, wherever the field is
  reached from (the pairs under it have their nearest distinct ancestors
  below it), unless a cyclic fragment is on the path; so `p: a { ...F }
  q: b { ...F }` over 20 levels is merged in linear steps and is valid.
  The memo covers lone fields only: a part that repeats a response name
  beside its spreads (`fragment G_i on Node { p: child { ...G_next }
  p: child { ...G_next } q: child { ...G_next } q: child { ...G_next } }`)
  fans out through parts that are not alone, and from about 18 levels it
  ends with `GQL230` (section 8, deviation 15).

Conflicts come in graphql-js's order in the common cases; with three or more
fields of one name in conflict the count differs (deviation 4; one adapted
row). The `@stream` checks wait for M14.

## 7. Complexity and recursion (R0.3, R3.3)

Every rule is linear in the document, with three exceptions that are linear in
the document with its fragments expanded: the operation closures
(`recursiveVariableUsages`, `recursivelyReferencedFragments`; graphql-js
has the same cost) and field selection merging. These charge the step budget.

No rule recurses over the document: the walk is `AstWalker`'s, fragment
closures, cycle detection (`NoFragmentCyclesRule`), the value checker and the
canonical argument text run over explicit stacks. A document built in code may
be nested 100000 deep; validating it may not overflow the stack on the web.

## 8. Step budget

`DocumentValidator.maxSteps` (default 1 000 000) bounds the work beyond one
walk. `ValidationContext.spend(steps)` charges it; when it is spent the context
reports one `GQL230` "The document is too complex to validate: it needs more
than N steps." at the document and aborts the run, which is then an
`InvalidDocument`. The default is measured, not guessed: the VM does about
1.2 million steps a second, so the budget bounds a run near one second (a
10 000 000 budget let the 2^60 hostile document run 10.9 s). The budget exists for
documents built in code, parsed without limits, or shaped to expand
exponentially through fragments. Within the parser's default limits a
document stays below it except in one shape: the field merging memoises the
subfields of a field that is alone in its set, so a fragment spread under
two fields over 25 levels is merged in linear steps, but a fan-out through
parts that repeat a response name (`fragment G_i on Node { p: child
{ ...G_next } p: child { ...G_next } q: child { ...G_next } q: child
{ ...G_next } }`, about 18 levels or more) still spends the budget and ends
with `GQL230`. This is an honest, bounded limit, not a hang.

## 9. Hostile documents (R0.3)

`packages/typed_graphql/test/validation/hostile_*_test.dart` run on the VM, AOT,
dart2js and dart2wasm. Each builds its document in code (the parser's `maxDepth`
would refuse it) or parses it without limits, and asserts both the result and
a `Stopwatch` bound of 10 s, where a naive (graphql-js-like) algorithm takes
minutes or overflows:

- selections, an input object and a list nested 100000 deep: valid or the
  expected diagnostics, no stack overflow;
- a chain of 100000 fragments is valid (merged once, section 6);
- 100000 aliases, conflicting fields of one response name, directives,
  repeated arguments, variables, operations and spreads;
- 1000 operations each spreading one chain of 1000 fragments spend the budget
  (`GQL230`); fragments that expand to 2^60 fields through lone fields are
  merged in near-linear steps and are valid, while a fan-out through parts
  that repeat a response name ends with `GQL230` (section 8).

The M4b fuzzers (section 12) repeat these shapes with random sizes and every
opt-in rule on.

## 10. Limit rules (M4b; R3.5)

Opt-in `ValidationRule`s in `validation/limits/`, none in `specifiedRules`:

- `MaxDepthRule(maxDepth:)` (`GQL232`): a top-level field has depth 1, a field
  in its selection set depth 2; inline fragments and spreads add none;
  introspection fields count. `The operation "Q" has a depth of 12, more than
  the maximum of 10.`
- `MaxAliasesRule(maxAliases:)` (`GQL233`): fields written with an alias.
  `The operation "Q" has more than 10 aliases.`
- `MaxDirectivesRule(maxDirectives:)` (`GQL234`): directives on the operation,
  its variable definitions, fields, inline fragments, spreads and, per spread,
  the spread fragment's definition. `The operation "Q" has more than 10
  directives.`
- `NoIntrospectionRule()` (`GQL235`): graphql-js's
  `NoSchemaIntrospectionCustomRule`, its message: a field whose named type is
  an introspection type; `__typename` stays allowed.
- `MaxIntrospectionDepthRule()` (`GQL236`): graphql-js's rule and message: below
  a `__schema` or `__type` field, no path may pass through 3 or more `fields`,
  `interfaces`, `possibleTypes` or `inputFields` fields.

An anonymous operation is "The anonymous operation". Counts and depths are per
operation with every spread expanded, as if each fragment were written where it
is spread. `SelectionMeasure` computes them for all five rules: an
explicit-stack fold over the selections, combining children by sum (counts) or
maximum (depths) per `MeasuredQuantity`, memoised per fragment, so a fragment
chain that expands 2^60 times costs one visit per fragment where graphql-js's
`MaxIntrospectionDepthRule` re-walks every expansion. Counts saturate at one
over the limit (the message says "more than"); an unknown fragment or a cycle
edge counts 0. Each selection visited charges the step budget. The three
counting rules report at the operation at `leave(Document)` (fragments may come
later), once per operation; the introspection rules report at the field during
the walk. A negative limit is a `RangeError` from `createVisitor` (a const
constructor cannot check it). "Tokens" are the parser's `maxTokens` (R1.6), not
a validation rule. R3.5's `MaxComplexity` is `MaxCostRule` (section 11;
deviation 6).

## 11. Cost analysis (M4b; R3.8)

The IBM GraphQL Cost Directives draft
(<https://ibm.github.io/graphql-specs/cost-spec.html>):

```graphql
directive @cost(weight: String!) on ARGUMENT_DEFINITION | ENUM | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | OBJECT | SCALAR
directive @listSize(assumedSize: Int, slicingArguments: [String!], sizedFields: [String!], requireOneSlicingArgument: Boolean = true) on FIELD_DEFINITION
```

- **Opt-in built-ins.** `SchemaBuilder(includesCostDirectives: true)` and
  `Schema(includesCostDirectives: true)`, everywhere `includesDeferAndStream`
  goes: `BuiltIns` (the internal `CostDirectiveSdl`), `Schema.directiveNamed`,
  `extend`, the printer with `includesBuiltIns`, the redefinition check, and
  introspection both ways (a `cost` or `listSize` directive in an answer turns
  the flag on). Without the flag `@cost` is an unknown directive, so schemas
  without it stay portable.
- **Schema checks** (`SchemaValidator`, only with the flag;
  `CostDirectiveRules` and `ListSizeRules`, after the other checks, in schema
  order, at the applied directive):
  - `GQL156` a weight that is not a GraphQL number:
    `The @cost weight "abc" of "Query.users" is not a number.`
  - `GQL157` `@cost` on an interface field or its argument (interfaces, unions
    and input object types are already outside the locations):
    `@cost cannot be applied to the interface field "Node.id".`
  - `GQL158` `@listSize` on a field that is not a list and has no
    `sizedFields`: `@listSize on "Query.user" requires a list field or sizedFields.`
  - `GQL159` a slicing argument that is not an `Int` or `Int!` argument of the
    field.
  - `GQL160` a sized field that is not a list field of the field's type.
  - `GQL161` `assumedSize` with slicing arguments, unless
    `requireOneSlicingArgument: false` and no slicing argument has a default.
- **`CostAnalysis(schema, {defaultListSize = 10})`** is const and makes one
  `CostWalk` per `costOf(document, operation, {variables})` call, which returns
  an `OperationCost(fieldCost, typeCost)` (doubles). The contract:
  - *type weight*: the type's `@cost`, else 1 for an object, 0 for a scalar or
    an enum; an interface or a union weighs its heaviest possible type; an
    input object 0;
  - *field weight*: the field's `@cost`, else its type's weight; *argument
    cost*: each given argument's `@cost` (else its type's weight) plus the
    input fields written in its value, at any depth; *directive cost*: the
    argument cost of the directives on the field; *raw cost*:
    `max(0, field weight + argument cost + directive cost)`;
  - *list size* of a list field: the largest slicing argument given (a
    variable takes its value from `variables`, else its default, else
    `defaultListSize`), else the largest slicing argument default, else
    `assumedSize`, else `defaultListSize`; a non-list field 1; with
    `sizedFields` the field itself is 1 and the named children take the size;
  - *field cost* of a selection set: the sum over its fields of
    `raw + size × field cost of the field's selections`; *type cost*: the sum
    of `size × (type weight + type cost of the selections)`, plus the root
    type's weight for the operation;
  - fragments and inline fragments add their selections (an upper bound);
    meta-fields and unknown fields cost 0 and their selections are not counted;
  - the costs of a fragment's selections are memoised per (fragment, sized
    context), so the analysis is polynomial in the fragments times the contexts
    (a `sizedFields` list creates one) even when fragments expand 2^60 times;
    it uses explicit stacks and charges each selection walked to the step
    budget; weights are parsed once per run (`CostRun`) and an unparsable
    weight counts as the default; `@cost` and `@listSize` count only when the
    schema has the directive (the built-in one under `includesCostDirectives`,
    or one declared in SDL).
- **`SlicingArgumentsRule`** (`GQL237`): with `requireOneSlicingArgument` (the
  default), a field with slicing arguments must be given exactly one of them,
  not as a `null` literal: `Field "users" must be given exactly one of its
  slicing arguments "first" or "last", but it was given 0.`
- **`MaxCostRule(maxCost:, {defaultListSize = 10})`** (`GQL238`): at
  `leave(Document)`, an operation whose field cost or type cost exceeds
  `maxCost` is reported at the operation: `The operation "Q" has a field cost
  of 1200 and a type cost of 300, more than the maximum of 1000.` Numbers print
  the same on every platform: integral values below 1e15 without a fraction,
  fractions as written, larger values in exponential form
  (`1.152921504606847e+18`), since the VM and JavaScript print large doubles
  differently. Validation has no variable values: a slicing variable counts
  with its default (open question 4).

## 12. Conformance and fuzzing (R0.7, R10.3, R10.4)

- `mapping/validation.csv` lists every test of every file in graphql-js's
  `src/validation/__tests__/` (the coverage test of M2 is extended to it, and
  reads double-quoted test names too), with the M2 statuses. `skipped`: the SDL
  rule suites (M3 covers them through `SchemaBuilder` / `SchemaValidator`), the
  defer/stream suites and the `@stream` merging tests (M14), fragment arguments
  (roadmap "Later"), `NoDeprecatedCustomRule` (open question 5), checks of
  JavaScript internals with no Dart counterpart (Node's `diagnostics_channel`
  tracing, `Object.prototype.toString`), and custom scalars whose graphql-js
  coercion functions a schema built from SDL does not have (R2.9).
- The ported suites live in `test/validation/`, one Dart test per graphql-js
  test with the same name, over `RulePort` (`test/support/rule_port.dart`) with
  graphql-js's test schema (`harness.ts`) built from its SDL; `RulePort.all`
  runs the rules a split graphql-js rule became together. Errors print as `message @
  line:column …`, as M3b's port prints them. `validate_test.dart` ports
  `validation-test.ts` (custom rules, `maxErrors`, a throwing rule).
- M4b fuzzers in `test/fuzz/`: (1) `valid_operation_fuzz_test.dart`: random
  operations generated by `RandomOperation` against a random schema that is
  valid by construction (`RandomValidSchema`; M3's generator rarely produces a
  valid schema) are valid; (2) `hostile_operation_fuzz_test.dart`: random and
  token-mutated documents never throw and yield at most `maxErrors + 1`
  diagnostics with every specified, recommended, limit and cost rule on;
  (3) `hostile_shape_fuzz_test.dart`: deep, wide, chained, fanned and cyclic
  shapes with random sizes end within 10 s, and a fan that exceeds the budget
  yields `GQL230`.

## 13. Documentation (R11.1–R11.3)

A Validation guide `packages/typed_graphql/doc/validation.md` (M4a: validating
a document, reading the result, the rules and their codes, custom rules,
suggestions and limits of a run; M4b: "Limits" and "Cost"), the `validation`
dartdoc category ("Operation Validation"), a `{@category validation}` tag on
every new exported type, a compiling snippet in `example/`, the README feature
list and Documentation section, the package CHANGELOG, `CLAUDE.md` (a
"Validation" paragraph in Architecture) and the handoff.

## 14. Deviations from the architecture spec

1. The 30 rules include two graphql-js rules split into five classes
   (`ValuesOfCorrectTypeRule` into §5.6.1, §5.6.2 and §5.6.4;
   `KnownDirectivesRule` into §5.7.1 and §5.7.2) so that each spec rule is
   one class and one code (section 5).
2. The limit and cost rules are `ValidationRule`s too, configured by their
   constructor; the architecture spec named them only.
3. Rules that need an operation's fragment closure report at
   `leave(Document)`, so the overall order of diagnostics differs from
   graphql-js's interleaving; the order within one rule is graphql-js's.
4. `OverlappingFieldsCanBeMergedRule` reports each conflicting pair once,
   against the first member of each other class, and in visit order: with three
   or more conflicting fields of one name, the count and order of its
   diagnostics differ from graphql-js's pairwise report (adapted rows).
5. The step budget and `GQL230` are new: graphql-js has no bound on validation
   work.
6. R3.5's `MaxComplexity` is `MaxCostRule` over the IBM directives (R3.8); a
   second, per-field complexity model would be redundant.
7. `SlicingArgumentsRule` is a separate opt-in rule (`GQL237`); the IBM draft
   lists it as a validation rule of the directives.
8. Did-you-mean text lives in `diagnostics/` (`Suggestions`), and M3b's value
   checker now suggests enum values and input fields, as graphql-js's
   `validateInputLiteral` does; M3's schema validation keeps suggestions off.
9. `EngineOrderedSort` reproduces the order V8's sort gives graphql-js's
   suggestions, so did-you-mean lists match graphql-js's character for
   character.
10. Directive definitions written in an executable document are not
    collected by `KnownDirectivesRule` (graphql-js collects them, for its
    SDL mode); an executable document cannot hold one anyway
    (`ExecutableDefinitionsRule` reports it).
11. Descriptions of operations, fragments and variable definitions are not
    walked (section 3).
12. `OverlappingFieldsCanBeMergedRule` checks a fragment where an earlier
    root expanded it, not again on its own (section 6): the conflicts are the
    same, found once. A fragment on a cycle is not expanded below itself, so
    in a document with fragment cycles (invalid anyway, `GQL216`) it may miss
    a conflict graphql-js finds; it never reports one that is not there.
13. Limit counts and introspection depth are memoised per fragment, so they
    are linear where graphql-js's `MaxIntrospectionDepthRule` is exponential;
    cost is memoised per fragment and sizing context, so it is polynomial in
    their product (sections 10 and 11).
14. "Did you mean" suggestions are skipped for an input longer than 256
    UTF-16 code units (`Suggestions.maxInputLength`): graphql-js measures
    any length, which lets one hostile name make every error cost its
    length.
15. The field-merging memo covers fields alone in their set only: a part that
    repeats a response name and fans out through fragments (about 18 levels
    of four spreads) still ends with `GQL230` where graphql-js, with no
    bound, would take exponential time (section 8).

## 15. Open questions for the owner

1. **The step budget** (section 8): keep `maxSteps` with a default of
   1 000 000 and `GQL230`? Recommendation: yes. Without it a 15 000-token
   document can spend minutes in fragment closures, which the server's limits
   (M6) cannot see; the default is about one second of work on the VM.
2. **`MaxIntrospectionDepthRule` by default?** graphql-js puts it in
   `specifiedRules` (as a "recommended" rule). The plans add
   `DocumentValidator.recommendedRules` (= specified + it) and keep
   `specifiedRules` the default. Recommendation: make `recommendedRules` the
   default (a one-line change in `DocumentValidator`), since the rule only
   rejects introspection queries no tool sends. Accepted by the owner
   (2026-10-15): `recommendedRules` is the default.
3. **Public rule classes.** Recommendation: export all 30 (graphql-js does;
   the conformance package needs them, and users compose lists). The plans do.
4. **Variables in cost** (section 11): a slicing argument given by a variable
   counts with its default, else `defaultListSize` (validation has no values).
   Recommendation: yes, and the server (M6) re-runs `CostAnalysis` with the
   coerced values through `costOf(variables:)`.
5. **`NoDeprecatedCustomRule`** (graphql-js custom rule, not in R3): port it in
   M4b? Recommendation: no; it is a lint for client codegen (M10 can add it as
   a warning rule).
6. **`defaultListSize` = 10** for a list field without `@listSize` (the draft
   leaves it to the implementation). Recommendation: keep 10, configurable per
   `CostAnalysis` and `MaxCostRule`; the server profile (M6) may pick its own.
7. **Fragments in cost add up** (an upper bound: two inline fragments on
   different possible types both count, and the type cost counts the root
   type). Recommendation: keep; a per-possible-type maximum is exact but costs
   a walk per possible type.
8. **Fewer overlap reports than graphql-js** with three or more conflicting
   fields of one name (deviation 4). Recommendation: accept; every conflicting
   field is still reported at least once.

