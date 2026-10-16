# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- `GraphQLShelfHandler`: a shelf `Handler` that serves GraphQL over HTTP
  through `GraphQLHttpHandler` (`HttpOptions` as `http`), with streamed bodies
  written unbuffered. The shelf guide is `doc/shelf.md`.
- WebSocket: `GraphQLShelfHandler(webSocket:, webSocketPingInterval:)` serves
  graphql-ws over a shelf WebSocket upgrade, after the Origin check (`403`
  with `GQL403` for a foreign origin, before `shelf_web_socket` is reached),
  with ping frames every `webSocketPingInterval` (12 seconds by default).
  Without `webSocket` such a request is an ordinary `GET`.
- `TempFileUploadStorage`: an `UploadStorage` that writes each upload to a
  file with a random name in a temporary directory, deletes a partial file when
  the content stream fails, and deletes the file on release.
- The GraphiQL page of `ServerProfile.development` is served through the
  handler (the page is the HTTP handler's).
- The README says what works, the guide is complete (a runnable program,
  WebSocket, uploads, GraphiQL, tests), `example/example.dart` serves a small
  schema, and the end-to-end tests run the transports over `shelf_io` on a
  loopback port.
