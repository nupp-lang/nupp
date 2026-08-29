/* Whether a partially consumed connection grows its receive buffer with the
 * connection's total traffic.
 *
 * A C fixture rather than a suite case because the property is the buffer's
 * capacity, and capacity is not something the Lua surface exposes or should:
 * a program has no use for it. `nuppNetStreamCapacity` exists for this and is
 * reachable from here because this links the provider directly.
 *
 * The shape matters. Almost all of each block is taken and a few bytes are
 * left, so unread bytes stay tiny while traffic reaches a megabyte. Draining
 * less would push unread bytes towards the receive bound legitimately, and the
 * measurement would say nothing about compaction.
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct NuppNetLoop NuppNetLoop;
typedef struct NuppNetListener NuppNetListener;
typedef struct NuppNetStream NuppNetStream;
typedef struct NuppNetConnect NuppNetConnect;

extern const char *nuppNativeError(void);
extern NuppNetLoop *nuppNetLoopCreate(void);
extern int32_t nuppNetLoopRun(NuppNetLoop *, int32_t);
extern void nuppNetLoopDestroy(NuppNetLoop *);
extern NuppNetListener *nuppNetListen(NuppNetLoop *, const uint8_t *, size_t, uint16_t, int32_t, bool);
extern int32_t nuppNetListenerPort(NuppNetListener *);
extern NuppNetStream *nuppNetAccept(NuppNetListener *, int32_t *);
extern uint8_t nuppNetListenerClose(NuppNetListener *);
extern void nuppNetListenerDestroy(NuppNetListener *);
extern NuppNetConnect *nuppNetConnectBegin(NuppNetLoop *, const uint8_t *, size_t, uint16_t, int32_t);
extern int32_t nuppNetConnectPoll(NuppNetConnect *, NuppNetStream **);
extern void nuppNetConnectDestroy(NuppNetConnect *);
extern intptr_t nuppNetTryRead(NuppNetStream *, uint8_t *, size_t);
extern intptr_t nuppNetTryWrite(NuppNetStream *, const uint8_t *, size_t);
extern uint8_t nuppNetCloseStream(NuppNetStream *);
extern void nuppNetStreamDestroy(NuppNetStream *);
extern size_t nuppNetStreamCapacity(NuppNetStream *);

#define BLOCK 8192
#define ROUNDS 120
#define LEFT_BEHIND 8

/* Generous next to the 8 KiB blocks and far below the megabyte of traffic, so
 * this fails on growth-with-traffic and not on ordinary slack. */
#define CAPACITY_CEILING (256 * 1024)

int main(void) {
    NuppNetLoop *loop = nuppNetLoopCreate();
    const uint8_t host[] = "127.0.0.1";
    NuppNetListener *listener;
    NuppNetConnect *pending;
    NuppNetStream *client = NULL, *served = NULL;
    static uint8_t block[BLOCK];
    static uint8_t sink[BLOCK];
    size_t sent = 0;
    size_t capacity;
    int spins, round;
    int32_t port, status;

    if (loop == NULL) { printf("no loop\n"); return 1; }
    memset(block, 'z', sizeof block);

    listener = nuppNetListen(loop, host, 9, 0, 128, false);
    if (listener == NULL) { printf("listen: %s\n", nuppNativeError()); return 1; }
    port = nuppNetListenerPort(listener);

    pending = nuppNetConnectBegin(loop, host, 9, (uint16_t)port, 5000);
    for (spins = 0; spins < 300 && client == NULL; spins++) {
        nuppNetLoopRun(loop, 5);
        if (nuppNetConnectPoll(pending, &client) < 0) break;
    }
    nuppNetConnectDestroy(pending);
    for (spins = 0; spins < 300 && served == NULL; spins++) {
        nuppNetLoopRun(loop, 5);
        served = nuppNetAccept(listener, &status);
    }
    if (client == NULL || served == NULL) { printf("no pair\n"); return 1; }

    for (round = 0; round < ROUNDS; round++) {
        if (nuppNetTryWrite(client, block, sizeof block) < 0) {
            printf("write: %s\n", nuppNativeError());
            return 1;
        }
        sent += sizeof block;
        for (spins = 0; spins < 20; spins++) {
            nuppNetLoopRun(loop, 1);
        }
        nuppNetTryRead(served, sink, sizeof sink - LEFT_BEHIND);
    }

    capacity = nuppNetStreamCapacity(served);
    printf("sent %zu bytes, buffer grew to %zu\n", sent, capacity);

    nuppNetCloseStream(client); nuppNetStreamDestroy(client);
    nuppNetCloseStream(served); nuppNetStreamDestroy(served);
    nuppNetListenerClose(listener); nuppNetListenerDestroy(listener);
    for (spins = 0; spins < 50; spins++) nuppNetLoopRun(loop, 1);
    nuppNetLoopDestroy(loop);

    if (capacity > CAPACITY_CEILING) {
        printf("FAIL: the receive buffer grew with total traffic\n");
        return 1;
    }
    printf("ok\n");
    return 0;
}
