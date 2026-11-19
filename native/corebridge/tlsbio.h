/**
 * @file
 * @brief Bounded, transport-independent TLS over a pinned OpenSSL BIO pair.
 */

#ifndef NUPP_CORE_TLSBIO_H
#define NUPP_CORE_TLSBIO_H

#include <stddef.h>
#include <stdint.h>

typedef struct NuppTls NuppTls;

typedef struct NuppTlsBytes {
  const char *data;
  size_t size;
} NuppTlsBytes;

typedef struct NuppTlsOptions {
  const char *hostname;
  NuppTlsBytes certificate, private_key, authority, protocols;
  unsigned int port;
  int server, verify;
} NuppTlsOptions;

enum {
  NUPP_TLS_WINDOW = 16384,
  NUPP_TLS_AGAIN = INT32_MIN,
  NUPP_TLS_ERROR = INT32_MIN + 1
};

/** Creates an owned TLS state. Borrows options only for the call. */
NuppTls *nupptlsopen (const NuppTlsOptions *options, char *why, size_t room);

/** Discards TLS state and both BIO ends. Does no I/O. */
void nupptlsfree (NuppTls *tls);

/** Releases the bounded configuration and session cache on its owner thread. */
void nupptlsclear (void);

/** Advances the handshake. Returns 1, AGAIN, or ERROR. */
int nupptlshandshake (NuppTls *tls);

/** Copies plaintext into caller storage. Returns bytes, 0 at EOF or a status.
 */
int nupptlsread (NuppTls *tls, void *out, size_t room);

/** Copies one admitted plaintext chunk. Returns bytes written or a status. */
int nupptlswrite (NuppTls *tls, const void *bytes, size_t size);

/** Advances queued work and returns 1 when all TLS output is consumed. */
int nupptlsflushed (NuppTls *tls);

/** Queues close_notify and reports progress without waiting for the peer. */
int nupptlsclose (NuppTls *tls);

/** Returns how many ciphertext bytes the input BIO can accept immediately. */
size_t nupptlsroom (NuppTls *tls);

/** Copies ciphertext into the TLS engine. Returns consumed bytes or a status.
 */
int nupptlsfeed (NuppTls *tls, const void *bytes, size_t size);

/** States that the transport will not provide more ciphertext. */
void nupptlseof (NuppTls *tls);

/** Borrows the next contiguous ciphertext output until the next TLS call. */
size_t nupptlsoutput (NuppTls *tls, const char **bytes);

/** Releases exactly the supplied prefix of the last available output. */
int nupptlsconsumed (NuppTls *tls, size_t size);

/** Reports handshake, verification and resumption state. */
int nupptlsready (const NuppTls *tls);
int nupptlsverified (const NuppTls *tls);
int nupptlsresumed (const NuppTls *tls);

/** Borrows the selected protocol or recorded failure until the next call. */
NuppTlsBytes nupptlsprotocol (const NuppTls *tls);
const char *nupptlswhy (const NuppTls *tls);

#endif
