# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- The README says the package is not usable yet.
- `CodegenConfig.parse` reads `typed_graphql.yaml` (R7.1) into a
  `ConfigResult`; its problems are `GQL500` (YAML syntax) and `GQL501`.
