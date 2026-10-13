#!/usr/bin/env bash
#
# tool/fetch_reference.sh
#
# Builds a local, read-only GraphQL specifications & protocols knowledge base
# in reference/ (git-ignored, see .gitignore) at the repo root. Everything in
# reference/ is fetched from upstream and must never be hand-edited.
#
# Safe to re-run at any time: git checkouts are re-fetched and hard-reset to
# the pinned ref (shallow, depth 1); single-file downloads are overwritten.
# Nothing outside reference/ is touched by this script.
#
# What gets fetched (exact commit/tag of each is written to
# reference/README.md by hand after running this script; "verified
# <date>" below is when the URL/ref was last confirmed to exist):
#
#   DIRECTORY                              SOURCE                                                          WHAT / WHY
#   reference/graphql-spec-main            graphql/graphql-spec@main                                       GraphQL spec working draft (post-September2025 edits)
#   reference/graphql-spec-October2021     graphql/graphql-spec@October2021                                Previous released edition (baseline for the "what changed" diff)
#   reference/graphql-spec-September2025   graphql/graphql-spec@September2025                              Newest released edition (as of 2026-10-13)
#   reference/graphql-over-http            graphql/graphql-over-http@main                                  GraphQL-over-HTTP spec (spec/GraphQLOverHTTP.md)
#   reference/graphql-federation-spec      graphql/graphql-federation-spec@main                             GraphQL Foundation "Composite Schemas" / Federation spec.
#                                                                                                            NOTE: graphql/composite-schemas-spec (named in the task) now
#                                                                                                            redirects here on GitHub - the project was renamed.
#   reference/graphql-wg                  graphql/graphql-wg@main (sparse checkout: rfcs/ only)            RFC catalog: defer/stream, oneOf, schema coordinates,
#                                                                                                            semantic nullability, fragment arguments, composite schemas, etc.
#   reference/graphql-js                  graphql/graphql-js@17.x.x                                        Reference implementation + compliance test corpus.
#                                                                                                            NOTE: graphql-js has no "main" branch; its default/trunk
#                                                                                                            branch is named "17.x.x" (per-major-version trunk naming).
#                                                                                                            Latest released tag at fetch time: v17.0.2.
#   reference/graphql-ws                  enisdenjo/graphql-ws@master                                       graphql-ws protocol (PROTOCOL.md). Default branch is "master".
#   reference/graphql-sse                 enisdenjo/graphql-sse@master                                      GraphQL over Server-Sent Events protocol (PROTOCOL.md).
#   reference/subscriptions-transport-ws/PROTOCOL.md
#                                          apollographql/subscriptions-transport-ws@master (single file)     Legacy pre-graphql-ws subscriptions protocol. Repo is archived.
#   reference/graphql-multipart-request-spec
#                                          jaydenseric/graphql-multipart-request-spec@master                 multipart/form-data file upload spec used by most GraphQL servers/clients.
#   reference/relay-specs/Connections.md
#   reference/relay-specs/ObjectIdentification.md
#                                          facebook/relay@main website/spec/*.md (single files)              Relay Cursor Connections spec + Global Object Identification spec.
#   reference/apollo-federation/subgraph-spec.mdx
#   reference/apollo-federation/directives.mdx
#                                          apollographql/federation@main docs/source/schema-design/...       Apollo Federation v2 subgraph spec (_entities/_service, @key, ...)
#                                                                                                            and the federation directives reference.
#   reference/apollo-apq/apq.mdx           apollographql/apollo-server@main docs/source/performance/apq.mdx  Automatic Persisted Queries (APQ) protocol doc.
#   reference/graphql-scalars              graphql/graphql-scalars@main                                     Custom scalar specifications (source of scalars.graphql.org).
#   reference/defer-stream-wg               graphql/defer-stream-wg@main                                     Incremental delivery (@defer/@stream) working group repo
#                                                                                                            (Solution-Criteria.md + meeting notes); separate from graphql-wg.
#   reference/nullability-wg               graphql/nullability-wg@main                                      Semantic-nullability subcommittee repo (archived; superseded by
#                                                                                                            the SemanticNullability.md / ClientControlledNullability.md RFCs
#                                                                                                            now tracked in graphql-wg/rfcs).
#
# Usage:
#   ./tool/fetch_reference.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_DIR="$ROOT_DIR/reference"
mkdir -p "$REF_DIR"

log() {
  printf '==> %s\n' "$*"
}

# clone_or_update <dest-dir> <repo-url> <ref>
# Full shallow clone/update of one ref (branch or tag).
clone_or_update() {
  local dest="$1" url="$2" ref="$3"
  if [ -d "$dest/.git" ]; then
    log "Updating $dest ($url @ $ref)"
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" checkout -q FETCH_HEAD
    git -C "$dest" reset --hard FETCH_HEAD
  else
    log "Cloning $dest ($url @ $ref)"
    rm -rf "$dest"
    git clone --quiet --depth 1 --branch "$ref" "$url" "$dest"
  fi
}

# sparse_clone_or_update <dest-dir> <repo-url> <ref> <sparse-path...>
# Shallow clone/update restricted to the given top-level paths (for large repos).
sparse_clone_or_update() {
  local dest="$1" url="$2" ref="$3"
  shift 3
  local paths=("$@")
  if [ -d "$dest/.git" ]; then
    log "Updating (sparse) $dest ($url @ $ref)"
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" reset --hard FETCH_HEAD
  else
    log "Cloning (sparse: ${paths[*]}) $dest ($url @ $ref)"
    rm -rf "$dest"
    git clone --quiet --depth 1 --branch "$ref" --filter=blob:none --sparse "$url" "$dest"
    git -C "$dest" sparse-checkout set "${paths[@]}"
  fi
}

# fetch_file <dest-path> <url>
# Single-file download via curl, always overwritten.
fetch_file() {
  local dest="$1" url="$2"
  mkdir -p "$(dirname "$dest")"
  log "Fetching $dest <- $url"
  curl -fsSL "$url" -o "$dest"
}

# --- graphql/graphql-spec: working draft + two editions -------------------
clone_or_update "$REF_DIR/graphql-spec-main" \
  "https://github.com/graphql/graphql-spec.git" "main"

clone_or_update "$REF_DIR/graphql-spec-October2021" \
  "https://github.com/graphql/graphql-spec.git" "October2021"

clone_or_update "$REF_DIR/graphql-spec-September2025" \
  "https://github.com/graphql/graphql-spec.git" "September2025"

# --- graphql/graphql-over-http ---------------------------------------------
clone_or_update "$REF_DIR/graphql-over-http" \
  "https://github.com/graphql/graphql-over-http.git" "main"

# --- graphql/graphql-federation-spec (formerly composite-schemas-spec) ----
# graphql/composite-schemas-spec was renamed; GitHub redirects it here.
clone_or_update "$REF_DIR/graphql-federation-spec" \
  "https://github.com/graphql/graphql-federation-spec.git" "main"

# --- graphql/graphql-wg: RFCs only (full repo has many stale WG branches) --
sparse_clone_or_update "$REF_DIR/graphql-wg" \
  "https://github.com/graphql/graphql-wg.git" "main" "rfcs"

# --- graphql/graphql-js: reference implementation + compliance tests ------
# No "main" branch exists; the default/trunk branch is "17.x.x".
clone_or_update "$REF_DIR/graphql-js" \
  "https://github.com/graphql/graphql-js.git" "17.x.x"

# --- Subscription / streaming transport protocols --------------------------
clone_or_update "$REF_DIR/graphql-ws" \
  "https://github.com/enisdenjo/graphql-ws.git" "master"

clone_or_update "$REF_DIR/graphql-sse" \
  "https://github.com/enisdenjo/graphql-sse.git" "master"

fetch_file "$REF_DIR/subscriptions-transport-ws/PROTOCOL.md" \
  "https://raw.githubusercontent.com/apollographql/subscriptions-transport-ws/master/PROTOCOL.md"

# --- File upload spec --------------------------------------------------------
clone_or_update "$REF_DIR/graphql-multipart-request-spec" \
  "https://github.com/jaydenseric/graphql-multipart-request-spec.git" "master"

# --- Relay: Cursor Connections + Global Object Identification ---------------
fetch_file "$REF_DIR/relay-specs/Connections.md" \
  "https://raw.githubusercontent.com/facebook/relay/main/website/spec/Connections.md"

fetch_file "$REF_DIR/relay-specs/ObjectIdentification.md" \
  "https://raw.githubusercontent.com/facebook/relay/main/website/spec/ObjectIdentification.md"

# --- Apollo Federation subgraph spec + directives reference -----------------
fetch_file "$REF_DIR/apollo-federation/subgraph-spec.mdx" \
  "https://raw.githubusercontent.com/apollographql/federation/main/docs/source/schema-design/federated-schemas/reference/subgraph-spec.mdx"

fetch_file "$REF_DIR/apollo-federation/directives.mdx" \
  "https://raw.githubusercontent.com/apollographql/federation/main/docs/source/schema-design/federated-schemas/reference/directives.mdx"

# --- Apollo Automatic Persisted Queries (APQ) -------------------------------
fetch_file "$REF_DIR/apollo-apq/apq.mdx" \
  "https://raw.githubusercontent.com/apollographql/apollo-server/main/docs/source/performance/apq.mdx"

# --- graphql/graphql-scalars (scalars.graphql.org source) -------------------
clone_or_update "$REF_DIR/graphql-scalars" \
  "https://github.com/graphql/graphql-scalars.git" "main"

# --- Extra GraphQL Foundation working-group repos relevant to a complete
#     implementation (discovered while researching the above; not explicitly
#     named in the original source list but directly on-topic) --------------
clone_or_update "$REF_DIR/defer-stream-wg" \
  "https://github.com/graphql/defer-stream-wg.git" "main"

clone_or_update "$REF_DIR/nullability-wg" \
  "https://github.com/graphql/nullability-wg.git" "main"

log "Done. See reference/README.md for an index and pinned commits/tags."
