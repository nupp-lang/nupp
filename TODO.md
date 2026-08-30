# Nupp TODO

A living list, not a design record. Items are removed when completed.

## Transport security

- [ ] **A platform trust store.** `tls.ClientOptions.authority` is PEM the
      caller supplies, so verifying against the public web PKI needs roots from
      somewhere. Three designs, and they fail differently: extract the
      platform's roots and verify with mbedTLS, delegate verification to the
      platform (Security.framework, CryptoAPI), or ship a bundled list. Linux
      has no API and the file location varies by distribution.
