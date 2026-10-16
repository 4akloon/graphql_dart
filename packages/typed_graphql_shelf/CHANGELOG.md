# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- `GraphQLShelfHandler`: a shelf `Handler` that serves GraphQL over HTTP
  through `GraphQLHttpHandler` (`HttpOptions` as `http`), with streamed bodies
  written unbuffered. `call` never throws: an unexpected failure (a body a
  middleware already read, a host that cannot hijack) is a `500` with `GQL330`,
  reported to `HttpOptions.onError`. The shelf guide is `doc/shelf.md`.
- WebSocket: `GraphQLShelfHandler(webSocket:, webSocketPingInterval:)` serves
  graphql-ws over a WebSocket upgrade that the adapter writes itself: `403`
  with `GQL403` for a foreign origin, `400` with `GQL425` for an incomplete
  handshake (both JSON), ping frames every `webSocketPingInterval` (12 seconds
  by default; zero or negative is an `ArgumentError`), and a limit on the size
  of a frame (`3 * maxMessageLength + 1024` bytes) that closes the socket
  before the payload is buffered. The limit is per frame only: a message split into many frames is
  not bounded in total (`dart:io` buffers every frame until the last), so
  run behind a proxy that caps the size of a message. The upgrade also
  refuses a `Sec-WebSocket-Key` that is not 16 bytes in base64 (`400`,
  `GQL425`), and reports a failure after the hijack to `HttpOptions.onError`
  and closes the connection. With no `onError` an unexpected error is a
  `500` that is not logged. Without `webSocket`
  such a request is an ordinary `GET`.
- `TempFileUploadStorage`: an `UploadStorage` that writes each upload to an
  exclusively created file with a random name, in a private directory (mode
  `0700` on POSIX, removed again when `chmod` fails or cannot run) it makes under the system temporary directory or in the
  directory you give, deletes a partial file when the content stream fails
  or the file cannot be measured, and deletes the file on release.
- The GraphiQL page of `ServerProfile.development` is served through the
  handler (the page is the HTTP handler's).
- The guide documents what `shelf_io` decides (early refusals arrive after
  the whole body, a disconnect during a fixed response is not noticed), so
  run behind a proxy; `example/example.dart` serves a small schema, and the
  end-to-end tests run the transports over `shelf_io` on a loopback port.
