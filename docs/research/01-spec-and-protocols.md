# 01. GraphQL specifications and protocols

Date: 2026-10-13. Scope: the GraphQL Foundation specification family (language,
type system, validation, execution, introspection, response format, incremental
delivery) across its newest released edition, its predecessor, and the current
working draft, plus every transport and ecosystem protocol relevant to a
from-scratch, fully-typed Dart GraphQL implementation (GraphQL-over-HTTP,
graphql-ws, graphql-sse, legacy `subscriptions-transport-ws`, multipart file
upload, Automatic Persisted Queries, Relay, Apollo Federation v2, and the
GraphQL Foundation's own vendor-neutral Federation spec). Method: direct
line-by-line inspection and diffing of the primary sources cloned locally into
`reference/` by `tool/fetch_reference.sh` (every git SHA below is from that
checkout, captured 2026-10-13); cross-checked against `graphql-js` (the
reference implementation) `src/validation/rules/` and `src/execution/` for
what actually ships versus what the spec text mandates. All file paths below
are relative to the repository root; `reference/` is git-ignored and must be
populated by running `tool/fetch_reference.sh` before these citations resolve
on disk.

## 0. In brief

1. The newest **released** edition is **September2025** (`reference/graphql-spec-September2025`, tag `September2025`, commit `89d93eb`, cut 2025-09-03), superseding **October2021** (`reference/graphql-spec-October2021`, commit `51337a9`, 2021-10-26). The **working draft** (`reference/graphql-spec-main`, commit `3f1ef84`, 2026-09-28) is ahead of September2025 with further unreleased changes.
2. October2021 → September2025's headline additions (`reference/graphql-spec-September2025/changelogs/September2025.md`): **`@oneOf` input objects** (PR #825), **Schema Coordinates** (PR #794), **descriptions on executable documents/operations** (PR #1170), **broader deprecation** — `@deprecated` now valid on field arguments, directive arguments and input fields (PRs #805, #1040, #1053, #1142), and **full-Unicode source text** (PR #849, `SourceCharacter` no longer restricted to the Basic Multilingual Plane).
3. September2025 → `main` (working draft, not yet released) adds: **empty selection sets** (`SelectionSet : { Selection* }` replacing `{ Selection+ }`, Section 2 L386 vs `+`), **OneOf inhabitability** via a new `InputObjectHasUnbreakableCycle()` algorithm (Section 3 L1785-1817, replacing a cruder "no direct self-reference" rule), **directive extensions** (`extend directive @Name ...`, new `DirectiveExtension` grammar, Section 3 L2369+), **`@deprecated` valid on `DIRECTIVE_DEFINITION`** plus the matching new `__DirectiveLocation.DIRECTIVE_DEFINITION` enum value, and a **new `__Schema.directives(includeDeprecated:)` argument** plus **new `__Directive.isDeprecated`/`deprecationReason`** fields.
4. A genuine **erratum was found and fixed between editions**: in the September2025 release itself, `Section 4 -- Introspection.md` already specifies `includeDeprecated: Boolean!` (non-null) for `fields`/`enumValues`/`inputFields`/`args`, but `Appendix D -- Specified Definitions.md` (a convenience appendix restating the same SDL) still showed the old nullable `Boolean = false` — an internal inconsistency inside September2025, corrected in `main` (confirmed by diffing both files against each other within the same edition and across editions).
5. **graphql-js v17 is released** (`reference/graphql-js`, tag `v17.0.2`, commit `7160…`, 2026-07-03). `@defer`/`@stream` and `experimentalExecuteIncrementally()` ship but remain **experimental/opt-in** — not in `specifiedDirectives`/`specifiedRules` as spec-required — because Incremental Delivery itself is still RFC Stage 2/Draft (`graphql-spec#1110`), not merged into `graphql-spec`. graphql-js even ships four validation rules (`DeferStreamDirectiveOnRootFieldRule`, `DeferStreamDirectiveOnValidOperationsRule`, `DeferStreamDirectiveLabelRule`, `StreamDirectiveOnListFieldRule`) for directives that **do not appear anywhere in Section 5 Validation of either spec edition on disk** — treat these as optional/experimental, not core compliance.
6. Section 5 (Validation) defines **30 leaf validation rules** (34 if the four explanatory sub-cases of "Fragment Spread Is Possible" are counted independently) — see §5 below for the full numbered table with `graphql-js` rule-file mapping. The only Section-5 change between September2025 and `main` is the empty-selection-set wording in "Leaf Field Selections" (5.3.3); no rules were added or removed.
7. **Incremental delivery's current response shape** (graphql-js v17, "current"/non-legacy format) uses `pending`/`incremental`/`completed`/`hasNext` entries, replacing the older per-patch `path`+`label`+`data` legacy shape (still reachable via `legacyExecuteIncrementally` in graphql-js). The transport-level envelope (`multipart/mixed` over chunked HTTP) is itself only an RFC (`reference/graphql-over-http/rfcs/IncrementalDelivery.md`), not part of the ratified GraphQL-over-HTTP spec.
8. RFC-stage snapshot (`reference/graphql-wg/rfcs/`): **Fragment Arguments** stuck at Strawman/competing-drafts with no champion; **Semantic Nullability** (`@semanticNonNull`) at Strawman, its sibling **Client Controlled Nullability** RFC explicitly marked "not being worked on" in favor of Semantic Nullability; the **Nullability Working Group itself was archived 2026-02-05**, having converged on a "**service capabilities + `onError`**" direction (`graphql-spec` PR #1163, per `reference/nullability-wg/README.md`), with further work continuing as plain `graphql-wg` RFC `DisableErrorPropagationDirective.md` (implementation PR `graphql-js#4348`).
9. GraphQL-over-HTTP (`reference/graphql-over-http`, commit `d438b20`, 2026-10-08) mandates the `application/graphql-response+json` media type be requested via `Accept`, defines exact status-code rules (`200`/`294`/`4xx`/`5xx` per case — see §12.1), and recommends the **non-IANA-registered custom status code `294 Partial Success`** for partial data+errors responses (explicitly non-normative, clients must still treat it as `200`-class per RFC 9110). There is **no literal "watershed" term** anywhere in the spec text — that is community shorthand for this 294/200 distinction.
10. The GraphQL Foundation's own **vendor-neutral Federation spec** (`reference/graphql-federation-spec`, formerly `composite-schemas-spec`, renamed — GitHub 301-redirects the old name) is a real, substantial spec (6 numbered sections + an appendix, not just a stub), using **`@lookup`/`@key`/`@internal`/`@inaccessible`/`@is`/`@require`/`@shareable`** — a different, overlapping directive vocabulary from Apollo's Federation v2 (`@key`/`@external`/`@requires`/`@provides`/`@shareable`/`@override`/`@tag`/...). Both must be considered separately; they are not interchangeable.
11. Relay's **Global Object Identification** spec text does **not** mandate any base64 `"Type:id"` encoding convention — it only requires a `Node` interface with a non-null `id: ID!` field and a root `node(id: ID!): Node` field; the base64 convention is purely a `graphql-relay-js`/client-library convention, not spec text (`reference/relay-specs/ObjectIdentification.md`).
12. Automatic Persisted Queries (Apollo, `reference/apollo-apq/apq.mdx`) is not a GraphQL Foundation spec, just a de facto protocol: client sends `extensions.persistedQuery.{version,sha256Hash}`; server replies with error code **`PERSISTED_QUERY_NOT_FOUND`** if it doesn't recognize the hash, prompting the client to resend the hash plus the full query text once.
13. graphql-over-http also ships **unmerged RFCs** beyond the ratified spec: `rfcs/GraphQLOverWebSocket.md`, `rfcs/GraphQLOverSSE.md` (these largely restate `enisdenjo/graphql-ws`/`graphql-sse`, which remain the de facto community standards), `rfcs/IncrementalDelivery.md` (`multipart/mixed` + chunked transfer), `rfcs/Batching.md` (array-of-operations POST body), and `rfcs/PersistedOperations.md` (superseded — a note says Persisted Operations have since been promised "as an appendix" to `graphql-spec`, but no `Appendix A -- Persisted Documents.md` exists in any locally-fetched edition as of 2026-10-13 — treat as aspirational/unmerged).
14. The `graphql-scalars` repo (source of scalars.graphql.org) is the Foundation's registry for `@specifiedBy`-style custom scalar specs, contributed under `scalars/contributed/<owner>/` by five organizations (`andimarek`, `jakobmerrild`, `chillicream`, `AlexandreCarlton`, `apollographql`) found in the local checkout.

## 1. Spec editions and the edition diff

### 1.1 Editions and working draft fetched

| Directory | Ref | Commit | Date | Role |
|---|---|---|---|---|
| `reference/graphql-spec-October2021` | tag `October2021` | `51337a9b82` | 2021-10-26 | Previous released edition — "before" side of the diff. |
| `reference/graphql-spec-September2025` | tag `September2025` | `89d93ebbe0` | 2025-09-03 | **Newest released edition** as of 2026-10-13; no later tag exists. |
| `reference/graphql-spec-main` | `main` | `3f1ef84601` | 2026-09-28 | Working draft: everything merged after the September2025 cut, not yet released. |

Spec text lives at `<dir>/spec/Section N -- <Name>.md` and `<dir>/spec/Appendix <L> -- <Name>.md`; `graphql-spec-September2025/changelogs/{October2021,September2025}.md` list every merged PR per edition.

### 1.2 October2021 → September2025 (released changes)

Per `reference/graphql-spec-September2025/changelogs/September2025.md` ("Notable contributions", backed by the full 90-commit changeset table in the same file):

| Change | PR(s) | Section affected |
|---|---|---|
| `@oneOf` input objects ("input unions") | #825 | Section 3, "OneOf Input Objects"; new `__Type.isOneOf` |
| Schema Coordinates | #794 | New Section 2, "Schema Coordinates" |
| Descriptions on executable documents / operations | #1170, #793 (default value coercion) | Section 2, "Descriptions" |
| Broader deprecation support (field args, directive args, input fields; `@deprecated(reason:)` made non-null) | #805, #1040, #1053, #1142 | Section 3, "@deprecated"; Appendix D |
| Full-Unicode source text (`SourceCharacter` no longer BMP-restricted) | #849 | Section 2, "Source Text" |
| Add validation rule that operation types exist | #955 | Section 5, new "Operation Type Existence" (5.2.1.1) |
| `ExecuteSelectionSet` renamed to `ExecuteCollectedFields`; "execution/field error" terminology renamed to "operation execution"/"execution error"; "response position" defined | #1039, #1152, #1148, #1159 | Section 6, Section 7 |
| Add `extensions` to GraphQL request | #976 | Section 7 |
| Add Appendix C "Specified Type System Definitions" (later renamed Appendix D in `main`) | #1037 | New appendix (did not exist in October2021 at all — October2021 only has Appendix A "Notation Conventions" and Appendix B "Grammar Summary") |
| Prevent `@skip`/`@include` on root subscription selection set | #860 | Section 5, "Single Root Field" |

### 1.3 September2025 → main (unreleased working-draft changes)

Verified by direct `diff -u` of every `Section N.md`/`Appendix D.md` file between the two checkouts (not guessed):

| Change | Evidence | Notes |
|---|---|---|
| Empty selection sets allowed | Section 2 L386: `SelectionSet : { Selection* }` (was `{ Selection+ }`); Section 5 "Leaf Field Selections" reworded "subselection must be empty" → "must not be present" / "must not be empty" → "must be present", with new counter-example `barkVolume {}` (invalid, scalar) and new example `human {}` (valid, object) | This is RFC "empty selection sets" (tracked publicly as `graphql-spec#1227`); landed in working draft, not yet in a release. |
| OneOf inhabitability algorithm | Section 3 L1742 replaces "must not reference itself directly" with `{InputObjectHasUnbreakableCycle(inputObject)} must be {false}`; new `InputObjectHasUnbreakableCycle()`/`InputFieldTypeHasUnbreakableCycle()` algorithm at L1785-1817; new counter-example (`First`/`Second` mutually-required `@oneOf` cycle) | Public RFC "OneOf inhabitability" (`#1211`-area work); algorithm text has **landed in `main`** even though its own RFC PR has not been reported merged by rfcs.graphql.org as of this fetch — distinguish "merged into spec main" from "cut into a numbered release edition". |
| Directive Extensions | Section 3 L40 adds `DirectiveExtension` to `TypeSystemExtensionDocument`; new `### Directive Extensions` subsection (`extend directive @Name Directives[Const]`) with 4 type-validation rules | No prior art for this in September2025 at all. |
| Directives on directive definitions; `@deprecated` on directives | `DirectiveDefinition` grammar gains optional `Directives[Const]?` before `repeatable`; `@deprecated`'s locations grow `... | ENUM_VALUE` → `... | ENUM_VALUE | DIRECTIVE_DEFINITION` | Section 3, "Directives" / "@deprecated". |
| New `__DirectiveLocation.DIRECTIVE_DEFINITION` enum value | Section 3 L2116; Appendix D L119 | Matches the grammar/`@deprecated` change above. |
| New `__Schema.directives(includeDeprecated: Boolean! = false)` argument | Appendix D L36 (was `directives: [__Directive!]!` with no argument) | Section 4 prose gains matching "Accepts the argument `includeDeprecated`..." note. |
| New `__Directive.isDeprecated`/`deprecationReason` fields | Appendix D L91-94 | Previously `__Directive` had no deprecation fields at all. |
| `includeDeprecated` nullability erratum fixed | Appendix D's `fields`/`enumValues`/`inputFields`/`args` arguments change `Boolean = false` → `Boolean! = false`, now matching Section 4's prose which was already non-null in September2025 | See item 4 of "In brief" — this was an internal September2025 inconsistency between Section 4 and Appendix D, not a new semantic change in `main`. |
| `ExecuteRequest()`/`Subscribe()` formalization | Section 6 L47-59: new explanatory paragraph for `ExecuteRequest()`; `Subscribe(subscription, schema, variableValues, initialValue)` → `Subscribe(sourceStream, subscription, schema, variableValues)` (source stream now created by `ExecuteRequest()` itself and passed in) | Makes explicit that a `CreateSourceEventStream()` failure is a _request error_, not an _execution error_ (new Note at Section 6 L309). |
| "execution" → "_operation execution_" terminology pass | Dozens of call sites across Sections 3, 5, 6, 7 | Purely editorial/terminology, no behavior change. |
| Error-list uniqueness wording tightened | Section 6 L943: "only one error should be added... per response position" → "each error added... must have a unique response path" | Editorial clarification, same semantics. |
| Fragments intro rewritten (component-based framing) | Section 2 L586-612 | Purely editorial (motivates Fragment Arguments RFC), no grammar change. |

## 2. Language (lexer + grammar) feature inventory

Source: `reference/graphql-spec-main/spec/Section 2 -- Language.md` (citations are that file's headings/line numbers unless noted).

| Feature | Spec location | Status | Notes for implementers |
|---|---|---|---|
| `SourceCharacter` (full Unicode scalar value) | "Source Text" L46 | Released (Sept2025, PR #849) | October2021 restricted this to BMP (`U+0000`-`U+FFFF` minus surrogates); now any Unicode scalar value. |
| `UnicodeBOM` (ignored) | "Ignored Tokens" L146-177 | Released | May appear before/after any token, anywhere in source. |
| `WhiteSpace`, `LineTerminator`, `Comment`, `Comma` (ignored) | "Ignored Tokens" | Released | `Comma` is insignificant (unlike JSON); `LineTerminator` matters for `#`-comments and block strings. |
| `Token` ::= Punctuator \| Name \| IntValue \| FloatValue \| StringValue | "Lexical Tokens" L130 | Released | Five terminal token kinds total. |
| `Punctuator` (`! $ & ( ) ... : = @ [ ] { \| }`) | "Punctuators" L185 | Released | Exactly 13 distinct punctuator glyphs incl. the 3-char `...`. |
| `Name` (`/[_A-Za-z][_0-9A-Za-z]*/`) | "Names" L185+ | Released | ASCII-only identifier grammar (unaffected by the Unicode source-text change — only applies to `Name`, not `StringValue`). |
| `IntValue` / `FloatValue` | "Int Value" L804, "Float Value" L831 | Released | No leading zeros, optional `-`, `FloatValue` requires fractional and/or exponent part. |
| `StringValue` (single-quoted) incl. escapes `\" \\ \/ \b \f \n \r \t`, `\u{H+}` / `\uHHHH` (incl. legacy UTF-16 surrogate pairs) | "String Value" L872-960 | Released | Variable-width `\u{1F4A9}` preferred over legacy fixed-width surrogate-pair form for supplementary characters; invalid surrogate/out-of-range hex (`\uDEAD`, `\u{110000}`) is a parse error. |
| `BlockString` (`"""..."""`) + `BlockStringValue()` dedent/trim algorithm | "String Value", "Block Strings" | Released | Must strip common leading indentation and blank first/last lines; algorithm referenced but not fully inlined in Section 2 (see Appendix B notation). |
| `NullValue`, `BooleanValue`, `EnumValue`, `ListValue`, `ObjectValue` (input object literal) | "Input Values" L783-1243 | Released | `EnumValue` excludes `true`/`false`/`null` lexically. |
| `Variable` (`$Name`) | "Variables" L1243 | Released | Variable definitions carry optional default value + optional const directives. |
| `Type` ::= `NamedType` \| `ListType` \| `NonNullType` | "Type References" L1299 | Released | `NonNullType` cannot itself be wrapped in another `NonNullType` (no `Int!!`). |
| `Directives` / `Directives[Const]` | "Directives" L1341 | Released | `[Const]` parametrization controls whether directive-argument values may themselves contain variables (type-system contexts forbid variables). |
| `SchemaCoordinate` (`TypeCoordinate`, `MemberCoordinate`, `ArgumentCoordinate`, `DirectiveCoordinate`, `DirectiveArgumentCoordinate`) | "Schema Coordinates" L1388 | **New in September2025** (PR #794) | Human-readable unique-reference syntax, e.g. `User.name`, `@deprecated(reason:)`; explicitly excludes union members (no coordinate form exists for "member of union X"). |
| `Document` ::= `Definition+` (`ExecutableDefinition` \| `TypeSystemDefinitionOrExtension`) | "Document" L287 | Released | A single document may legally mix executable and type-system definitions at the grammar level (Section 5's "Executable Definitions" validation rule is what forbids this for a request document). |
| `OperationDefinition` (shorthand query, named query/mutation/subscription) | "Operations" L329 | Released | Shorthand form (`{ field }`) is query-only, anonymous, no variables/directives. |
| `SelectionSet` — `{ Selection+ }` (September2025) vs `{ Selection* }` (`main`) | "Selection Sets" L384 | **Working draft only** | Empty selection sets permitted in `main`; see §1.3. |
| `Field`, `Alias`, `Arguments` | "Fields" L412, "Field Alias" L521 | Released | |
| `FragmentSpread`, `FragmentDefinition`, `TypeCondition`, `InlineFragment` | "Fragments" L578-783 | Released | Fragment names must not be `on`. |
| `DirectiveDefinition` gains optional `Directives[Const]?` before `repeatable`/`on` | "Directives" (Type System section) | **Working draft only** | Lets a directive definition itself be annotated (e.g. with another directive), see §1.3. |

## 3. Type system feature inventory

Source: `reference/graphql-spec-main/spec/Section 3 -- Type System.md`.

| Feature | Spec location | Status | Notes |
|---|---|---|---|
| 8 type kinds: `SCALAR OBJECT INTERFACE UNION ENUM INPUT_OBJECT LIST NON_NULL` | "Types", `__TypeKind` | Released | Matches `__TypeKind` introspection enum exactly. |
| Built-in scalars: `Int` (signed 32-bit), `Float` (IEEE-754 double), `String` (Unicode text), `Boolean`, `ID` (serializes as String, accepts String/Int input, rejects Float) | "Scalars" L402-655 | Released | Exact coercion boundary for `Int`: values `< -2^31` or `>= 2^31` must raise an error on both input and result coercion. `Float` input coercion rejects `NaN`/`Infinity`. `ID` input accepts both `"4"` and `4`/`-4` but rejects `4.0`. |
| Objects: fields, field arguments, interface implementation (with covariant return-type and contravariant/invariant argument rules), `@deprecated` on fields | "Objects" L673-1109 | Released | |
| Interfaces (incl. interfaces implementing interfaces, transitively) | "Interfaces" L1109 | Released | |
| Unions (object-type members only, no interfaces/scalars as members) | "Unions" L1362 | Released | No schema-coordinate form exists for a union member (see §2). |
| Enums | "Enums" L1486 | Released | |
| Input Objects, incl. input coercion rules, circular-reference validation | "Input Objects" L1560-1914 | Released (base rules); working draft (inhabitability algorithm) | See §1.3 for the `InputObjectHasUnbreakableCycle()` upgrade. |
| `@oneOf` Input Objects (exactly one non-null field) + `__Type.isOneOf` | "OneOf Input Objects" L1819 | **Released (September2025, PR #825)** | Full input-coercion truth table given in spec (14 rows, literal+variable combinations); coercion failures are a mix of _request error_ (bad shape) and _execution error_ (null/absent member after coercion). |
| List / Non-Null wrapping types, "Combining List and Non-Null" | "List" L1914, "Non-Null" L1972 | Released | |
| Type extensions (`extend type/interface/union/enum/input/scalar`) | "Type Extensions" + per-kind `### X Extensions` | Released | |
| **Directive Extensions** (`extend directive @Name Directives[Const]`) | "Directive Extensions" | **Working draft only** | New grammar + 4 validation rules (previous directive must exist; no duplicate non-repeatable directives; no directive self-reference, direct or indirect). |
| Built-in directives: `@skip(if:)`, `@include(if:)` on `FIELD \| FRAGMENT_SPREAD \| INLINE_FRAGMENT`; `@deprecated(reason: String! = "No longer supported")` on `FIELD_DEFINITION \| ARGUMENT_DEFINITION \| INPUT_FIELD_DEFINITION \| ENUM_VALUE [ \| DIRECTIVE_DEFINITION in main]`; `@specifiedBy(url: String!)` on `SCALAR`; `@oneOf` on `INPUT_OBJECT` | "Directives" L2080-2373 | Released (all four); `DIRECTIVE_DEFINITION` location working-draft-only | `@skip`/`@include` are "should provide"; `@deprecated` is "must provide ... if representing deprecated portions"; `@specifiedBy`/`@oneOf` are "should provide". |
| Directive locations: 8 `ExecutableDirectiveLocation` + 11 `TypeSystemDirectiveLocation` (12 in `main`, adding `DIRECTIVE_DEFINITION`) | "Directives" grammar | Released (11); working draft (12th) | |
| Custom-directive naming convention (`_`-prefixed to avoid collision with future built-ins) | "Custom Directives" | Non-normative recommendation | e.g. `@fb_auth`, `@rfc_live`. |

## 4. Schema introspection feature inventory

Source: `reference/graphql-spec-main/spec/Section 4 -- Introspection.md` + `Appendix D -- Specified Definitions.md`; cross-checked against September2025/October2021 (see §1.3/§1.4 for what's new).

Full current (`main`) introspection SDL:

```graphql
type __Schema {
  description: String
  types: [__Type!]!
  queryType: __Type!
  mutationType: __Type
  subscriptionType: __Type
  directives(includeDeprecated: Boolean! = false): [__Directive!]!   # includeDeprecated arg is new in main
}

type __Type {
  kind: __TypeKind!
  name: String
  description: String
  specifiedByURL: String                                            # non-null only for custom SCALAR
  fields(includeDeprecated: Boolean! = false): [__Field!]            # non-null for OBJECT/INTERFACE
  interfaces: [__Type!]                                              # non-null for OBJECT/INTERFACE
  possibleTypes: [__Type!]                                           # non-null for INTERFACE/UNION
  enumValues(includeDeprecated: Boolean! = false): [__EnumValue!]    # non-null for ENUM
  inputFields(includeDeprecated: Boolean! = false): [__InputValue!]  # non-null for INPUT_OBJECT
  ofType: __Type                                                     # non-null for LIST/NON_NULL
  isOneOf: Boolean                                                   # non-null for INPUT_OBJECT; released Sept2025
}

enum __TypeKind { SCALAR OBJECT INTERFACE UNION ENUM INPUT_OBJECT LIST NON_NULL }

type __Field {
  name: String!
  description: String
  args(includeDeprecated: Boolean! = false): [__InputValue!]!
  type: __Type!
  isDeprecated: Boolean!
  deprecationReason: String
}

type __InputValue {
  name: String!
  description: String
  type: __Type!
  defaultValue: String
  isDeprecated: Boolean!
  deprecationReason: String
}

type __EnumValue {
  name: String!
  description: String
  isDeprecated: Boolean!
  deprecationReason: String
}

type __Directive {
  name: String!
  description: String
  isRepeatable: Boolean!
  locations: [__DirectiveLocation!]!
  args(includeDeprecated: Boolean! = false): [__InputValue!]!
  isDeprecated: Boolean!          # new in main
  deprecationReason: String       # new in main
}

enum __DirectiveLocation {
  QUERY MUTATION SUBSCRIPTION FIELD FRAGMENT_DEFINITION FRAGMENT_SPREAD
  INLINE_FRAGMENT VARIABLE_DEFINITION SCHEMA SCALAR OBJECT FIELD_DEFINITION
  ARGUMENT_DEFINITION INTERFACE UNION ENUM ENUM_VALUE INPUT_OBJECT
  INPUT_FIELD_DEFINITION DIRECTIVE_DEFINITION   # DIRECTIVE_DEFINITION new in main
}
```

| Feature | Status | Notes |
|---|---|---|
| Meta-fields `__typename: String!`, `__schema: __Schema!`, `__type(name: String!): __Type` | Released | `__typename` implicit on any selection set; `__schema`/`__type` implicit **only** on the root Query type. `__typename` is **not** permitted as the sole root field of a subscription (ties into validation rule 5.2.4.1). |
| Per-kind field-nulling rules (Scalar/Object/Union/Interface/Enum/Input Object/List/Non-Null each expose only their relevant subset of `__Type` fields, rest `null`) | Released | Section 4 "The __Type Type", one subsection per kind. |
| `includeDeprecated` nullability | September2025 (Section 4 prose) vs. `main` (Appendix D sync) | See §1.3/§1.4 erratum note — do not assume Appendix D and Section 4 agree within an edition; always prefer Section 4's normative prose. |
| `__Schema.directives(includeDeprecated:)` | **Working draft only** | Previously no argument at all. |
| `__Directive.isDeprecated`/`deprecationReason` | **Working draft only** | Previously `__Directive` had no deprecation fields. |
| `__DirectiveLocation.DIRECTIVE_DEFINITION` | **Working draft only** | Paired with `@deprecated` becoming valid on `DIRECTIVE_DEFINITION`. |
| `__Type.specifiedByURL` | Released, name stable since at least October2021 in the locally fetched editions (no `specifiedByUrl` lowercase variant found in any checked-out edition) | Only non-null for custom scalars using `@specifiedBy`. |
| Reserved-name rule: user schema `Name`s must not start with `__` | Released | Section 4, cross-referenced from Section 3 naming rules. |

## 5. Validation rules (Section 5)

Source: `reference/graphql-spec-main/spec/Section 5 -- Validation.md` (2237 lines) and `reference/graphql-spec-September2025/spec/Section 5 -- Validation.md` (2219 lines); numbering derived from heading nesting and confirmed against known public section numbers (e.g. 5.2.3.1 "Lone Anonymous Operation", 5.8.5 "All Variable Usages Are Allowed"). graphql-js rule mapping is sourced from the literal `// Spec Section:` comments and `specifiedRules`/`specifiedSDLRules` arrays in `reference/graphql-js/src/validation/specifiedRules.ts`.

**30 leaf rules total** (34 if the four "Fragment Spread Is Possible" sub-cases are counted as independent rules rather than explanatory sub-cases of 5.5.2.3). The only Section-5 change between September2025 and `main` is the "Leaf Field Selections" (5.3.3) empty-selection-set wording (§1.3); every rule below exists identically in both editions unless noted.

| # | Rule | Description | graphql-js rule file |
|---|---|---|---|
| 5.1.1 | Executable Definitions | Every top-level definition in a request document must be an Operation or Fragment, never a type-system definition/extension. | `ExecutableDefinitionsRule.ts` |
| 5.2.1.1 | Operation Type Existence | The root operation type matching each operation's kind (query/mutation/subscription) must exist in the schema. **New in September2025** (PR #955). | `KnownOperationTypesRule.ts` |
| 5.2.2.1 | Operation Name Uniqueness | Named operations sharing a name must be exactly one operation (even across differing operation types). | `UniqueOperationNamesRule.ts` |
| 5.2.3.1 | Lone Anonymous Operation | If a document has more than one operation, none may be anonymous. | `LoneAnonymousOperationRule.ts` |
| 5.2.4.1 | Single Root Field | A subscription's collected root selection (via `CollectSubscriptionFields`, ignoring `@skip`/`@include`) must resolve to exactly one field, which must not be an introspection meta-field. | `SingleFieldSubscriptionsRule.ts` |
| 5.3.1 | Field Selections | A selected field name must be defined on the scoped type; unions permit only `__typename` directly. | `FieldsOnCorrectTypeRule.ts` |
| 5.3.2 | Field Selection Merging | `FieldsInSetCanMerge`: fields sharing a response name must have identical response shape, and (for the same parent Object type) identical field name + arguments, recursively on merged sub-selections. | `OverlappingFieldsCanBeMergedRule.ts` |
| 5.3.3 | Leaf Field Selections | Scalar/Enum selections must have no subselection; Object/Interface/Union selections must have a subselection (may be empty `{}` in `main`, must be non-empty in September2025). | `ScalarLeafsRule.ts` |
| 5.4.1 | Argument Names | Every argument name must match a defined argument on the field/directive. | `KnownArgumentNamesRule.ts` (+ `KnownArgumentNamesOnDirectivesRule` SDL variant) |
| 5.4.2 | Argument Uniqueness | No duplicate argument names within one argument set. | `UniqueArgumentNamesRule.ts` |
| 5.4.3 | Required Arguments | Non-null arguments without a default must be present and not the `null` literal. | `ProvidedRequiredArgumentsRule.ts` (+ `ProvidedRequiredArgumentsOnDirectivesRule`) |
| 5.5.1.1 | Fragment Name Uniqueness | Each named fragment definition must be unique in the document. | `UniqueFragmentNamesRule.ts` |
| 5.5.1.2 | Fragment Spread Type Existence | A fragment's type condition must reference a schema-defined type. | `KnownTypeNamesRule.ts` |
| 5.5.1.3 | Fragments on Object, Interface or Union Types | Fragment type condition kind must be OBJECT/INTERFACE/UNION. | `FragmentsOnCompositeTypesRule.ts` |
| 5.5.1.4 | Fragments Must Be Used | Every fragment definition must be spread at least once. | `NoUnusedFragmentsRule.ts` |
| 5.5.2.1 | Fragment Spread Target Defined | A named spread must refer to a fragment defined in the document. | `KnownFragmentNamesRule.ts` |
| 5.5.2.2 | Fragment Spreads Must Not Form Cycles | `DetectFragmentCycles`: the fragment-spread graph must be acyclic. | `NoFragmentCyclesRule.ts` |
| 5.5.2.3 | Fragment Spread Is Possible | `GetPossibleTypes(fragmentType) ∩ GetPossibleTypes(parentType)` must be non-empty (4 documented sub-cases: object-in-object, abstract-in-object, object-in-abstract, abstract-in-abstract). | `PossibleFragmentSpreadsRule.ts` |
| 5.6.1 | Values of Correct Type | Literal input values must be coercible to the expected type. | `ValuesOfCorrectTypeRule.ts` |
| 5.6.2 | Input Object Field Names | Every input-object literal field name must be defined on the expected input type. | folded into `ValuesOfCorrectTypeRule.ts` (no dedicated file) |
| 5.6.3 | Input Object Field Uniqueness | No duplicate field names within one input-object literal. | `UniqueInputFieldNamesRule.ts` |
| 5.6.4 | Input Object Required Fields | Non-null input fields without a default must be present and non-null. | folded into `ValuesOfCorrectTypeRule.ts` (no dedicated file) |
| 5.7.1 | Directives Are Defined | Every directive used must be defined by the schema. | `KnownDirectivesRule.ts` |
| 5.7.2 | Directives Are in Valid Locations | A directive's AST location must be among its declared locations. | `KnownDirectivesRule.ts` (same file) |
| 5.7.3 | Directives Are Unique per Location | Non-`repeatable` directives may appear at most once per exact location. | `UniqueDirectivesPerLocationRule.ts` |
| 5.8.1 | Variable Uniqueness | No two variables sharing a name on one operation. | `UniqueVariableNamesRule.ts` |
| 5.8.2 | Variables Are Input Types | `IsInputType(variableType)` must hold. | `VariablesAreInputTypesRule.ts` |
| 5.8.3 | All Variable Uses Defined | Every variable used by an operation (or any fragment it transitively includes) must be declared by that operation. | `NoUndefinedVariablesRule.ts` |
| 5.8.4 | All Variables Used | Every declared variable must be used somewhere in the operation or its fragments. | `NoUnusedVariablesRule.ts` |
| 5.8.5 | All Variable Usages Are Allowed | `IsVariableUsageAllowed`/`AreTypesCompatible`: variable type must be nullability/list-compatible with its use site, accounting for defaults and `@oneOf` non-null requirements. | `VariablesInAllowedPositionRule.ts` |

**SDL/type-system-document rules** (validate schema-definition documents, not request documents — conceptually Section 3, not numbered under Section 5): `LoneSchemaDefinitionRule.ts`, `UniqueOperationTypesRule.ts`, `UniqueTypeNamesRule.ts`, `UniqueEnumValueNamesRule.ts`, `UniqueFieldDefinitionNamesRule.ts`, `UniqueArgumentDefinitionNamesRule.ts`, `UniqueDirectiveNamesRule.ts`, `PossibleTypeExtensionsRule.ts` (only in `specifiedSDLRules`); plus dual-purpose files shared with the executable-rule set: `KnownTypeNamesRule.ts`, `KnownDirectivesRule.ts`, `UniqueDirectivesPerLocationRule.ts`, `UniqueArgumentNamesRule.ts`, `UniqueInputFieldNamesRule.ts`.

**Not required by spec text — hardening or experimental, do not treat as core compliance:**
- `MaxIntrospectionDepthRule.ts` — graphql-js's own comment: "Technically these aren't part of the spec but they are strongly encouraged"; graphql-js separates it into `recommendedRules`, not `specifiedRules`.
- `DeferStreamDirectiveLabelRule.ts`, `DeferStreamDirectiveOnRootFieldRule.ts`, `DeferStreamDirectiveOnValidOperationsRule.ts`, `StreamDirectiveOnListFieldRule.ts` — experimental `@defer`/`@stream` support; zero matches for "defer"/"@stream" in Section 5 text of either edition on disk.
- `rules/custom/NoDeprecatedCustomRule.ts`, `rules/custom/NoSchemaIntrospectionCustomRule.ts` — explicitly opt-in "Custom Rules", not in any `specified*` array.

## 6. Execution feature inventory

Source: `reference/graphql-spec-main/spec/Section 6 -- Execution.md`.

| Algorithm | Spec location | Summary |
|---|---|---|
| `ExecuteRequest(schema, document, operationName, variableValues, initialValue)` | "Executing Requests" | Preamble: resolve `GetOperation()`, run `CoerceVariableValues()`, then dispatch to `ExecuteQuery`/`ExecuteMutation`/(`CreateSourceEventStream` + `Subscribe`) by operation kind. Errors here are typically _request errors_; errors after dispatch are typically _execution errors_ — this distinction was only made fully explicit in `main` (§1.3). |
| `GetOperation(document, operationName)` | "Executing Requests" | Resolves which operation to run; raises a _request error_ if ambiguous or named operation not found. |
| `CoerceVariableValues(schema, operation, variableValues)` | "Coercing Variable Values" | Per declared variable: apply default (incl. explicit `null` default), else raise _request error_ if non-null and missing/null, else coerce the provided literal/value per the variable's input type. Explicitly noted as "very similar to `CoerceArgumentValues()`". |
| `ExecuteQuery` / `ExecuteMutation` | "Executing Operations" → "Query"/"Mutation" | Both call `ExecuteRootSelectionSet`; query runs the root selection **normally** (parallel-eligible), mutation runs it **serially**. |
| `CreateSourceEventStream`, `Subscribe(sourceStream, subscription, schema, variableValues)`, `MapSourceToResponseEvent`, `Unsubscribe` | "Subscription" → "Source Stream"/"Response Stream"/"Unsubscribe" | `Subscribe()`'s signature changed in `main` to take the already-created `sourceStream` as its first argument (§1.3); response stream = source stream mapped through `ExecuteRootSelectionSet` per event. |
| `ExecuteRootSelectionSet(variableValues, initialValue, objectType, selectionSet, executionMode)` | "Executing the Root Selection Set" | `CollectFields()` then `ExecuteCollectedFields()` serially or normally depending on `executionMode`; shared by queries, mutations, and each subscription event. |
| `CollectFields(objectType, selectionSet, variableValues)` / `CollectSubfields(objectType, fields, variableValues)` | "Field Collection" | Produces an ordered _collected fields map_ (response name → _field set_), merging same-response-name selections across fragments; order is significant and must match first-encountered order. |
| `ExecuteCollectedFields(collectedFieldsMap, objectType, objectValue, variableValues)` | "Executing Collected Fields" | Builds the ordered result map; a non-null _response position_ raising an _execution error_ propagates to its parent position (field's whole selection, or whole list). |
| Normal vs. serial execution | "Normal and Serial Execution" | Normal = any order (commonly parallel) since resolution must be side-effect-free/idempotent outside mutations; serial = textual order, each field's **own value resolution** (not its sub-selection) must complete before starting the next field. |
| `ExecuteField(objectType, objectValue, fieldType, fields, variableValues)` | "Executing Fields" | `CoerceArgumentValues()` → `ResolveFieldValue()` → `CompleteValue()`. |
| `CoerceArgumentValues(objectType, field, variableValues)` | "Coercing Field Arguments" | Argument-literal-or-variable coercion, analogous to `CoerceVariableValues`. |
| `ResolveFieldValue(objectType, objectValue, fieldName, argumentValues)` | "Value Resolution" | Implementation-defined; may be async. |
| `CompleteValue(fieldType, fields, result, variableValues)` | "Value Completion" | Non-Null unwraps and re-raises _execution error_ on inner `null`; `null`/`undefined` result → `null`; List maps `CompleteValue` over items; Scalar/Enum → `CoerceResult()`; Object/Interface/Union → `ResolveAbstractType()` (if needed) + `CollectSubfields()` + `ExecuteCollectedFields()` (normally, parallel-eligible even inside a serial mutation's sub-selections). |
| `CoerceResult(leafType, value)` | "Coercing Results" | Delegates to the type's own internal result-coercion method; must not return `null`, else _execution error_. |
| `ResolveAbstractType(abstractType, objectValue)` | "Resolving Abstract Types" | Implementation-defined concrete-type resolution for Interface/Union. |
| Error propagation / null bubbling | "Handling Execution Errors" | An _execution error_ resolves its _response position_ to `null` and is recorded once (unique _response path_ per error, tightened wording in `main`); if that position is Non-Null, the error re-raises at the parent position; a `List` of `Non-Null` fully nulls the list if any element nulls; repeats upward until an nullable ancestor absorbs it or the whole response is `null`. |

## 7. Response format

Source: `reference/graphql-spec-main/spec/Section 7 -- Response.md`.

| Concept | Rule |
|---|---|
| Three kinds of _response_ | _execution result_ (query/mutation, or one event of a subscription's stream), _response stream_ (subscription), _request error result_ (failure before operation execution begins). |
| _Execution result_ shape | Must contain `"data"`; must contain non-empty `"errors"` iff any _execution error_ was raised (omitted entirely, not empty array, if none); may contain `"extensions"`. |
| _Request error result_ shape | Must contain non-empty `"errors"`; **must not** contain `"data"` at all; may contain `"extensions"`. |
| _Response position_ / _response path_ | A response path is a list of path segments (string response names, or 0-indexed list integers) from the response root to a position; aliased fields use the alias in the path, not the field name. |
| `"data"` | Result of operation execution; `null` only when an execution error prevented a valid response (never present at all for a _request error result_). |
| `"errors"` entry format | Each error is a map; §7 "Errors" defines `message` (required string), optional `locations` (list of `{line, column}`, 1-indexed), optional `path` (the response path, for execution errors only — request errors have no path), and implementations may add further entries. |
| `"extensions"` | Reserved, implementer-defined, optional on both result kinds. |
| Serialization | JSON is the canonical serialization format; other formats are allowed if they can express the same structure; map key ordering should be preserved where the format allows it (recommended, not mandatory, per September2025 PR #1092). |

## 8. Incremental delivery (`@defer` / `@stream`)

- **Spec status**: Stage 2/Draft, tracked at `graphql-spec#1110` ("Incremental Delivery spec draft"); **not merged** into either September2025 or `main` — zero occurrences of `@defer`/`@stream` in any locally fetched `Section *.md`. The authoritative RFC text lives in `reference/graphql-wg/rfcs/DeferStream.md` ("Working Draft - September 2024").
- **graphql-js v17 implementation**: ships `experimentalExecuteIncrementally()` (and the legacy-format `legacyExecuteIncrementally()`), plus the four non-spec validation rules listed in §5 ("Not required by spec text"). `@defer`/`@stream` are not in `specifiedDirectives`.
- **Current response shape** (non-legacy): initial payload carries `data` + `pending` + `hasNext: true`; subsequent payloads carry some combination of `pending`/`incremental`/`completed` + `hasNext: boolean`. This replaces an older **legacy** per-patch shape keyed by `path` + optional `label` + `data` (still reachable via the legacy executor for backward compatibility with early adopters).
- **HTTP transport**: not part of ratified GraphQL-over-HTTP; proposed separately in `reference/graphql-over-http/rfcs/IncrementalDelivery.md` — `Transfer-Encoding: chunked` on HTTP/1.1 (explicitly forbidden on HTTP/2, which streams natively), body framed as `multipart/mixed` per RFC 1341 with an arbitrary boundary (example uses `-`), each part carrying its own `Content-Type` header and a JSON execution-result-shaped payload.
- **Working group status**: `reference/defer-stream-wg` is the dedicated subcommittee (separate from `graphql-wg` proper); still active (agendas through 2025).

## 9. Semantic nullability / error-behavior RFCs

| RFC | File | Status |
|---|---|---|
| Client Controlled Nullability | `graphql-wg/rfcs/ClientControlledNullability.md` | **Explicitly abandoned in favor of Semantic Nullability** — file header: "this document is not being worked on at the moment". |
| Semantic Nullability (`@semanticNonNull`) | `graphql-wg/rfcs/SemanticNullability.md` | Active replacement direction; reframes GraphQL's "nullable by default" error-propagation design as a historical/pragmatic choice, not a semantic ideal; Strawman-stage prose document, no merged spec PR found. |
| Disable Error Propagation Directive (`@disableErrorPropagation` / `onError`) | `graphql-wg/rfcs/DisableErrorPropagationDirective.md` | Proposed by Martin Bonnin, building on an original spec-edit PR by Benjie (`graphql-spec#1050`); implementation at `graphql-js#4348`. Distinguishes "semantic null" (legitimate business-domain null) from "error null" (null caused by a failure), letting a client opt a query into "don't null-bubble past this point, just report the error". |
| Nullability Working Group | `nullability-wg/README.md` | **Archived 2026-02-05.** Its own closing note: converged on a "service capabilities + `onError`" direction (`graphql-spec#1163`); further work continues directly in `graphql-wg`, not a dedicated subcommittee. |

## 10. Fragment arguments

- `reference/graphql-wg/rfcs/FragmentArguments.md`: motivates the problem as "variable modularity" — a reusable fragment component (e.g. a `FriendsList`) cannot parametrize its own variables (e.g. a `count`) independently of the operation that spreads it, forcing variable names/types to be threaded awkwardly through the whole query.
- Status: no merged spec PR; multiple competing proposals exist without a single champion as of this fetch — treat as **not implementable against a stable spec text** yet; track `graphql-spec` PRs referenced from the RFC file for the current leading proposal before building support.
- Related editorial motivation landed already in `main`'s Section 2 "Fragments" intro rewrite (component-based framing, §1.3) — this is preparatory prose, not the RFC's grammar/algorithm itself.

## 11. Other RFC catalog (`graphql-wg/rfcs/`)

| RFC file | One-line status |
|---|---|
| `InputUnion.md` | Superseded — kept "for historic purposes"; superseded by `@oneOf`, which "gained RFC3 status in May 2025" and is released (§3). |
| `SchemaCoordinates.md` | **Merged** (`graphql-spec#794`), released in September2025 (§1.2). |
| `CompositeSchemas.md` | Origin document for what is now the separately-spec'd `graphql-federation-spec` (§12.9); surveys prior art (stitching, Apollo Federation v1/v2, Nadel, StepZen, etc.) before proposing a vendor-neutral model. |
| `DeferStream.md` | Stage 2/Draft, see §8. |
| `SemanticNullability.md`, `ClientControlledNullability.md`, `DisableErrorPropagationDirective.md` | See §9. |
| `FragmentArguments.md` | See §10. |
| `Subscriptions.md`, `ObjectIdentification.md` | Background/design-rationale documents (subscriptions execution model predates Section 6's current text; object-identification RFC predates and informs — but is distinct from — the Relay Global Object Identification spec, §12.8). |
| `FeatureDiscovery.md`, `OptInFeatures.md` | Mechanisms for a client/tool to detect which optional spec features (e.g. `@defer`, `@oneOf`) a given service supports. |
| `AbstractFilter/`, `AnnotationStructs.md`, `ExpandingSubtyping.md`, `FieldExtensions.md`, `FragmentModularity.md`, `FullSchemas.md`, `ImplicitInheritance.md`, `MatchesDirective.md`, `MetadataStructs.md`, `MockSpec.md`, `OperationExpressions.md`, `SchemaFragments.md`, `Struct.md` | Early-stage/exploratory RFC documents present in the working group repo; none observed to have landed spec text as of this fetch — lowest priority for an initial implementation. |

## 12. Protocols

### 12.1 GraphQL over HTTP

Source: `reference/graphql-over-http/spec/GraphQLOverHTTP.md`.

| Rule | Detail |
|---|---|
| Media types | `application/json` (request; servers MUST support UTF-8 JSON POST with this type) and `application/graphql-response+json` (response; clients MUST include it in `Accept`). A client not yet knowing server support SHOULD send `Accept: application/graphql-response+json, application/json;q=0.9`. A client that never supports the response media type is a "legacy client". |
| GET | Parameters (`query`, `operationName`, `variables`, `extensions`) URL-encoded `application/x-www-form-urlencoded`; `variables`/`extensions` as JSON strings. **Mutations forbidden over GET** — server MUST reply `4xx` (recommends `405 Method Not Allowed` + `Allow` header). |
| POST | Body is a JSON object `{query, operationName?, variables?, extensions?}`; server MUST support `application/json`; unrecognized extra properties MUST be ignored by the server, and MUST NOT be added by implementers (use `extensions` or headers instead). |
| Status codes (`data` present, non-null, no `errors`) | **MUST** be `2xx`; **SHOULD** be `200`. |
| Status codes (`data` present + `errors` present, i.e. partial success) | **SHOULD** be the non-standard **`294 Partial Success`** — not IANA-registered, explicitly non-normative/recommended only alongside `application/graphql-response+json`; clients unaware of `294` must per RFC 9110 treat it as `200`-class. There is no literal "watershed" terminology in the spec text. |
| Status codes (no `data`, i.e. _request error result_) | Granular `4xx`/`5xx` table: `405` (mutation via GET, or unsupported method), `415` (unsupported `Content-Type`), `406` (no acceptable media type and `Accept` excludes `application/json`), `408` (request timeout), `414` (URI too large), `431` (headers too large), `413` (body too large), `400` (unparseable JSON or unparseable GraphQL document), `422` (not a well-formed GraphQL-over-HTTP request; validation failure; `GetOperation()` ambiguous; `CoerceVariableValues()` failure), `401`/`403` (auth), `5xx` (server-side failure). |
| Validation/Execution | Server SHOULD apply all Section 5 validation rules (MAY add more, e.g. depth/complexity limits); execution follows `ExecuteRequest()` exactly. |

### 12.2 graphql-ws (`graphql-transport-ws` subprotocol)

Source: `reference/graphql-ws/PROTOCOL.md` (master @ `895b747`, 2026-10-13).

| Message | Direction | Purpose |
|---|---|---|
| `ConnectionInit` | Client → Server | Must arrive within `connectionInitWaitTimeout`, else server closes `4408`. More than one → `4429`. Server may reject (e.g. auth) with `4403`. |
| `ConnectionAck` | Server → Client | Only after this may the client send `Subscribe`; absent ack + operation attempt → `4401`. |
| `Ping` / `Pong` | Bidirectional | Keepalive/latency; a `Pong` must answer a `Ping` ASAP; `Pong` may also be sent unsolicited. |
| `Subscribe` | Client → Server | Carries `id` + `{query, operationName?, variables?, extensions?}`; duplicate active `id` → server closes `4409`. |
| `Next` | Server → Client | One `ExecutionResult` per emitted event from the source stream. |
| `Error` | Server → Client | Terminal for that `id`; `GraphQLError[]` payload; no `Complete` follows. |
| `Complete` | Bidirectional | Server→client: stream finished normally. Client→server: client stopped listening; server must then suppress further messages for that `id`. |
| Invalid message | — | Immediate socket closure, `4400: <message>`. |

### 12.3 graphql-sse

Source: `reference/graphql-sse/PROTOCOL.md` (master @ `3749c60`, tag `2.6.2`).

| Mode | Mechanics |
|---|---|
| Distinct connections mode | One SSE connection (`Content-Type: text/event-stream`) per operation, conforming to GraphQL-over-HTTP otherwise; `next` events carry `ExecutionResult` in `data`; `complete` event ends the stream; client closes the connection to stop a stream. Suited to HTTP/2+ (no practical per-domain connection cap). |
| Single connection mode | Addresses the browser's 6-connections-per-domain HTTP/1 `EventSource` cap. Client first **reserves** a connection via `PUT` (server replies `201` + a reservation token, sent back via `X-GraphQL-Event-Stream-Token` header or `token` query param); operations are then POSTed as ordinary GraphQL-over-HTTP requests (server replies `202 Accepted` instead of streaming inline) carrying a client-chosen `operationId` in `extensions`; results are multiplexed onto the single reserved SSE connection, each `next`/`complete` event's `data` wrapped in `{id, payload}`; a `DELETE ?operationId=<id>` request stops a streaming operation (`@stream`/`@defer`/subscription). |

### 12.4 Legacy `subscriptions-transport-ws`

- Fetched as a single file (`reference/subscriptions-transport-ws/PROTOCOL.md`) via `curl` per task instructions, from the **archived** `apollographql/subscriptions-transport-ws` repo.
- Superseded in practice by `graphql-ws`; the document does not self-describe as "legacy" but the repo's archived status and the ecosystem's wholesale move to `graphql-transport-ws` make it legacy-only — only worth supporting for backward compatibility with old clients/servers, not for new implementations.

### 12.5 GraphQL multipart request specification (file uploads)

Source: `reference/graphql-multipart-request-spec/readme.md` (master @ `eff83eb`, 2025-03-05).

| Field | Role |
|---|---|
| `operations` | JSON-encoded operations object (single, or array if batching), with every file value replaced by `null`. |
| `map` | JSON object: key = multipart field name holding a file; value = array of `object-path` strings locating that file inside `operations`. |
| `<file fields>` | One multipart field per uploaded file, named arbitrarily (commonly `"0"`, `"1"`, ...), referenced from `map`. |
| Ordering rationale | Fields ordered `operations`, `map`, then files, so a server can start resolving the operation while files are still uploading. |

### 12.6 graphql-over-http RFCs beyond the ratified spec

Source: `reference/graphql-over-http/rfcs/*.md`.

| RFC | Summary |
|---|---|
| `IncrementalDelivery.md` | See §8 — `multipart/mixed` + chunked transfer framing for `@defer`/`@stream`. |
| `Batching.md` | Client sends a JSON **array** of operation objects as the POST body instead of a single object; cites Apollo Link Batch HTTP and graphql-php as prior art. No response-shape rule given beyond "array in, array out" by convention. |
| `PersistedOperations.md` | Marked "kept for historic purposes"; claims persisted operations are "specified as an appendix" (`Appendix A -- Persisted Documents.md`) — **this file does not exist in any locally fetched spec edition** (confirmed absent in `main`/`September2025`/`October2021`); treat the appendix claim as aspirational/unmerged as of 2026-10-13. The RFC's own mechanics: client computes `documentId` = SHA-256 of the full document text; request carries `documentId` instead of `query` once the server has it on record; `query` and `documentId` must not both be absent. |
| `GraphQLOverWebSocket.md`, `GraphQLOverSSE.md` | Foundation-level draft specs that substantially restate the community `graphql-ws`/`graphql-sse` protocols above; the community repos remain the de facto standards actually implemented across the ecosystem. |

### 12.7 Automatic Persisted Queries (Apollo)

Source: `reference/apollo-apq/apq.mdx`.

| Step | Detail |
|---|---|
| 1. Optimistic hash-only request | Client sends `extensions: {persistedQuery: {version: 1, sha256Hash: "<sha256 of query text>"}}` with no `query`. |
| 2. Cache miss | Server replies with error code **`PERSISTED_QUERY_NOT_FOUND`**. |
| 3. Retry with full query | Client resends the same request, now including both `query` and the `extensions.persistedQuery` block; server persists the `hash → query` mapping for future requests. |
| CDN/GET integration | APQ's fixed, hash-addressed request shape makes GraphQL queries cacheable as GET requests on a CDN — the doc has a dedicated worked example for this. |

### 12.8 Relay (Cursor Connections + Global Object Identification)

Source: `reference/relay-specs/{Connections,ObjectIdentification}.md`.

| Spec | Rule |
|---|---|
| Reserved names | Any Object type whose name ends in `Connection`; a type named `PageInfo`; an interface named `Node`. |
| Connection Type | Must have `edges: [EdgeType]` and `pageInfo: PageInfo!`. |
| Edge Type | Must have `node` and `cursor: String!` (opaque). |
| Pagination arguments | Forward: `first: Int`, `after: <cursor>`. Backward: `last: Int`, `before: <cursor>`. Combining both is discouraged (ordering becomes ambiguous) but not forbidden. |
| `EdgesToReturn`/`ApplyCursorsToEdges` algorithm | Filter by `before`/`after` first, then slice by `first` (drop from the end), then by `last` (drop from the start). |
| `PageInfo` | `hasPreviousPage`/`hasNextPage: Boolean!` (exact semantics depend on which of `first`/`last` was used — see `HasPreviousPage`/`HasNextPage` algorithms), `startCursor`/`endCursor: String` (nullable, null if no results). |
| `Node` interface | Exactly one field: `id: ID!`, globally unique, re-fetchable. |
| `node` root field | `node(id: ID!): Node`, best-effort refetch; returns `null` if the object no longer exists/is inaccessible, never an error for "not found". |
| Base64 `"Type:id"` convention | **Not present in the spec text itself** — this is purely a convention of `graphql-relay-js`/client tooling, not a requirement of `ObjectIdentification.md`. |

### 12.9 Federation v2

**Apollo Federation v2** (vendor spec, widely deployed) — `reference/apollo-federation/{subgraph-spec,directives}.mdx`.

| Element | Role |
|---|---|
| `Query._service: _Service!` | Returns `{ sdl: String! }`, the subgraph's own SDL (minus federation-private additions), for gateway composition. |
| `Query._entities(representations: [_Any!]!): [_Entity]!` | Resolves a batch of entity references by their `@key` fields; `_Any` is an opaque scalar carrying `{__typename, <key fields>}`; `_Entity` is a dynamically-built union of every `@key`-annotated type. |
| Directive vocabulary (selected) | `@key(fields: FieldSet!, resolvable: Boolean = true)`, `@external`, `@requires(fields:)`, `@provides(fields:)`, `@shareable`, `@override(from:)`, `@inaccessible`, `@tag(name:)`, `@composeDirective`, `@interfaceObject`, `@authenticated`, `@requiresScopes`, `@policy`, `@context`/`@fromContext`, `@cost`/`@listSize` (demand control), `@cacheTag`, plus a `@link` directive for importing/namespacing all of the above. |
| Scalars | `_Any`, `FieldSet` (a stringly-typed selection-set-shaped scalar), `Scope`, `Policy`. |

**GraphQL Foundation's own Federation spec** (vendor-neutral, `reference/graphql-federation-spec`, renamed from `composite-schemas-spec`, transferred from ChilliCream) — a real multi-section spec, not just a stub:

| Section | Content |
|---|---|
| "Source Schema" (§2) | Defines `@lookup(…) on FIELD_DEFINITION` (resolves an entity by a "stable key" = the lookup field's arguments; supports abstract return types with per-concrete-type key correspondence) and `@internal` (hides a lookup field from the public composed schema while keeping it available for entity resolution). |
| "Composition" (§4) | Formal validation algorithm for composing multiple source schemas: type-system validity, disallowed-inaccessible-element checks, `@external`/`@key`/`@is` directive validation, root-type usage rules. |
| "Execution" (§5) | Executor configuration and query-plan execution model. |
| "Shared Types" (§6) | `Name`, `FieldSelection` scalar-like shared grammar used across the other sections. |
| Directives (selected, from §2/related sections) | `@lookup`, `@key`, `@internal`, `@inaccessible`, `@is` (selection-map-based field correspondence for abstract lookup return types), `@require`, `@shareable`. |

These two vocabularies **overlap but are not identical** (`@lookup`/`@internal`/`@is` have no Apollo equivalent by that name; conversely Apollo's `@provides`/`@override`/`@tag`/`@cost` etc. have no counterpart yet in the Foundation spec) — a Dart federation implementation must pick (or dual-support) one explicitly rather than assuming compatibility.

### 12.10 Custom scalars (`@specifiedBy` ecosystem)

- `reference/graphql-scalars` is the literal source of `scalars.graphql.org`; community-contributed scalar specs live under `scalars/contributed/<owner>/` (owners found locally: `andimarek`, `jakobmerrild`, `chillicream`, `AlexandreCarlton`, `apollographql`).
- Mechanism: a custom scalar's type definition carries `@specifiedBy(url: "https://...")`; `__Type.specifiedByURL` surfaces that URL through introspection so generic tooling can look up the scalar's serialization rules.

## 13. Implementation checklist

Flat numbered list, grouped by layer. **Core** = required for spec compliance; **Optional** = spec-permitted but not mandatory, or hardening; **Ecosystem** = outside the GraphQL Foundation spec proper (vendor/community protocol).

**Language / lexer**
1. (Core) Full-Unicode `SourceCharacter` lexing (not BMP-restricted) — matches the working-draft/September2025 text, not October2021.
2. (Core) All five token kinds (`Punctuator`, `Name`, `IntValue`, `FloatValue`, `StringValue`) plus the five ignored-token kinds (`UnicodeBOM`, `WhiteSpace`, `LineTerminator`, `Comment`, `Comma`).
3. (Core) Block string dedent/trim algorithm (`BlockStringValue()`).
4. (Core) Both Unicode escape forms in single-quoted strings (`\uHHHH` fixed-width incl. legacy surrogate pairs, and `\u{H+}` variable-width), with scalar-value validation (reject lone surrogates, reject `> U+10FFFF`).
5. (Core) Full executable + type-system grammar (Document, OperationDefinition, SelectionSet, Field, FragmentSpread/Definition, InlineFragment, all Input Value kinds, Variable, Type references, Directives, type system definitions + extensions for every kind).
6. (Core) `SchemaCoordinate` parsing/formatting (new in September2025).
7. (Optional) Empty selection sets (`{ }`) — working-draft-only grammar, not in the current released edition; decide whether to target `main` or September2025 as your conformance baseline.
8. (Optional) `DirectiveExtension` (`extend directive @Name ...`) and directives-on-directive-definitions — working-draft-only.

**Type system**
9. (Core) All 8 type kinds, built-in scalars with exact coercion boundaries (`Int` 32-bit signed, `Float` IEEE-754 finite, `ID` string/int-in-float-out).
10. (Core) Interface implementation covariance/contravariance rules; union member restrictions (object types only).
11. (Core) Input Object coercion rules incl. default values and circular-reference validation.
12. (Core) `@oneOf` Input Objects, including the full input-coercion truth table and `__Type.isOneOf`.
13. (Optional) OneOf inhabitability check (`InputObjectHasUnbreakableCycle`) — working-draft-only refinement of the circular-reference rule.
14. (Core) Built-in directives `@skip`/`@include`/`@deprecated`/`@specifiedBy`/`@oneOf` with exact locations.
15. (Optional) `@deprecated` on `DIRECTIVE_DEFINITION` + matching `__DirectiveLocation.DIRECTIVE_DEFINITION` — working-draft-only.

**Validation**
16. (Core) All 30 Section 5 rules from §5's table, each as an independently testable visitor/rule.
17. (Optional) SDL-document validation rules (uniqueness rules for schema-definition documents) if supporting schema-building from SDL text.
18. (Optional) Non-spec hardening: max introspection depth, max query depth/complexity/cost limiting.
19. (Optional/Ecosystem) `@defer`/`@stream`-specific validation rules — only if implementing incremental delivery.

**Execution**
20. (Core) `ExecuteRequest` → `CoerceVariableValues` → `ExecuteQuery`/`ExecuteMutation`/(`CreateSourceEventStream`+`Subscribe`) dispatch, with correct request-error-vs-execution-error error classification at each boundary.
21. (Core) `CollectFields`/`CollectSubfields` producing an ordered collected-fields map with correct `@skip`/`@include` handling and fragment-spread merging.
22. (Core) Serial root execution for mutations (each top-level field's own resolution completes before the next starts; its sub-selection may still execute normally/parallel).
23. (Core) `CompleteValue` with correct null/error propagation: non-null unwrap-and-reraise, list-of-non-null full-list nulling, unique-response-path error de-duplication.
24. (Core) Abstract-type resolution (`ResolveAbstractType`) for Interface/Union.
25. (Core) Subscription source-stream → response-stream mapping, with `Unsubscribe` support.

**Introspection**
26. (Core) Full `__Schema`/`__Type`/`__Field`/`__InputValue`/`__EnumValue`/`__Directive`/`__TypeKind`/`__DirectiveLocation` SDL with correct per-kind field nulling.
27. (Core) `includeDeprecated` arguments on `fields`/`enumValues`/`inputFields`/`args`, non-null with default `false`.
28. (Optional) `__Schema.directives(includeDeprecated:)` and `__Directive.isDeprecated`/`deprecationReason` — working-draft-only.
29. (Optional) `__DirectiveLocation.DIRECTIVE_DEFINITION` — working-draft-only, paired with item 15.

**Response**
30. (Core) Three response shapes (execution result / response stream / request error result) with exact `data`/`errors`/`extensions` presence rules (never `data`+no-`errors`-key being absent together incorrectly; never `data` present on a request error result).
31. (Core) Response path construction (string field names incl. aliases, integer list indices).
32. (Optional) Preserve map key ordering in serialization (recommended, not mandatory).

**Incremental delivery (entirely optional — RFC stage, not merged)**
33. (Optional) `@defer`/`@stream` directive support with the non-spec validation rules from item 19.
34. (Optional) Current incremental response shape (`pending`/`incremental`/`completed`/`hasNext`) and/or legacy (`path`/`label`/`data`) shape.
35. (Optional) `multipart/mixed` HTTP transport framing per the graphql-over-http RFC.

**Semantic nullability / error behavior (entirely optional — RFC stage, not merged)**
36. (Optional) `@semanticNonNull` / service-capabilities-style nullability annotations.
37. (Optional) `@disableErrorPropagation`/`onError` directive.

**Fragment arguments (entirely optional — no stable spec text)**
38. (Optional) Do not implement against a specific grammar yet; no champion proposal as of this fetch.

**Transports**
39. (Core, for any HTTP transport) GraphQL-over-HTTP: both media types, GET and POST request shapes, full status-code table, `294 Partial Success` handling.
40. (Ecosystem) `graphql-ws` (`graphql-transport-ws` subprotocol) — all 8 message types + custom close codes (`4400`/`4401`/`4403`/`4408`/`4409`/`4429`).
41. (Ecosystem) `graphql-sse` — distinct-connections mode (simpler, HTTP/2-friendly) and/or single-connection mode (reservation token + multiplexed events) for HTTP/1 environments.
42. (Ecosystem, legacy/back-compat only) `subscriptions-transport-ws` — only if targeting old Apollo clients.
43. (Ecosystem) GraphQL multipart request spec for file uploads (`operations`/`map`/file-field convention).
44. (Ecosystem) Automatic Persisted Queries (`PERSISTED_QUERY_NOT_FOUND` handshake).
45. (Ecosystem) Request batching (array-of-operations POST body) if targeting Apollo Link Batch HTTP-style clients.

**Ecosystem specs**
46. (Ecosystem) Relay Cursor Connections (`edges`/`pageInfo`, forward/backward pagination args, `EdgesToReturn`/`PageInfo` algorithms).
47. (Ecosystem) Relay Global Object Identification (`Node` interface + `node` root field) — without assuming any mandated ID-encoding scheme.
48. (Ecosystem) Apollo Federation v2 subgraph support (`_service`, `_entities`, `@key` et al.) if targeting the dominant real-world federation ecosystem.
49. (Ecosystem) GraphQL Foundation Federation spec (`@lookup`/`@internal`/`@is`/`@require` et al.) if targeting vendor-neutral composition instead of/alongside Apollo's.
50. (Ecosystem) `@specifiedBy`-style custom scalar specs (consult `scalars.graphql.org`/`graphql-scalars` contributed specs for common scalars like `DateTime`, `URL`, `Decimal` rather than inventing bespoke ones).
