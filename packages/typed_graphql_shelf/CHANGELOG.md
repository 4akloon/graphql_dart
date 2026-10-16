# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- The README says the package is not usable yet.
- `GraphQLShelfHandler`: a shelf `Handler` that serves GraphQL over HTTP
  through `GraphQLHttpHandler` (`HttpOptions` as `http`), with streamed bodies
  written unbuffered. The shelf guide is `doc/shelf.md`.
- WebSocket: `GraphQLShelfHandler(webSocket:, webSocketPingInterval:)` serves
  graphql-ws over a shelf WebSocket upgrade, after the Origin check (`403`
  with `GQL403` for a foreign origin).
