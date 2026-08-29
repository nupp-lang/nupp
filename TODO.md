# Nupp TODO

A living list, not a design record. Items are removed when completed.

The ahead-of-time backend and the native codec path above it have their own
list in [aot-todo.md](aot-todo.md), because that work has a running order and
this file deliberately does not.

## Transport security

- [ ] **Session resumption.** Tickets and session IDs, so a client reconnecting
      to a server it has met before skips the asymmetric work. Client side is a
      cache keyed by host, port, ALPN and certificate; server side is a store or
      ticket keys and their rotation. Decide where the cache lives, given that
      lanes are shared-nothing and a client reconnecting on another lane misses.
      `mbedtls_ssl_get_session`/`set_session` and `mbedtls_ssl_ticket_setup`.
      Leave TLS 1.3 early data out until replay is answered.
- [ ] **A platform trust store.** `tls.ClientOptions.authority` is PEM the
      caller supplies, so verifying against the public web PKI needs roots from
      somewhere. Three designs, and they fail differently: extract the
      platform's roots and verify with mbedTLS, delegate verification to the
      platform (Security.framework, CryptoAPI), or ship a bundled list. Linux
      has no API and the file location varies by distribution.
- [ ] **Kernel TLS offload.** Hand the session keys to the kernel after the
      handshake so records are encrypted on the socket. Removes the encryption
      ceiling a single I/O lane runs into, and is what makes `sendfile` useful
      for a TLS server. Linux `TLS_TX`/`TLS_RX`; not portable.
- [ ] **DTLS.** `nupp.io.tls` is stream-only. Datagram sessions need mbedTLS's
      `MBEDTLS_SSL_TRANSPORT_DATAGRAM`, its own timer callbacks, and a cookie
      exchange the server drives. Wanted by the same use that wanted datagrams.

## Testing and CI

- [ ] **CI matrix** (GitHub Actions). The process-only Windows job is the first
      executable slice; the project-wide matrix remains. Add macOS + Linux,
      LuaJIT 2.1 rolling (2.1.1784535649 is the floor) + (when released) 3.0;
      run `./tests/run`, the tl.lua oracle, and import-c fixture tests; track
      `bench/reification.lua` and `bench/aos.nupp` numbers as an artifact per
      commit (regression fence around the reification speedup).
