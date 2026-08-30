# Nupp TODO

A living list, not a design record. Items are removed when completed.

## Transport security

- [ ] **A platform trust store.** `tls.ClientOptions.authority` is PEM the
      caller supplies, so verifying against the public web PKI needs roots from
      somewhere. Three designs, and they fail differently: extract the
      platform's roots and verify with mbedTLS, delegate verification to the
      platform (Security.framework, CryptoAPI), or ship a bundled list. Linux
      has no API and the file location varies by distribution.
## GPU compute

- [ ] **Tensor views and chained kernels, then a tiny transformer.** Shape and
      stride validation over resident buffers, subviews without allocation, no
      broadcasting. Cooperative-matrix variants come last, behind a tolerance
      NEP, because hardware accumulation order cannot match one CPU
      definition.
