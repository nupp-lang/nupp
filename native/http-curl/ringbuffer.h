/**
 * @file
 * @brief Byte rings for buffered HTTP upload and download.
 */

#ifndef NUPP_HTTP_CURL_RING_BUFFER_H
#define NUPP_HTTP_CURL_RING_BUFFER_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/** Lazy storage with a logical head and a count of available bytes. */
typedef struct {
  unsigned char *bytes;
  size_t start, used, room;
} Buffer;

/** Advances a valid index by at most one capacity, including wraparound. */
static inline size_t bufferadvance (size_t start, size_t count, size_t room) {
  size_t tail = room - start;

  return count < tail ? start + count : count - tail;
}

/** Returns the part of a transfer that fits before the next wrap. */
static inline size_t bufferfirst (size_t start, size_t count, size_t room) {
  size_t tail = room - start;

  return count < tail ? count : tail;
}

/** Appends bytes, allocating storage on the first nonempty append.
 * @pre count fits in the unused capacity and the input is disjoint from the
 * ring.
 * @return 1 on success or 0 when storage could not be allocated.
 */
static inline int bufferappend (Buffer *buffer, const void *bytes,
                                size_t count) {
  if (count == 0) {
    return 1;
  }

  if (!buffer->bytes) {
    buffer->bytes = malloc(buffer->room);

    if (!buffer->bytes) {
      return 0;
    }
  }

  size_t at = bufferadvance(buffer->start, buffer->used, buffer->room);
  size_t first = bufferfirst(at, count, buffer->room);
  memcpy(buffer->bytes + at, bytes, first);
  memcpy(buffer->bytes, (const unsigned char *)bytes + first, count - first);
  buffer->used += count;

  return 1;
}

/** Removes at most count bytes in FIFO order and returns the number copied.
 * @pre The output is disjoint from the ring and can hold the bytes copied.
 */
static inline size_t buffertake (Buffer *buffer, void *bytes, size_t count) {
  if (count > buffer->used) {
    count = buffer->used;
  }

  if (count == 0) {
    return 0;
  }

  size_t first = bufferfirst(buffer->start, count, buffer->room);
  memcpy(bytes, buffer->bytes + buffer->start, first);
  memcpy((unsigned char *)bytes + first, buffer->bytes, count - first);
  buffer->start = bufferadvance(buffer->start, count, buffer->room);
  buffer->used -= count;

  return count;
}

#endif
