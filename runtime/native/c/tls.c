/* TLS over a socket, on mbedTLS.
 *
 * A session wraps a connection this process already has: `nupp.io.net` owns the
 * socket and this owns the encryption over it. The two meet in C rather than in
 * Lua, which is the whole reason this file exists at all -- mbedTLS drives its
 * transport through function pointers, and a callback that reached Lua would
 * both abort trace recording and put a garbage collector underneath a
 * handshake.
 *
 * Nothing here blocks. The BIO callbacks answer `WANT_READ` and `WANT_WRITE`
 * when the socket has nothing to give or cannot take more, mbedTLS returns the
 * same to its caller, and the Lua side drives the reactor and comes back --
 * exactly as it already does for a plain socket.
 */

#include "nupp_native.h"
#include "nupp_net.h"

#include <mbedtls/ssl.h>
#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/x509_crt.h>
#include <mbedtls/pk.h>
#include <mbedtls/error.h>
#include <mbedtls/platform_util.h>
#include <mbedtls/sha256.h>
#include <mbedtls/ssl_cache.h>
#include <mbedtls/ssl_ticket.h>

#include <uv.h>

#include <stdlib.h>
#include <string.h>

/* What a nonblocking answer is, for a caller that has to tell "not yet" from
 * "never". These have to be distinct: one means come back, the other means stop,
 * and a caller that cannot tell them apart retries a permanent failure forever.
 * A message accompanies TLS_FAILED in the error slot. */
#define TLS_WOULD_BLOCK (-1)
#define TLS_FAILED (-2)

/* mbedTLS spells these in `net_sockets.h`, which is its own socket layer: the
 * one thing this file exists to not use. The codes are part of its public error
 * space, so they are named here rather than dragging a second transport in for
 * two constants. */
#define NUPP_TLS_SEND_FAILED (-0x004E)
#define NUPP_TLS_RECV_FAILED (-0x004C)

/* Resumption state belongs to the process rather than to a Lua state. Worker
 * lanes are shared-nothing Lua states, so a Lua table here would make a client
 * pay for a full handshake whenever its next connection landed on another
 * lane. The bounded native stores below are shared by all of them instead. */
#define TLS_CLIENT_CACHE_MAX 128
#define TLS_SERVER_STORE_MAX 32
#define TLS_TICKET_LIFETIME 86400u

typedef struct {
    bool used;
    unsigned char key[32];
    unsigned char certificate[32];
    bool hasCertificate;
    unsigned char *serialized;
    size_t serializedLength;
    uint64_t lastUsed;
} TlsClientCacheEntry;

typedef struct {
    bool used;
    bool transient;
    unsigned char key[32];
    size_t references;
    uint64_t lastUsed;
    uv_mutex_t guard;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_ssl_cache_context sessions;
    mbedtls_ssl_ticket_context tickets;
} TlsServerStoreEntry;

static TlsClientCacheEntry clientCache[TLS_CLIENT_CACHE_MAX];
static TlsServerStoreEntry serverStores[TLS_SERVER_STORE_MAX];
static uv_mutex_t clientCacheGuard;
static uv_mutex_t serverStoresGuard;
static uv_once_t storesOnce = UV_ONCE_INIT;
static bool storesReady;
static uint64_t clientCacheClock;
static uint64_t serverStoreClock;

static void tls_fail(int code, const char *what);

static void tls_stores_init(void) {
    if (uv_mutex_init(&clientCacheGuard) != 0) {
        return;
    }
    if (uv_mutex_init(&serverStoresGuard) != 0) {
        uv_mutex_destroy(&clientCacheGuard);
        return;
    }
    storesReady = true;
}

static bool tls_stores(void) {
    uv_once(&storesOnce, tls_stores_init);
    return storesReady;
}

/* Length-prefix each hash component. Concatenating configuration bytes would
 * make {"ab", "c"} and {"a", "bc"} one server identity, which would let
 * their ticket keys cross a configuration boundary. */
static void tls_digest_part(
    mbedtls_sha256_context *digest,
    const void *bytes,
    size_t length
) {
    unsigned char size[8];
    size_t at;
    uint64_t wide = (uint64_t)length;
    for (at = 0; at < sizeof size; at++) {
        size[sizeof size - at - 1] = (unsigned char)(wide >> (at * 8));
    }
    mbedtls_sha256_update(digest, size, sizeof size);
    if (length != 0) {
        mbedtls_sha256_update(digest, bytes, length);
    }
}

static void tls_digest_config(
    unsigned char out[32],
    const uint8_t *first,
    size_t firstLength,
    const uint8_t *second,
    size_t secondLength,
    const uint8_t *third,
    size_t thirdLength,
    const uint8_t *fourth,
    size_t fourthLength,
    bool verify
) {
    mbedtls_sha256_context digest;
    unsigned char checked = verify ? 1 : 0;
    mbedtls_sha256_init(&digest);
    mbedtls_sha256_starts(&digest, 0);
    tls_digest_part(&digest, first, firstLength);
    tls_digest_part(&digest, second, secondLength);
    tls_digest_part(&digest, third, thirdLength);
    tls_digest_part(&digest, fourth, fourthLength);
    tls_digest_part(&digest, &checked, sizeof checked);
    mbedtls_sha256_finish(&digest, out);
    mbedtls_sha256_free(&digest);
}

static int tls_ticket_write(
    void *context,
    const mbedtls_ssl_session *session,
    unsigned char *start,
    const unsigned char *end,
    size_t *length,
    uint32_t *lifetime
) {
    TlsServerStoreEntry *store = context;
    int state;
    uv_mutex_lock(&store->guard);
    state = mbedtls_ssl_ticket_write(
        &store->tickets, session, start, end, length, lifetime);
    uv_mutex_unlock(&store->guard);
    return state;
}

static int tls_ticket_parse(
    void *context,
    mbedtls_ssl_session *session,
    unsigned char *bytes,
    size_t length
) {
    TlsServerStoreEntry *store = context;
    int state;
    uv_mutex_lock(&store->guard);
    state = mbedtls_ssl_ticket_parse(&store->tickets, session, bytes, length);
    uv_mutex_unlock(&store->guard);
    return state;
}

static int tls_session_get(
    void *context,
    const unsigned char *id,
    size_t idLength,
    mbedtls_ssl_session *session
) {
    TlsServerStoreEntry *store = context;
    int state;
    uv_mutex_lock(&store->guard);
    state = mbedtls_ssl_cache_get(&store->sessions, id, idLength, session);
    uv_mutex_unlock(&store->guard);
    return state;
}

static int tls_session_set(
    void *context,
    const unsigned char *id,
    size_t idLength,
    const mbedtls_ssl_session *session
) {
    TlsServerStoreEntry *store = context;
    int state;
    uv_mutex_lock(&store->guard);
    state = mbedtls_ssl_cache_set(&store->sessions, id, idLength, session);
    uv_mutex_unlock(&store->guard);
    return state;
}

static void tls_server_store_free(TlsServerStoreEntry *store) {
    mbedtls_ssl_ticket_free(&store->tickets);
    mbedtls_ssl_cache_free(&store->sessions);
    mbedtls_ctr_drbg_free(&store->drbg);
    mbedtls_entropy_free(&store->entropy);
    uv_mutex_destroy(&store->guard);
    memset(store, 0, sizeof *store);
}

static bool tls_server_store_init(
    TlsServerStoreEntry *store,
    const unsigned char key[32]
) {
    int failed;
    memset(store, 0, sizeof *store);
    if (uv_mutex_init(&store->guard) != 0) {
        nupp_fail("tls: the server session store could not be locked");
        return false;
    }
    mbedtls_entropy_init(&store->entropy);
    mbedtls_ctr_drbg_init(&store->drbg);
    mbedtls_ssl_cache_init(&store->sessions);
    mbedtls_ssl_ticket_init(&store->tickets);
    failed = mbedtls_ctr_drbg_seed(
        &store->drbg, mbedtls_entropy_func, &store->entropy,
        key, 32);
    if (failed == 0) {
        failed = mbedtls_ssl_ticket_setup(
            &store->tickets,
            mbedtls_ctr_drbg_random,
            &store->drbg,
            MBEDTLS_CIPHER_AES_256_GCM,
            TLS_TICKET_LIFETIME);
    }
    if (failed != 0) {
        tls_fail(failed, "the server session store could not be seeded");
        tls_server_store_free(store);
        return false;
    }
    memcpy(store->key, key, sizeof store->key);
    store->used = true;
    return true;
}

static TlsServerStoreEntry *tls_server_store_acquire(
    const unsigned char key[32]
) {
    TlsServerStoreEntry *choice = NULL;
    size_t at;
    if (!tls_stores()) {
        nupp_fail("tls: the process session store could not be initialized");
        return NULL;
    }
    uv_mutex_lock(&serverStoresGuard);
    for (at = 0; at < TLS_SERVER_STORE_MAX; at++) {
        if (serverStores[at].used &&
            memcmp(serverStores[at].key, key, 32) == 0) {
            choice = &serverStores[at];
            break;
        }
        if (!serverStores[at].used || serverStores[at].references == 0) {
            if (choice == NULL || !choice->used ||
                (serverStores[at].used &&
                 serverStores[at].lastUsed < choice->lastUsed)) {
                choice = &serverStores[at];
            }
        }
    }
    if (choice == NULL) {
        choice = calloc(1, sizeof *choice);
        if (choice == NULL) {
            nupp_fail("tls: out of memory for the server session store");
            uv_mutex_unlock(&serverStoresGuard);
            return NULL;
        }
        if (!tls_server_store_init(choice, key)) {
            free(choice);
            uv_mutex_unlock(&serverStoresGuard);
            return NULL;
        }
        /* A thirty-third simultaneously active server identity still gets a
         * TLS connection. Its store is private to that connection until a
         * process slot is free, so capacity limits resumption rather than TLS. */
        choice->transient = true;
        choice->references = 1;
        choice->lastUsed = ++serverStoreClock;
        uv_mutex_unlock(&serverStoresGuard);
        return choice;
    }
    if (!choice->used || memcmp(choice->key, key, 32) != 0) {
        if (choice->used) {
            tls_server_store_free(choice);
        }
        if (!tls_server_store_init(choice, key)) {
            uv_mutex_unlock(&serverStoresGuard);
            return NULL;
        }
    }
    choice->references++;
    choice->lastUsed = ++serverStoreClock;
    uv_mutex_unlock(&serverStoresGuard);
    return choice;
}

static void tls_server_store_release(TlsServerStoreEntry *store) {
    if (store == NULL || !tls_stores()) {
        return;
    }
    uv_mutex_lock(&serverStoresGuard);
    if (store->transient) {
        uv_mutex_unlock(&serverStoresGuard);
        tls_server_store_free(store);
        free(store);
        return;
    }
    if (store->references > 0) {
        store->references--;
    }
    store->lastUsed = ++serverStoreClock;
    uv_mutex_unlock(&serverStoresGuard);
}

struct NuppTls {
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config config;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_x509_crt chain;
    mbedtls_x509_crt authority;
    mbedtls_pk_context key;

    TlsServerStoreEntry *serverStore;
    unsigned char cacheKey[32];
    unsigned char cacheCertificate[32];
    bool cacheKeyReady;
    bool cacheCertificateReady;

    NuppNetStream *stream;

    /* The protocol list, owned here because mbedTLS records the pointer rather
     * than the contents: its documentation requires the table to outlive the
     * configuration, so a list built on the caller's stack would be a dangling
     * read at the first handshake rather than at the call that set it. */
    char *alpnBytes;
    const char **alpn;

    bool server;
    bool handshaken;
    bool failed;
    bool closed;
    bool resumptionOffered;
    bool sawPeerCertificate;
    bool resumed;
    int failure;
};

typedef struct NuppTls NuppTls;

static int tls_verify_observe(
    void *context,
    mbedtls_x509_crt *certificate,
    int depth,
    uint32_t *flags
) {
    NuppTls *session = context;
    (void)certificate;
    (void)depth;
    (void)flags;
    session->sawPeerCertificate = true;
    return 0;
}

static void tls_client_cache_key(
    NuppTls *session,
    const uint8_t *hostname,
    size_t hostnameLength,
    const uint8_t *authority,
    size_t authorityLength,
    const uint8_t *protocols,
    size_t protocolsLength,
    bool verify
) {
    char peer[64];
    int32_t port = 0;
    unsigned char portBytes[4];
    const uint8_t *host = hostname;
    size_t hostLength = hostnameLength;
    if (nuppNetStreamPeer(session->stream, peer, sizeof peer, &port) &&
        hostLength == 0) {
        host = (const uint8_t *)peer;
        hostLength = strlen(peer);
    }
    portBytes[0] = (unsigned char)((uint32_t)port >> 24);
    portBytes[1] = (unsigned char)((uint32_t)port >> 16);
    portBytes[2] = (unsigned char)((uint32_t)port >> 8);
    portBytes[3] = (unsigned char)port;
    tls_digest_config(
        session->cacheKey,
        host, hostLength,
        portBytes, sizeof portBytes,
        protocols, protocolsLength,
        authority, authorityLength,
        verify);
    session->cacheKeyReady = true;
}

static void tls_client_cache_entry_clear(TlsClientCacheEntry *entry) {
    if (entry->serialized != NULL) {
        mbedtls_platform_zeroize(
            entry->serialized, entry->serializedLength);
        free(entry->serialized);
    }
    memset(entry, 0, sizeof *entry);
}

static bool tls_client_cache_load(NuppTls *session) {
    mbedtls_ssl_session saved;
    TlsClientCacheEntry *entry = NULL;
    size_t at;
    int failed;
    if (!session->cacheKeyReady || !tls_stores()) {
        return false;
    }
    mbedtls_ssl_session_init(&saved);
    uv_mutex_lock(&clientCacheGuard);
    for (at = 0; at < TLS_CLIENT_CACHE_MAX; at++) {
        if (clientCache[at].used &&
            memcmp(clientCache[at].key, session->cacheKey, 32) == 0) {
            if (entry == NULL || clientCache[at].lastUsed > entry->lastUsed) {
                entry = &clientCache[at];
            }
        }
    }
    if (entry == NULL) {
        uv_mutex_unlock(&clientCacheGuard);
        mbedtls_ssl_session_free(&saved);
        return false;
    }
    failed = mbedtls_ssl_session_load(
        &saved, entry->serialized, entry->serializedLength);
    if (failed == 0) {
        entry->lastUsed = ++clientCacheClock;
        if (entry->hasCertificate) {
            memcpy(session->cacheCertificate,
                entry->certificate, sizeof session->cacheCertificate);
            session->cacheCertificateReady = true;
        }
    } else {
        tls_client_cache_entry_clear(entry);
    }
    uv_mutex_unlock(&clientCacheGuard);
    if (failed == 0) {
        failed = mbedtls_ssl_set_session(&session->ssl, &saved);
    }
    mbedtls_ssl_session_free(&saved);
    return failed == 0;
}

static void tls_client_cache_save(NuppTls *session) {
    mbedtls_ssl_session saved;
    const mbedtls_x509_crt *certificate;
    TlsClientCacheEntry *choice = NULL;
    unsigned char fingerprint[32];
    unsigned char *serialized = NULL;
    size_t serializedLength = 0;
    size_t serializedCapacity;
    size_t at;
    int failed;
    bool hasCertificate = false;
    if (session->server || !session->cacheKeyReady || !tls_stores()) {
        return;
    }
    mbedtls_ssl_session_init(&saved);
    failed = mbedtls_ssl_get_session(&session->ssl, &saved);
    if (failed != 0) {
        mbedtls_ssl_session_free(&saved);
        return;
    }
    failed = mbedtls_ssl_session_save(&saved, NULL, 0, &serializedLength);
    if (failed != MBEDTLS_ERR_SSL_BUFFER_TOO_SMALL || serializedLength == 0) {
        mbedtls_ssl_session_free(&saved);
        return;
    }
    serializedCapacity = serializedLength;
    serialized = malloc(serializedCapacity);
    if (serialized == NULL) {
        mbedtls_ssl_session_free(&saved);
        return;
    }
    failed = mbedtls_ssl_session_save(
        &saved, serialized, serializedCapacity, &serializedLength);
    mbedtls_ssl_session_free(&saved);
    if (failed != 0) {
        mbedtls_platform_zeroize(serialized, serializedCapacity);
        free(serialized);
        return;
    }
    certificate = mbedtls_ssl_get_peer_cert(&session->ssl);
    if (certificate != NULL && certificate->raw.p != NULL) {
        hasCertificate = mbedtls_sha256(
            certificate->raw.p, certificate->raw.len, fingerprint, 0) == 0;
    } else if (session->cacheCertificateReady) {
        memcpy(fingerprint,
            session->cacheCertificate, sizeof session->cacheCertificate);
        hasCertificate = true;
    }
    if (hasCertificate) {
        memcpy(session->cacheCertificate, fingerprint, sizeof fingerprint);
        session->cacheCertificateReady = true;
    }

    uv_mutex_lock(&clientCacheGuard);
    for (at = 0; at < TLS_CLIENT_CACHE_MAX; at++) {
        if (clientCache[at].used &&
            memcmp(clientCache[at].key, session->cacheKey, 32) == 0 &&
            clientCache[at].hasCertificate == hasCertificate &&
            (!hasCertificate || memcmp(
                clientCache[at].certificate, fingerprint, 32) == 0)) {
            choice = &clientCache[at];
            break;
        }
        if (choice == NULL || !clientCache[at].used ||
            (choice->used && clientCache[at].used &&
             clientCache[at].lastUsed < choice->lastUsed)) {
            choice = &clientCache[at];
        }
    }
    tls_client_cache_entry_clear(choice);
    choice->used = true;
    memcpy(choice->key, session->cacheKey, sizeof choice->key);
    if (hasCertificate) {
        memcpy(choice->certificate, fingerprint, sizeof fingerprint);
        choice->hasCertificate = true;
    }
    choice->serialized = serialized;
    choice->serializedLength = serializedLength;
    choice->lastUsed = ++clientCacheClock;
    uv_mutex_unlock(&clientCacheGuard);
}

/* mbedTLS wants a message for a code; it does not have one to hand without
 * being asked. */
static void tls_fail(int code, const char *what) {
    char text[128];
    mbedtls_strerror(code, text, sizeof text);
    nupp_fail_format("tls: %s: %s", what, text);
}

/* --- the transport ------------------------------------------------------ */

/* The two halves of the reason this is C. Each hands bytes straight to the
 * socket beside it and reports "not yet" in mbedTLS's spelling. */
static int tls_send(void *context, const unsigned char *bytes, size_t length) {
    NuppTls *session = context;
    intptr_t took = nuppNetTryWrite(session->stream, bytes, length);
    if (took < 0) {
        return NUPP_TLS_SEND_FAILED;
    }
    if (took == 0 && length > 0) {
        return MBEDTLS_ERR_SSL_WANT_WRITE;
    }
    return (int)took;
}

static int tls_recv(void *context, unsigned char *into, size_t length) {
    NuppTls *session = context;
    intptr_t got = nuppNetTryRead(session->stream, into, length);
    if (got < 0) {
        return NUPP_TLS_RECV_FAILED;
    }
    if (got == 0) {
        /* Nothing yet and the peer finished are different answers, and only the
         * socket knows which this is. Reporting the end as "want read" would
         * hang a handshake against a peer that has gone. */
        if (nuppNetStreamEnded(session->stream)) {
            return 0;
        }
        return MBEDTLS_ERR_SSL_WANT_READ;
    }
    return (int)got;
}

/* --- sessions ----------------------------------------------------------- */

/* Adopts a NUL-separated protocol list as the array mbedTLS wants.
 *
 * NUL-separated rather than delimited by anything printable, because a protocol
 * name is arbitrary bytes and any delimiter chosen from them is a name somebody
 * may legitimately want. The entries are already terminated in place once the
 * buffer is copied, so the array is pointers into it and not a second copy. */
static bool tls_alpn_adopt(NuppTls *session, const uint8_t *bytes, size_t length) {
    size_t at;
    size_t count = 0;
    size_t slot = 0;

    if (bytes == NULL || length == 0) {
        return true;
    }
    session->alpnBytes = malloc(length + 1);
    if (session->alpnBytes == NULL) {
        return false;
    }
    memcpy(session->alpnBytes, bytes, length);
    session->alpnBytes[length] = '\0';

    for (at = 0; at < length; at++) {
        if (session->alpnBytes[at] == '\0') {
            count++;
        }
    }
    if (count == 0) {
        return false;
    }
    session->alpn = calloc(count + 1, sizeof *session->alpn);
    if (session->alpn == NULL) {
        return false;
    }
    session->alpn[slot++] = session->alpnBytes;
    for (at = 0; at + 1 < length; at++) {
        if (session->alpnBytes[at] == '\0' && slot < count) {
            session->alpn[slot++] = session->alpnBytes + at + 1;
        }
    }
    session->alpn[count] = NULL;
    return true;
}

static void tls_free(NuppTls *session) {
    mbedtls_ssl_free(&session->ssl);
    mbedtls_ssl_config_free(&session->config);
    mbedtls_ctr_drbg_free(&session->drbg);
    mbedtls_entropy_free(&session->entropy);
    mbedtls_x509_crt_free(&session->chain);
    mbedtls_x509_crt_free(&session->authority);
    mbedtls_pk_free(&session->key);
    tls_server_store_release(session->serverStore);
    nuppNetStreamRelease(session->stream);
    free(session->alpn);
    free(session->alpnBytes);
    free(session);
}

/* Wraps a connection.
 *
 * The socket is not owned here and is not closed here: `nupp.io.net` handed it
 * over to be encrypted, not given away, and one owner is the whole of what the
 * affine layer above is enforcing.
 */
NUPP_EXPORT NuppTls *nuppTlsWrap(
    NuppNetStream *stream,
    bool server,
    const uint8_t *hostname,
    size_t hostnameLength,
    const uint8_t *certificate,
    size_t certificateLength,
    const uint8_t *privateKey,
    size_t privateKeyLength,
    const uint8_t *authority,
    size_t authorityLength,
    const uint8_t *protocols,
    size_t protocolsLength,
    bool verify
) {
    NuppTls *session;
    int failed;

    if (stream == NULL) {
        nupp_fail("tls: wrapping needs a connection");
        return NULL;
    }
    session = calloc(1, sizeof *session);
    if (session == NULL) {
        nupp_fail("tls: out of memory");
        return NULL;
    }
    session->stream = stream;
    /* Held, so that the socket struct outlives the owner releasing it. The
     * connection stops working the moment its owner closes it -- that is the
     * point -- but asking whether it did must not read freed memory. */
    nuppNetStreamRetain(stream);
    session->server = server;
    mbedtls_ssl_init(&session->ssl);
    mbedtls_ssl_config_init(&session->config);
    mbedtls_entropy_init(&session->entropy);
    mbedtls_ctr_drbg_init(&session->drbg);
    mbedtls_x509_crt_init(&session->chain);
    mbedtls_x509_crt_init(&session->authority);
    mbedtls_pk_init(&session->key);

    failed = mbedtls_ctr_drbg_seed(&session->drbg, mbedtls_entropy_func,
        &session->entropy, (const unsigned char *)"nupp.io.tls", 11);
    if (failed != 0) {
        tls_fail(failed, "the random generator could not be seeded");
        tls_free(session);
        return NULL;
    }

    failed = mbedtls_ssl_config_defaults(&session->config,
        server ? MBEDTLS_SSL_IS_SERVER : MBEDTLS_SSL_IS_CLIENT,
        MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (failed != 0) {
        tls_fail(failed, "the session could not be configured");
        tls_free(session);
        return NULL;
    }
    mbedtls_ssl_conf_rng(&session->config, mbedtls_ctr_drbg_random, &session->drbg);

    /* mbedTLS wants its PEM NUL-terminated and counts the NUL, which is a
     * pointer arithmetic mistake waiting to be made once per caller. */
    if (certificate != NULL && certificateLength > 0) {
        failed = mbedtls_x509_crt_parse(&session->chain, certificate, certificateLength + 1);
        if (failed != 0) {
            tls_fail(failed, "the certificate could not be read");
            tls_free(session);
            return NULL;
        }
    }
    if (privateKey != NULL && privateKeyLength > 0) {
        failed = mbedtls_pk_parse_key(&session->key, privateKey, privateKeyLength + 1,
            NULL, 0, mbedtls_ctr_drbg_random, &session->drbg);
        if (failed != 0) {
            tls_fail(failed, "the private key could not be read");
            tls_free(session);
            return NULL;
        }
        failed = mbedtls_ssl_conf_own_cert(&session->config, &session->chain, &session->key);
        if (failed != 0) {
            tls_fail(failed, "the certificate and key were not accepted");
            tls_free(session);
            return NULL;
        }
    }
    if (authority != NULL && authorityLength > 0) {
        failed = mbedtls_x509_crt_parse(&session->authority, authority, authorityLength + 1);
        if (failed != 0) {
            tls_fail(failed, "the trusted certificates could not be read");
            tls_free(session);
            return NULL;
        }
        mbedtls_ssl_conf_ca_chain(&session->config, &session->authority, NULL);
    }
    mbedtls_ssl_conf_authmode(&session->config,
        verify ? MBEDTLS_SSL_VERIFY_REQUIRED :
        (server ? MBEDTLS_SSL_VERIFY_NONE : MBEDTLS_SSL_VERIFY_OPTIONAL));

    if (server) {
        unsigned char storeKey[32];
        tls_digest_config(
            storeKey,
            certificate, certificateLength,
            privateKey, privateKeyLength,
            authority, authorityLength,
            protocols, protocolsLength,
            verify);
        session->serverStore = tls_server_store_acquire(storeKey);
        if (session->serverStore == NULL) {
            tls_free(session);
            return NULL;
        }
        mbedtls_ssl_conf_session_cache(
            &session->config,
            session->serverStore,
            tls_session_get,
            tls_session_set);
        mbedtls_ssl_conf_session_tickets_cb(
            &session->config,
            tls_ticket_write,
            tls_ticket_parse,
            session->serverStore);
    } else {
        tls_client_cache_key(
            session,
            hostname, hostnameLength,
            authority, authorityLength,
            protocols, protocolsLength,
            verify);
        /* TLS 1.3 tickets arrive after the handshake. Signalling them makes
         * the read path save each one rather than silently discarding it.
         * Early data remains disabled in the mbedTLS configuration. */
#if defined(MBEDTLS_SSL_PROTO_TLS1_3)
        mbedtls_ssl_conf_tls13_enable_signal_new_session_tickets(
            &session->config,
            MBEDTLS_SSL_TLS1_3_SIGNAL_NEW_SESSION_TICKETS_ENABLED);
#endif
        mbedtls_ssl_conf_verify(
            &session->config, tls_verify_observe, session);
    }

    if (protocols != NULL && protocolsLength > 0) {
        if (!tls_alpn_adopt(session, protocols, protocolsLength)) {
            nupp_fail("tls: the protocol list could not be read");
            tls_free(session);
            return NULL;
        }
        failed = mbedtls_ssl_conf_alpn_protocols(&session->config, session->alpn);
        if (failed != 0) {
            tls_fail(failed, "the protocol list was not accepted");
            tls_free(session);
            return NULL;
        }
    }

    failed = mbedtls_ssl_setup(&session->ssl, &session->config);
    if (failed != 0) {
        tls_fail(failed, "the session could not be set up");
        tls_free(session);
        return NULL;
    }
    if (!server && hostname != NULL && hostnameLength > 0) {
        NuppText text;
        if (!nupp_text(&text, hostname, hostnameLength, "hostname")) {
            tls_free(session);
            return NULL;
        }
        failed = mbedtls_ssl_set_hostname(&session->ssl, text.value);
        nupp_text_free(&text);
        if (failed != 0) {
            tls_fail(failed, "the peer name could not be set");
            tls_free(session);
            return NULL;
        }
    }
    if (!server) {
        session->resumptionOffered = tls_client_cache_load(session);
    }
    mbedtls_ssl_set_bio(&session->ssl, session, tls_send, tls_recv, NULL);
    return session;
}

/* Drives the handshake as far as it will go without blocking. Answers 1 when it
 * is finished, 0 when it needs the socket to do something first, and -1 when it
 * failed. */
NUPP_EXPORT int32_t nuppTlsHandshake(NuppTls *session) {
    int state;
    if (session == NULL || session->closed) {
        nupp_fail("tls: the session is closed");
        return -1;
    }
    if (session->handshaken) {
        return 1;
    }
    if (session->failed) {
        tls_fail(session->failure, "the handshake failed");
        return -1;
    }
    state = mbedtls_ssl_handshake(&session->ssl);
#if defined(MBEDTLS_SSL_PROTO_TLS1_3)
    if (state == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) {
        tls_client_cache_save(session);
        return 0;
    }
#endif
    if (state == 0) {
        session->handshaken = true;
        session->resumed = session->resumptionOffered &&
            !session->sawPeerCertificate;
        /* A TLS 1.3 ticket is a post-handshake message. Before that arrives,
         * get_session can serialize negotiated state but nothing resumable. */
        if (strcmp(mbedtls_ssl_get_version(&session->ssl), "TLSv1.3") != 0) {
            tls_client_cache_save(session);
        }
        return 1;
    }
    if (state == MBEDTLS_ERR_SSL_WANT_READ || state == MBEDTLS_ERR_SSL_WANT_WRITE) {
        return 0;
    }
    session->failed = true;
    session->failure = state;
    tls_fail(state, "the handshake failed");
    return -1;
}

/* The application protocol both sides agreed on, or NULL when none was
 * negotiated -- because neither offered a list, or because the handshake has not
 * happened yet. A server offered a list with nothing in common with the client's
 * does not reach here at all: that is a fatal alert, not an empty answer. */
NUPP_EXPORT const char *nuppTlsAlpn(NuppTls *session) {
    if (session == NULL || !session->handshaken) {
        return NULL;
    }
    return mbedtls_ssl_get_alpn_protocol(&session->ssl);
}

/* Whether the peer's certificate satisfied what was asked of it. Answers zero
 * when it did, and mbedTLS's flags when it did not, so a caller can say which
 * part was wrong rather than only that something was. */
NUPP_EXPORT uint32_t nuppTlsVerifyResult(NuppTls *session) {
    if (session == NULL) {
        return (uint32_t)-1;
    }
    return mbedtls_ssl_get_verify_result(&session->ssl);
}

/* Whether this client handshake used cached key material. Servers answer false:
 * their session-ID and ticket callbacks know that a value was accepted while
 * mbedTLS deliberately exposes no durable post-handshake flag for it. */
NUPP_EXPORT bool nuppTlsResumed(NuppTls *session) {
    return session != NULL && session->handshaken && session->resumed;
}

/* Reads decrypted bytes. Zero means the peer closed its sending half, which is
 * the same three-state answer the socket beneath already gives; -1 is a
 * failure and TLS_WOULD_BLOCK is "not yet". */
NUPP_EXPORT intptr_t nuppTlsRead(NuppTls *session, uint8_t *into, size_t wanted) {
    int got;
    unsigned int tickets = 0;
    if (session == NULL || session->closed) {
        nupp_fail("tls: the session is closed");
        return TLS_FAILED;
    }
    if (!session->handshaken) {
        nupp_fail("tls: the handshake has not finished");
        return TLS_FAILED;
    }
    do {
        got = mbedtls_ssl_read(&session->ssl, into, wanted);
#if defined(MBEDTLS_SSL_PROTO_TLS1_3)
        if (got == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) {
            tls_client_cache_save(session);
            if (++tickets == 8) {
                return TLS_WOULD_BLOCK;
            }
        }
    } while (got == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET);
#else
    } while (false);
#endif
    if (got > 0) {
        return (intptr_t)got;
    }
    /* Zero is the transport's read end closing, which is not the session
     * ending: the peer went away without saying it was finished, so what was
     * received is the front of a stream and not the whole of one. Reporting it
     * as a clean end is the truncation this module exists to refuse, so it is a
     * failure with a message that says which kind. */
    if (got == 0) {
        session->failed = true;
        nupp_fail("tls: the peer closed the connection without ending the session");
        return TLS_FAILED;
    }
    if (got == MBEDTLS_ERR_SSL_WANT_READ || got == MBEDTLS_ERR_SSL_WANT_WRITE) {
        return TLS_WOULD_BLOCK;
    }
    /* The peer said it was finished. This is the only clean end there is. */
    if (got == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) {
        return 0;
    }
    session->failed = true;
    tls_fail(got, "could not read");
    return TLS_FAILED;
}

/* Writes plaintext, answering how much of it was taken. A partial answer is
 * ordinary: a record has a size and the socket beneath has a queue. */
NUPP_EXPORT intptr_t nuppTlsWrite(NuppTls *session, const uint8_t *bytes, size_t length) {
    int took;
    if (session == NULL || session->closed) {
        nupp_fail("tls: the session is closed");
        return TLS_FAILED;
    }
    if (!session->handshaken) {
        nupp_fail("tls: the handshake has not finished");
        return TLS_FAILED;
    }
    if (length == 0) {
        return 0;
    }
    took = mbedtls_ssl_write(&session->ssl, bytes, length);
    if (took >= 0) {
        return (intptr_t)took;
    }
    if (took == MBEDTLS_ERR_SSL_WANT_READ || took == MBEDTLS_ERR_SSL_WANT_WRITE) {
        return TLS_WOULD_BLOCK;
    }
    session->failed = true;
    tls_fail(took, "could not write");
    return TLS_FAILED;
}

/* Sends `close_notify`, which is TLS's half-close: it tells the peer this side
 * is done sending rather than that the connection is gone. The socket is left
 * open, because the socket is not this file's to close. */
NUPP_EXPORT uint8_t nuppTlsCloseNotify(NuppTls *session) {
    int state;
    if (session == NULL || session->closed || !session->handshaken) {
        return 0;
    }
    state = mbedtls_ssl_close_notify(&session->ssl);
    if (state == MBEDTLS_ERR_SSL_WANT_READ || state == MBEDTLS_ERR_SSL_WANT_WRITE) {
        return 0;
    }
    return state == 0 ? 1 : 0;
}

/* Releases the session and nothing else. The connection underneath outlives it
 * and is closed by whoever owns it. */
NUPP_EXPORT void nuppTlsDestroy(NuppTls *session) {
    if (session == NULL) {
        return;
    }
    session->closed = true;
    tls_free(session);
}
