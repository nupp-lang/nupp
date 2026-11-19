/**
 * @file
 * @brief Bounded copied I/O for libuv stream handles on their owner thread.
 */

#ifndef NUPP_CORE_STREAMIO_H
#define NUPP_CORE_STREAMIO_H

#include <uv.h>

/** Initialize to zero and place its address in the libuv handle's data slot. */
typedef struct NuppStreamIO {
  uv_write_t write;
  char inbound[16384];
  char outbound[16384];
  size_t readstart, readend;
  int reading, readstatus, pending, writestatus;
} NuppStreamIO;

/** Copies available bytes, returns zero at EOF or UV_EAGAIN while waiting. */
int nuppstreamread (uv_stream_t *stream, void *bytes, size_t size);

/** Prefetches one chunk when there are no unread bytes or terminal status. */
int nuppstreamstartread (uv_stream_t *stream);

/** Reports whether the next read would return bytes, EOF or an error. */
int nuppstreamreadable (const NuppStreamIO *io);

/** Copies one bounded chunk. Accepted bytes remain owned until completion. */
int nuppstreamwrite (uv_stream_t *stream, const void *bytes, size_t size);

/** Reports queued bytes or the error from the last asynchronous write. */
int nuppstreampending (const NuppStreamIO *io);

#endif
