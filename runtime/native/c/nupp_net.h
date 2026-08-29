/* What the TLS provider needs from the socket provider.
 *
 * Only these three, and deliberately: TLS moves bytes over a connection and has
 * no business knowing how one is opened, accepted or closed. Keeping the shared
 * surface to the byte-moving half is what stops the two files growing into one.
 */

#ifndef NUPP_NET_H
#define NUPP_NET_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct NuppNetStream NuppNetStream;

intptr_t nuppNetTryRead(NuppNetStream *stream, uint8_t *into, size_t wanted);
intptr_t nuppNetTryWrite(NuppNetStream *stream, const uint8_t *from, size_t length);
bool nuppNetStreamEnded(NuppNetStream *stream);

/* A layering module holds the connection struct alive while it may still ask
 * about it. The connection stops working when its owner closes it; this only
 * keeps the memory readable. */
void nuppNetStreamRetain(NuppNetStream *stream);
void nuppNetStreamRelease(NuppNetStream *stream);

#endif
