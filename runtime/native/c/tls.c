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
#include <mbedtls/ssl_cookie.h>
#include <mbedtls/ssl_ciphersuites.h>

#include <uv.h>

#include <stdlib.h>
#include <string.h>
#include <errno.h>

#if defined(__linux__)
#include <linux/tls.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
#endif

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
    mbedtls_ssl_cookie_ctx cookies;
    bool cookiesReady;
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
    uint8_t configuration
) {
    mbedtls_sha256_context digest;
    mbedtls_sha256_init(&digest);
    mbedtls_sha256_starts(&digest, 0);
    tls_digest_part(&digest, first, firstLength);
    tls_digest_part(&digest, second, secondLength);
    tls_digest_part(&digest, third, thirdLength);
    tls_digest_part(&digest, fourth, fourthLength);
    tls_digest_part(&digest, &configuration, sizeof configuration);
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

static int tls_cookie_write(
    void *context,
    unsigned char **start,
    unsigned char *end,
    const unsigned char *identity,
    size_t identityLength
) {
    TlsServerStoreEntry *store = context;
    int state;
    uv_mutex_lock(&store->guard);
    state = mbedtls_ssl_cookie_write(
        &store->cookies, start, end, identity, identityLength);
    uv_mutex_unlock(&store->guard);
    return state;
}

static int tls_cookie_check(
    void *context,
    const unsigned char *cookie,
    size_t cookieLength,
    const unsigned char *identity,
    size_t identityLength
) {
    TlsServerStoreEntry *store = context;
    int state;
    uv_mutex_lock(&store->guard);
    state = mbedtls_ssl_cookie_check(
        &store->cookies, cookie, cookieLength, identity, identityLength);
    uv_mutex_unlock(&store->guard);
    return state;
}

static bool tls_server_store_cookies(TlsServerStoreEntry *store) {
    int failed = 0;
    uv_mutex_lock(&store->guard);
    if (!store->cookiesReady) {
        failed = mbedtls_ssl_cookie_setup(
            &store->cookies, mbedtls_ctr_drbg_random, &store->drbg);
        store->cookiesReady = failed == 0;
    }
    uv_mutex_unlock(&store->guard);
    if (failed != 0) {
        tls_fail(failed, "the DTLS cookie secret could not be seeded");
    }
    return failed == 0;
}

static void tls_server_store_free(TlsServerStoreEntry *store) {
    mbedtls_ssl_cookie_free(&store->cookies);
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
    mbedtls_ssl_cookie_init(&store->cookies);
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
            /* An unused slot beats evicting anybody; among idle identities the
             * least recently used goes. */
            if (choice == NULL ||
                (choice->used &&
                 (!serverStores[at].used ||
                  serverStores[at].lastUsed < choice->lastUsed))) {
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
    NuppNetDatagram *datagramSocket;

    char peerHost[64];
    int32_t peerPort;
    bool peerReady;

    uint64_t timerStarted;
    uint32_t timerIntermediate;
    uint32_t timerFinal;

    unsigned char masterSecret[48];
    unsigned char clientRandom[32];
    unsigned char serverRandom[32];
    mbedtls_tls_prf_types tlsPrf;
    bool keyMaterialReady;

#if defined(__linux__)
    uv_poll_t kernelPoll;
    int kernelFd;
    bool kernelPollReady;
    bool kernelPollClosing;
#endif

    /* The protocol list, owned here because mbedTLS records the pointer rather
     * than the contents: its documentation requires the table to outlive the
     * configuration, so a list built on the caller's stack would be a dangling
     * read at the first handshake rather than at the call that set it. */
    char *alpnBytes;
    const char **alpn;

    bool server;
    bool datagram;
    bool kernelRequested;
    bool kernelOffloaded;
    bool handshakeComplete;
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
    const uint8_t *certificate,
    size_t certificateLength,
    const uint8_t *privateKey,
    size_t privateKeyLength,
    bool verify
) {
    char peer[64] = {0};
    int32_t port = 0;
    unsigned char portBytes[4];
    const uint8_t *host = hostname;
    size_t hostLength = hostnameLength;
    if (session->datagram && session->peerReady) {
        memcpy(peer, session->peerHost, sizeof peer);
        peer[sizeof peer - 1] = '\0';
        port = session->peerPort;
    } else if (session->stream != NULL) {
        nuppNetStreamPeer(session->stream, peer, sizeof peer, &port);
    }
    if (peer[0] != '\0' && hostLength == 0) {
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
        (uint8_t)((verify ? 1 : 0) |
            (session->datagram ? 2 : 0) |
            (session->kernelRequested ? 4 : 0)));
    /* A ticket carries the identity that earned it. Folding the client's own
     * certificate and key into the key is what keeps a session cached under
     * one identity from being resumed -- and acted under -- by another. */
    if (certificateLength != 0 || privateKeyLength != 0) {
        tls_digest_config(
            session->cacheKey,
            session->cacheKey, sizeof session->cacheKey,
            certificate, certificateLength,
            privateKey, privateKeyLength,
            NULL, 0,
            1);
    }
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

/* PEM through mbedTLS, which wants the buffer NUL-terminated with the NUL
 * counted. Both take a copy so the terminator lives in memory this call owns,
 * and zero it after: a private key must not linger in a freed allocation. */
static int tls_parse_certificates(
    mbedtls_x509_crt *into, const uint8_t *bytes, size_t length
) {
    unsigned char *copy = malloc(length + 1);
    int failed;
    if (copy == NULL) {
        return MBEDTLS_ERR_X509_ALLOC_FAILED;
    }
    memcpy(copy, bytes, length);
    copy[length] = 0;
    failed = mbedtls_x509_crt_parse(into, copy, length + 1);
    mbedtls_platform_zeroize(copy, length + 1);
    free(copy);
    return failed;
}

static int tls_parse_key(NuppTls *session, const uint8_t *bytes, size_t length) {
    unsigned char *copy = malloc(length + 1);
    int failed;
    if (copy == NULL) {
        return MBEDTLS_ERR_PK_ALLOC_FAILED;
    }
    memcpy(copy, bytes, length);
    copy[length] = 0;
    failed = mbedtls_pk_parse_key(&session->key, copy, length + 1,
        NULL, 0, mbedtls_ctr_drbg_random, &session->drbg);
    mbedtls_platform_zeroize(copy, length + 1);
    free(copy);
    return failed;
}

/* mbedTLS wants a message for a code; it does not have one to hand without
 * being asked. */
static void tls_fail(int code, const char *what) {
    char text[128];
    mbedtls_strerror(code, text, sizeof text);
    nupp_fail_format("tls: %s: %s", what, text);
}

/* --- the transport ------------------------------------------------------ */

/* The bound peer, registered with the socket underneath. One datagram socket
 * may carry several sessions, and a session still learning its own peer takes
 * the oldest datagram from anybody: the claim is what keeps it from taking a
 * record that another session was going to decrypt. It lasts exactly as long
 * as the binding -- released when a cookie challenge unlearns the peer and
 * when the session goes. */
static void tls_claim_peer(NuppTls *session) {
    if (session->datagram && session->peerReady) {
        nuppNetDatagramClaimPeer(
            session->datagramSocket, session->peerHost, session->peerPort);
    }
}

static void tls_unclaim_peer(NuppTls *session) {
    if (session->datagram && session->peerReady) {
        nuppNetDatagramReleasePeer(
            session->datagramSocket, session->peerHost, session->peerPort);
    }
}

static int tls_set_peer_identity(NuppTls *session) {
    unsigned char identity[70];
    size_t hostLength;
    if (!session->peerReady) {
        return MBEDTLS_ERR_SSL_BAD_INPUT_DATA;
    }
    hostLength = strlen(session->peerHost);
    if (hostLength + 5 > sizeof identity) {
        return MBEDTLS_ERR_SSL_BAD_INPUT_DATA;
    }
    memcpy(identity, session->peerHost, hostLength);
    identity[hostLength] = '\0';
    identity[hostLength + 1] = (unsigned char)((uint32_t)session->peerPort >> 24);
    identity[hostLength + 2] = (unsigned char)((uint32_t)session->peerPort >> 16);
    identity[hostLength + 3] = (unsigned char)((uint32_t)session->peerPort >> 8);
    identity[hostLength + 4] = (unsigned char)session->peerPort;
    return mbedtls_ssl_set_client_transport_id(
        &session->ssl, identity, hostLength + 5);
}

static void tls_set_timer(
    void *context,
    uint32_t intermediate,
    uint32_t final
) {
    NuppTls *session = context;
    session->timerIntermediate = intermediate;
    session->timerFinal = final;
    session->timerStarted = final == 0 ? 0 : uv_hrtime() / 1000000u;
}

static int tls_get_timer(void *context) {
    NuppTls *session = context;
    uint64_t elapsed;
    if (session->timerStarted == 0 || session->timerFinal == 0) {
        return 0;
    }
    elapsed = uv_hrtime() / 1000000u - session->timerStarted;
    if (elapsed >= session->timerFinal) {
        return 2;
    }
    if (session->timerIntermediate > 0 &&
        elapsed >= session->timerIntermediate) {
        return 1;
    }
    return 0;
}

static void tls_export_keys(
    void *context,
    mbedtls_ssl_key_export_type type,
    const unsigned char *secret,
    size_t secretLength,
    const unsigned char clientRandom[32],
    const unsigned char serverRandom[32],
    mbedtls_tls_prf_types tlsPrf
) {
    NuppTls *session = context;
    if (type != MBEDTLS_SSL_KEY_EXPORT_TLS12_MASTER_SECRET ||
        secretLength != sizeof session->masterSecret) {
        return;
    }
    memcpy(session->masterSecret, secret, sizeof session->masterSecret);
    memcpy(session->clientRandom, clientRandom, sizeof session->clientRandom);
    memcpy(session->serverRandom, serverRandom, sizeof session->serverRandom);
    session->tlsPrf = tlsPrf;
    session->keyMaterialReady = true;
}

/* The two halves of the reason this is C. Each hands bytes straight to the
 * socket beside it and reports "not yet" in mbedTLS's spelling. */
static int tls_send(void *context, const unsigned char *bytes, size_t length) {
    NuppTls *session = context;
    if (session->datagram) {
        intptr_t sent;
        if (!session->peerReady) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        sent = nuppNetDatagramTrySend(
            session->datagramSocket,
            session->peerHost,
            session->peerPort,
            bytes,
            length);
        if (sent < 0) {
            return NUPP_TLS_SEND_FAILED;
        }
        if (sent == 0 && length > 0) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        return (int)sent;
    }
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
    if (session->datagram) {
        int32_t status = -1;
        uint8_t truncated = 0;
        char host[64];
        int32_t port = 0;
        intptr_t got = nuppNetDatagramReceivePeer(
            session->datagramSocket,
            session->peerHost,
            session->peerPort,
            !session->peerReady,
            into,
            length,
            &status,
            &truncated,
            host,
            sizeof host,
            &port);
        if (truncated) {
            /* Discarded, not fatal: a UDP source is forgeable, and DTLS's rule
             * for a datagram that cannot be a record is to drop it silently --
             * one spoofed oversized packet must not end the session. */
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        if (status < 0 || got < 0) {
            return NUPP_TLS_RECV_FAILED;
        }
        if (status == 0) {
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        if (!session->peerReady) {
            memcpy(session->peerHost, host, sizeof session->peerHost);
            session->peerHost[sizeof session->peerHost - 1] = '\0';
            session->peerPort = port;
            session->peerReady = true;
            if (session->server && tls_set_peer_identity(session) != 0) {
                return NUPP_TLS_RECV_FAILED;
            }
            tls_claim_peer(session);
        }
        return (int)got;
    }
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
    /* A list without its trailing separator still names a final entry, which
     * the terminator added above closes. */
    if (session->alpnBytes[length - 1] != '\0') {
        count++;
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

#if defined(__linux__)
static void tls_kernel_ready(uv_poll_t *handle, int status, int events) {
    (void)status;
    (void)events;
    uv_poll_stop(handle);
}

static void tls_kernel_wait(NuppTls *session, int events) {
    if (session->kernelPollReady && !session->kernelPollClosing) {
        uv_poll_start(&session->kernelPoll, events, tls_kernel_ready);
    }
}

static bool tls_kernel_crypto(
    NuppTls *session,
    int option,
    const unsigned char *key,
    const unsigned char *salt,
    const unsigned char sequence[8],
    size_t keyLength
) {
    if (keyLength == TLS_CIPHER_AES_GCM_128_KEY_SIZE) {
        struct tls12_crypto_info_aes_gcm_128 crypto;
        memset(&crypto, 0, sizeof crypto);
        crypto.info.version = TLS_1_2_VERSION;
        crypto.info.cipher_type = TLS_CIPHER_AES_GCM_128;
        memcpy(crypto.iv, sequence, sizeof crypto.iv);
        memcpy(crypto.key, key, sizeof crypto.key);
        memcpy(crypto.salt, salt, sizeof crypto.salt);
        memcpy(crypto.rec_seq, sequence, sizeof crypto.rec_seq);
        return setsockopt(
            session->kernelFd, SOL_TLS, option, &crypto, sizeof crypto) == 0;
    }
    if (keyLength == TLS_CIPHER_AES_GCM_256_KEY_SIZE) {
        struct tls12_crypto_info_aes_gcm_256 crypto;
        memset(&crypto, 0, sizeof crypto);
        crypto.info.version = TLS_1_2_VERSION;
        crypto.info.cipher_type = TLS_CIPHER_AES_GCM_256;
        memcpy(crypto.iv, sequence, sizeof crypto.iv);
        memcpy(crypto.key, key, sizeof crypto.key);
        memcpy(crypto.salt, salt, sizeof crypto.salt);
        memcpy(crypto.rec_seq, sequence, sizeof crypto.rec_seq);
        return setsockopt(
            session->kernelFd, SOL_TLS, option, &crypto, sizeof crypto) == 0;
    }
    return false;
}

/* Abandons a handoff that has not touched the socket's record layer. The
 * session continues on user-space records: nothing before this point has
 * changed the mbedTLS session, and the descriptor closed here is a duplicate
 * whose only purpose was the handoff that is not happening. Clearing the
 * request is what keeps the next handshake poll from trying again. */
static int tls_kernel_fallback(NuppTls *session) {
    if (session->kernelFd >= 0) {
        close(session->kernelFd);
        session->kernelFd = -1;
    }
    session->kernelRequested = false;
    return 0;
}

/* Tries to hand the finished handshake's record layer to the kernel. Answers 1
 * when the kernel took both directions, 0 when it could not and the session
 * falls back to user-space records, and -1 for a failure user space cannot
 * recover from.
 *
 * The line between the last two is whether the kernel was handed any of the
 * record layer. Up to and including a failed TCP_ULP attach it was not: an
 * unusable cipher, an underivable key block, a refused or buffered-up
 * descriptor, and a setsockopt that answered EEXIST, ENOENT or anything else
 * all leave the socket carrying plain TCP, and nothing on those paths has
 * touched the mbedTLS session, so its record layer simply continues. Once a
 * key direction has been installed with TLS_RX or TLS_TX the shared open file
 * description is partly kernel-managed and records may already be consumed
 * there, so a failure from then on fails the handshake. A socket with the ULP
 * attached but no keys yet is claimed to pass bytes through unchanged, but no
 * pinned kernel source is vendored here to hold that claim against, so the
 * boundary sits at the attach rather than after it. */
static int tls_kernel_enable(NuppTls *session) {
    const mbedtls_ssl_ciphersuite_t *suite;
    const char *name;
    unsigned char seed[64];
    unsigned char keyBlock[72];
    const unsigned char *clientKey;
    const unsigned char *serverKey;
    const unsigned char *clientSalt;
    const unsigned char *serverSalt;
    const unsigned char *writeKey;
    const unsigned char *readKey;
    const unsigned char *writeSalt;
    const unsigned char *readSalt;
    size_t keyLength;
    intptr_t descriptor;
    int failed;

    if (!session->keyMaterialReady ||
        mbedtls_ssl_get_version_number(&session->ssl) !=
            MBEDTLS_SSL_VERSION_TLS1_2) {
        return tls_kernel_fallback(session);
    }
    suite = mbedtls_ssl_ciphersuite_from_id(
        mbedtls_ssl_get_ciphersuite_id_from_ssl(&session->ssl));
    name = suite == NULL ? NULL : mbedtls_ssl_ciphersuite_get_name(suite);
    keyLength = suite == NULL ? 0 :
        mbedtls_ssl_ciphersuite_get_cipher_key_bitlen(suite) / 8;
    if (name == NULL || strstr(name, "AES-") == NULL ||
        strstr(name, "-GCM-") == NULL ||
        (keyLength != TLS_CIPHER_AES_GCM_128_KEY_SIZE &&
         keyLength != TLS_CIPHER_AES_GCM_256_KEY_SIZE)) {
        return tls_kernel_fallback(session);
    }

    memcpy(seed, session->serverRandom, sizeof session->serverRandom);
    memcpy(seed + sizeof session->serverRandom,
        session->clientRandom, sizeof session->clientRandom);
    failed = mbedtls_ssl_tls_prf(
        session->tlsPrf,
        session->masterSecret,
        sizeof session->masterSecret,
        "key expansion",
        seed,
        sizeof seed,
        keyBlock,
        keyLength * 2 + 8);
    if (failed != 0) {
        mbedtls_platform_zeroize(keyBlock, sizeof keyBlock);
        return tls_kernel_fallback(session);
    }
    clientKey = keyBlock;
    serverKey = keyBlock + keyLength;
    clientSalt = keyBlock + keyLength * 2;
    serverSalt = clientSalt + 4;
    writeKey = session->server ? serverKey : clientKey;
    readKey = session->server ? clientKey : serverKey;
    writeSalt = session->server ? serverSalt : clientSalt;
    readSalt = session->server ? clientSalt : serverSalt;

    /* A refusal here -- the stream closed, ciphertext already buffered in
     * this process by a peer that wrote early, no descriptor to duplicate --
     * has handed the kernel nothing, so it falls back like the checks above. */
    descriptor = nuppNetStreamTlsSocket(session->stream);
    if (descriptor < 0) {
        mbedtls_platform_zeroize(keyBlock, sizeof keyBlock);
        return tls_kernel_fallback(session);
    }
    session->kernelFd = (int)descriptor;
    /* A failed attach installs nothing: ENOENT is the tls module absent,
     * EEXIST a ULP already there, and every failure answer means this call
     * changed nothing, so user-space records continue. */
    if (setsockopt(
            session->kernelFd, SOL_TCP, TCP_ULP, "tls", sizeof "tls") != 0) {
        mbedtls_platform_zeroize(keyBlock, sizeof keyBlock);
        return tls_kernel_fallback(session);
    }
    if (!tls_kernel_crypto(
            session,
            TLS_RX,
            readKey,
            readSalt,
            session->ssl.MBEDTLS_PRIVATE(in_ctr),
            keyLength)) {
        nupp_fail_format("tls: Linux kTLS could not take receive records: %s",
            strerror(errno));
        mbedtls_platform_zeroize(keyBlock, sizeof keyBlock);
        return -1;
    }
    if (!tls_kernel_crypto(
            session,
            TLS_TX,
            writeKey,
            writeSalt,
            session->ssl.MBEDTLS_PRIVATE(cur_out_ctr),
            keyLength)) {
        nupp_fail_format("tls: Linux kTLS could not take transmit records: %s",
            strerror(errno));
        mbedtls_platform_zeroize(keyBlock, sizeof keyBlock);
        return -1;
    }
    mbedtls_platform_zeroize(keyBlock, sizeof keyBlock);
    if (uv_poll_init_socket(
            (uv_loop_t *)nuppNetStreamLoop(session->stream),
            &session->kernelPoll,
            session->kernelFd) != 0) {
        nupp_fail("tls: the kernel TLS socket could not join the reactor");
        return -1;
    }
    session->kernelPoll.data = session;
    session->kernelPollReady = true;
    /* Marked only now, with the ULP attached, both directions' keys installed
     * and the reactor watching the descriptor. Marking earlier would leave the
     * stream refusing its ordinary byte transport after a handoff that fell
     * back or failed partway, which its owner could otherwise go on using or
     * close cleanly. */
    nuppNetStreamTlsEngaged(session->stream);
    session->kernelOffloaded = true;
    return 1;
}

static int tls_kernel_send(
    NuppTls *session,
    const unsigned char *bytes,
    size_t length
) {
    ssize_t took = send(
        session->kernelFd, bytes, length, MSG_DONTWAIT | MSG_NOSIGNAL);
    if (took >= 0) {
        return (int)took;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
        tls_kernel_wait(session, UV_WRITABLE);
        return MBEDTLS_ERR_SSL_WANT_WRITE;
    }
    nupp_fail_format("tls: kernel record write failed: %s", strerror(errno));
    return NUPP_TLS_SEND_FAILED;
}

static int tls_kernel_recv(
    NuppTls *session,
    unsigned char *into,
    size_t length
) {
    struct msghdr message;
    struct iovec input;
    unsigned char controls[CMSG_SPACE(sizeof(unsigned char))];
    struct cmsghdr *control;
    ssize_t got;
    unsigned char recordType = 23;
    memset(&message, 0, sizeof message);
    memset(controls, 0, sizeof controls);
    input.iov_base = into;
    input.iov_len = length;
    message.msg_iov = &input;
    message.msg_iovlen = 1;
    message.msg_control = controls;
    message.msg_controllen = sizeof controls;
    got = recvmsg(session->kernelFd, &message, MSG_DONTWAIT);
    if (got < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            tls_kernel_wait(session, UV_READABLE);
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        nupp_fail_format("tls: kernel record read failed: %s", strerror(errno));
        return NUPP_TLS_RECV_FAILED;
    }
    control = CMSG_FIRSTHDR(&message);
    if (control != NULL && control->cmsg_level == SOL_TLS &&
        control->cmsg_type == TLS_GET_RECORD_TYPE &&
        control->cmsg_len >= CMSG_LEN(sizeof recordType)) {
        memcpy(&recordType, CMSG_DATA(control), sizeof recordType);
    }
    if (recordType == 23) {
        return (int)got;
    }
    if (recordType == 21 && got >= 2 && into[1] == 0) {
        return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
    }
    nupp_fail_format("tls: unexpected kernel TLS record type %u",
        (unsigned)recordType);
    return NUPP_TLS_RECV_FAILED;
}

static bool tls_kernel_close_notify(NuppTls *session) {
    unsigned char alert[2] = {1, 0};
    unsigned char recordType = 21;
    unsigned char controls[CMSG_SPACE(sizeof recordType)];
    struct msghdr message;
    struct cmsghdr *control;
    struct iovec output;
    int attempt;
    memset(&message, 0, sizeof message);
    memset(controls, 0, sizeof controls);
    output.iov_base = alert;
    output.iov_len = sizeof alert;
    message.msg_iov = &output;
    message.msg_iovlen = 1;
    message.msg_control = controls;
    message.msg_controllen = sizeof controls;
    control = CMSG_FIRSTHDR(&message);
    control->cmsg_level = SOL_TLS;
    control->cmsg_type = TLS_SET_RECORD_TYPE;
    control->cmsg_len = CMSG_LEN(sizeof recordType);
    memcpy(CMSG_DATA(control), &recordType, sizeof recordType);
    message.msg_controllen = control->cmsg_len;
    /* The socket buffer may be full of records already accepted, and a
     * close_notify quietly dropped for that turns an ended session into a
     * truncated one at the peer. The kernel drains that buffer on its own, so
     * waiting for writability briefly is usually enough -- and only briefly,
     * because a close must not hang on a peer that has stopped reading. */
    for (attempt = 0; attempt < 25; attempt++) {
        struct pollfd waiting;
        if (sendmsg(session->kernelFd, &message,
                MSG_DONTWAIT | MSG_NOSIGNAL) == (ssize_t)sizeof alert) {
            return true;
        }
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            return false;
        }
        waiting.fd = session->kernelFd;
        waiting.events = POLLOUT;
        waiting.revents = 0;
        poll(&waiting, 1, 20);
    }
    return false;
}
#endif

static void tls_reap(NuppTls *session) {
#if defined(__linux__)
    if (session->kernelFd >= 0) {
        close(session->kernelFd);
        session->kernelFd = -1;
    }
#endif
    if (session->stream != NULL) {
        nuppNetStreamRelease(session->stream);
    }
    if (session->datagramSocket != NULL) {
        tls_unclaim_peer(session);
        nuppNetDatagramRelease(session->datagramSocket);
    }
    mbedtls_platform_zeroize(
        session->masterSecret, sizeof session->masterSecret);
    free(session->alpn);
    free(session->alpnBytes);
    free(session);
}

#if defined(__linux__)
static void tls_kernel_poll_closed(uv_handle_t *handle) {
    NuppTls *session = handle->data;
    session->kernelPollReady = false;
    tls_reap(session);
}
#endif

static void tls_free(NuppTls *session) {
    mbedtls_ssl_free(&session->ssl);
    mbedtls_ssl_config_free(&session->config);
    mbedtls_ctr_drbg_free(&session->drbg);
    mbedtls_entropy_free(&session->entropy);
    mbedtls_x509_crt_free(&session->chain);
    mbedtls_x509_crt_free(&session->authority);
    mbedtls_pk_free(&session->key);
    tls_server_store_release(session->serverStore);
#if defined(__linux__)
    if (session->kernelPollReady && !session->kernelPollClosing) {
        session->kernelPollClosing = true;
        uv_poll_stop(&session->kernelPoll);
        uv_close((uv_handle_t *)&session->kernelPoll, tls_kernel_poll_closed);
        return;
    }
#endif
    tls_reap(session);
}

/* Wraps a connection.
 *
 * The socket is not owned here and is not closed here: `nupp.io.net` handed it
 * over to be encrypted, not given away, and one owner is the whole of what the
 * affine layer above is enforcing.
 */
NUPP_EXPORT NuppTls *nuppTlsWrap(
    void *transport,
    bool datagram,
    bool server,
    const uint8_t *peerHost,
    size_t peerHostLength,
    int32_t peerPort,
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
    bool verify,
    bool kernelOffload
) {
    NuppTls *session;
    int failed;

    if (transport == NULL) {
        nupp_fail("tls: wrapping needs a socket");
        return NULL;
    }
    if (datagram && kernelOffload) {
        nupp_fail("tls: kernel TLS offload applies only to TCP streams");
        return NULL;
    }
#if !defined(__linux__)
    /* No kernel here can take the record layer, so the request can never
     * engage. The contract is that an offload the platform cannot make falls
     * back to user-space records with `nuppTlsKernelOffloaded` answering
     * false, and on these systems that answer is known before the handshake
     * -- so the request is dropped now rather than pinning negotiation to
     * TLS 1.2 for a handoff that cannot happen. */
    kernelOffload = false;
#endif
    session = calloc(1, sizeof *session);
    if (session == NULL) {
        nupp_fail("tls: out of memory");
        return NULL;
    }
    session->datagram = datagram;
    session->kernelRequested = kernelOffload;
#if defined(__linux__)
    session->kernelFd = -1;
#endif
    if (datagram) {
        session->datagramSocket = transport;
        nuppNetDatagramRetain(session->datagramSocket);
    } else {
        session->stream = transport;
        /* Held, so that the socket struct outlives the owner releasing it. The
         * connection stops working the moment its owner closes it -- that is
         * the point -- but asking whether it did must not read freed memory. */
        nuppNetStreamRetain(session->stream);
    }
    session->server = server;
    mbedtls_ssl_init(&session->ssl);
    mbedtls_ssl_config_init(&session->config);
    mbedtls_entropy_init(&session->entropy);
    mbedtls_ctr_drbg_init(&session->drbg);
    mbedtls_x509_crt_init(&session->chain);
    mbedtls_x509_crt_init(&session->authority);
    mbedtls_pk_init(&session->key);

    if (peerHost != NULL && peerHostLength > 0) {
        NuppText peer;
        if (peerPort < 0 || peerPort > 65535 ||
            !nupp_text(&peer, peerHost, peerHostLength, "DTLS peer")) {
            tls_free(session);
            return NULL;
        }
        if (peer.length >= sizeof session->peerHost) {
            nupp_text_free(&peer);
            nupp_fail("tls: the DTLS peer address is too long");
            tls_free(session);
            return NULL;
        }
        memcpy(session->peerHost, peer.value, peer.length + 1);
        session->peerPort = peerPort;
        session->peerReady = true;
        tls_claim_peer(session);
        nupp_text_free(&peer);
    }
    failed = mbedtls_ctr_drbg_seed(&session->drbg, mbedtls_entropy_func,
        &session->entropy, (const unsigned char *)"nupp.io.tls", 11);
    if (failed != 0) {
        tls_fail(failed, "the random generator could not be seeded");
        tls_free(session);
        return NULL;
    }

    failed = mbedtls_ssl_config_defaults(&session->config,
        server ? MBEDTLS_SSL_IS_SERVER : MBEDTLS_SSL_IS_CLIENT,
        datagram ? MBEDTLS_SSL_TRANSPORT_DATAGRAM :
            MBEDTLS_SSL_TRANSPORT_STREAM,
        MBEDTLS_SSL_PRESET_DEFAULT);
    if (failed != 0) {
        tls_fail(failed, "the session could not be configured");
        tls_free(session);
        return NULL;
    }
    mbedtls_ssl_conf_rng(&session->config, mbedtls_ctr_drbg_random, &session->drbg);
    if (kernelOffload) {
        mbedtls_ssl_conf_min_tls_version(
            &session->config, MBEDTLS_SSL_VERSION_TLS1_2);
        mbedtls_ssl_conf_max_tls_version(
            &session->config, MBEDTLS_SSL_VERSION_TLS1_2);
    }

    /* mbedTLS wants its PEM NUL-terminated and counts the NUL. The terminator
     * is added on a copy here: the caller handed a pointer and a length, and a
     * byte past that span is not the call's to read. */
    if (certificate != NULL && certificateLength > 0) {
        failed = tls_parse_certificates(&session->chain, certificate, certificateLength);
        if (failed != 0) {
            tls_fail(failed, "the certificate could not be read");
            tls_free(session);
            return NULL;
        }
    }
    if (privateKey != NULL && privateKeyLength > 0) {
        failed = tls_parse_key(session, privateKey, privateKeyLength);
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
        failed = tls_parse_certificates(&session->authority, authority, authorityLength);
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
            (uint8_t)((verify ? 1 : 0) |
                (datagram ? 2 : 0) |
                (kernelOffload ? 4 : 0)));
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
        if (datagram) {
            if (!tls_server_store_cookies(session->serverStore)) {
                tls_free(session);
                return NULL;
            }
            mbedtls_ssl_conf_dtls_cookies(
                &session->config,
                tls_cookie_write,
                tls_cookie_check,
                session->serverStore);
        }
    } else {
        tls_client_cache_key(
            session,
            hostname, hostnameLength,
            authority, authorityLength,
            protocols, protocolsLength,
            certificate, certificateLength,
            privateKey, privateKeyLength,
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
    if (datagram) {
        if (!server && !session->peerReady) {
            nupp_fail("tls: a DTLS client needs a peer address");
            tls_free(session);
            return NULL;
        }
        mbedtls_ssl_set_timer_cb(
            &session->ssl, session, tls_set_timer, tls_get_timer);
    }
    if (kernelOffload) {
        mbedtls_ssl_set_export_keys_cb(
            &session->ssl, tls_export_keys, session);
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
        if (session->failure != 0) {
            tls_fail(session->failure, "the handshake failed");
        } else {
            nupp_fail("tls: the handshake previously failed");
        }
        return -1;
    }
    if (session->handshakeComplete) {
#if defined(__linux__)
        if (session->kernelRequested && !session->kernelOffloaded) {
            if (nuppNetPending(session->stream) != 0) {
                return 0;
            }
            /* A handoff the platform cannot begin clears the request and the
             * session continues on user-space records; only one that failed
             * after handing the kernel a key direction fails the handshake.
             * `nuppTlsKernelOffloaded` is what says which way this went. */
            if (tls_kernel_enable(session) < 0) {
                session->failed = true;
                return -1;
            }
        }
#endif
        session->handshaken = true;
        return 1;
    }
    state = mbedtls_ssl_handshake(&session->ssl);
#if defined(MBEDTLS_SSL_DTLS_HELLO_VERIFY)
    if (state == MBEDTLS_ERR_SSL_HELLO_VERIFY_REQUIRED &&
        session->datagram && session->server) {
        state = mbedtls_ssl_session_reset(&session->ssl);
        if (state == 0) {
            /* The address that sent this hello has proved nothing yet: the
             * cookie it was just challenged with is the proof, and it may
             * never answer. Staying bound to it would let one spoofed packet
             * wedge the session forever, with every honest peer's records
             * filtered out against an address that has gone quiet. Unlearned
             * instead, so the next hello -- this peer's answer or somebody
             * else's -- binds afresh, and `tls_recv` re-registers the
             * transport identity when it does. */
            tls_unclaim_peer(session);
            session->peerReady = false;
            mbedtls_ssl_set_timer_cb(
                &session->ssl, session, tls_set_timer, tls_get_timer);
            mbedtls_ssl_set_bio(
                &session->ssl, session, tls_send, tls_recv, NULL);
            return 0;
        }
    }
#endif
#if defined(MBEDTLS_SSL_PROTO_TLS1_3)
    if (state == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) {
        tls_client_cache_save(session);
        return 0;
    }
#endif
    if (state == 0) {
        session->handshakeComplete = true;
        session->resumed = session->resumptionOffered &&
            !session->sawPeerCertificate;
        /* A TLS 1.3 ticket is a post-handshake message. Before that arrives,
         * get_session can serialize negotiated state but nothing resumable. */
        if (strcmp(mbedtls_ssl_get_version(&session->ssl), "TLSv1.3") != 0) {
            tls_client_cache_save(session);
        }
        return nuppTlsHandshake(session);
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
    if (session->failed) {
        /* mbedTLS documents a context that returned a fatal error as unusable;
         * re-entering it answers nonsense at best. */
        nupp_fail("tls: the session has failed");
        return TLS_FAILED;
    }
    do {
#if defined(__linux__)
        if (session->kernelOffloaded) {
            got = tls_kernel_recv(session, into, wanted);
        } else
#endif
        {
        got = mbedtls_ssl_read(&session->ssl, into, wanted);
        }
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
    if (session->failed) {
        nupp_fail("tls: the session has failed");
        return TLS_FAILED;
    }
    if (length == 0) {
        return 0;
    }
#if defined(__linux__)
    if (session->kernelOffloaded) {
        took = tls_kernel_send(session, bytes, length);
    } else
#endif
    {
        took = mbedtls_ssl_write(&session->ssl, bytes, length);
    }
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
#if defined(__linux__)
    if (session->kernelOffloaded) {
        return tls_kernel_close_notify(session) ? 1 : 0;
    }
#endif
    state = mbedtls_ssl_close_notify(&session->ssl);
    if (state == MBEDTLS_ERR_SSL_WANT_READ || state == MBEDTLS_ERR_SSL_WANT_WRITE) {
        return 0;
    }
    return state == 0 ? 1 : 0;
}

NUPP_EXPORT bool nuppTlsConnected(NuppTls *session) {
    if (session == NULL || session->closed) {
        return false;
    }
    if (session->datagram) {
        return !nuppNetDatagramClosed(session->datagramSocket);
    }
    return !nuppNetStreamClosed(session->stream);
}

NUPP_EXPORT bool nuppTlsKernelOffloaded(NuppTls *session) {
    return session != NULL && session->handshaken && session->kernelOffloaded;
}

NUPP_EXPORT bool nuppTlsKernelSupported(void) {
#if defined(__linux__)
    return true;
#else
    return false;
#endif
}

NUPP_EXPORT uint8_t nuppTlsPeer(
    NuppTls *session,
    char *host,
    size_t capacity,
    int32_t *port
) {
    size_t length;
    if (session == NULL || !session->datagram || !session->peerReady ||
        host == NULL || capacity == 0) {
        return 0;
    }
    length = strlen(session->peerHost);
    if (length >= capacity) {
        length = capacity - 1;
    }
    memcpy(host, session->peerHost, length);
    host[length] = '\0';
    if (port != NULL) {
        *port = session->peerPort;
    }
    return 1;
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
