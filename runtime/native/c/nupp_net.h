/* What the TLS provider needs from the socket provider.
 *
 * Only these three, and deliberately: TLS moves bytes over a connection and has
 * no business knowing how one is opened, accepted or closed. Keeping the shared
 * surface to the byte-moving half is what stops the two files growing into one.
 */

#ifndef NUPP_NET_H
#define NUPP_NET_H

#include "nupp_native.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct NuppNetStream NuppNetStream;
typedef struct NuppNetDatagram NuppNetDatagram;

NUPP_EXPORT intptr_t nuppNetTryRead(NuppNetStream *stream, uint8_t *into, size_t wanted);
NUPP_EXPORT intptr_t nuppNetTryWrite(NuppNetStream *stream, const uint8_t *from, size_t length);
NUPP_EXPORT bool nuppNetStreamEnded(NuppNetStream *stream);
NUPP_EXPORT bool nuppNetStreamClosed(NuppNetStream *stream);
NUPP_EXPORT bool nuppNetStreamPeer(
    NuppNetStream *stream,
    char *host,
    size_t capacity,
    int32_t *port
);
NUPP_EXPORT size_t nuppNetPending(NuppNetStream *stream);

/* Stops libuv's byte transport and duplicates the connected TCP socket for a
 * kernel TLS record layer. The stream stays the owner of the connection; the
 * duplicate only lets the TLS layer poll and use the same open file
 * description without racing libuv's ordinary reads and writes. */
NUPP_EXPORT intptr_t nuppNetStreamTlsSocket(NuppNetStream *stream);

/* Marks the stream as owned by the kernel record layer, called only once the
 * handoff has fully engaged. Until then the stream keeps its ordinary byte
 * transport, so a failed handoff leaves a connection its owner can still use. */
NUPP_EXPORT void nuppNetStreamTlsEngaged(NuppNetStream *stream);
NUPP_EXPORT void *nuppNetStreamLoop(NuppNetStream *stream);

/* A layering module holds the connection struct alive while it may still ask
 * about it. The connection stops working when its owner closes it; this only
 * keeps the memory readable. */
NUPP_EXPORT void nuppNetStreamRetain(NuppNetStream *stream);
NUPP_EXPORT void nuppNetStreamRelease(NuppNetStream *stream);

NUPP_EXPORT intptr_t nuppNetDatagramReceivePeer(
    NuppNetDatagram *socket,
    const char *wantedHost,
    int32_t wantedPort,
    bool anyPeer,
    uint8_t *into,
    size_t capacity,
    int32_t *status,
    uint8_t *truncated,
    char *hostOut,
    size_t hostCapacity,
    int32_t *portOut
);
NUPP_EXPORT intptr_t nuppNetDatagramTrySend(
    NuppNetDatagram *socket,
    const char *host,
    int32_t port,
    const uint8_t *bytes,
    size_t length
);
NUPP_EXPORT bool nuppNetDatagramClosed(NuppNetDatagram *socket);
NUPP_EXPORT void nuppNetDatagramRetain(NuppNetDatagram *socket);
NUPP_EXPORT void nuppNetDatagramRelease(NuppNetDatagram *socket);

/* A session that has bound a datagram peer claims that address, so a session
 * still learning its own peer on the same socket leaves the bound peer's
 * records where they are. Released when the binding is undone or the session
 * goes. */
NUPP_EXPORT bool nuppNetDatagramClaimPeer(NuppNetDatagram *socket, const char *host, int32_t port);
NUPP_EXPORT void nuppNetDatagramReleasePeer(NuppNetDatagram *socket, const char *host, int32_t port);

#endif
