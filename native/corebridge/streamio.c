/**
 * @file
 * @brief One bounded copied read and write slot per libuv stream.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "streamio.h"
#include <string.h>

static void readbuffer (uv_handle_t *handle, size_t suggested,
                        uv_buf_t *buffer) {
  (void)suggested;
  NuppStreamIO *io = handle->data;
  *buffer = uv_buf_init(io->inbound, sizeof(io->inbound));
}

static void received (uv_stream_t *stream, ssize_t count,
                      const uv_buf_t *buffer) {
  (void)buffer;
  NuppStreamIO *io = stream->data;

  if (count == 0) {
    return;
  }

  uv_read_stop(stream);
  io->reading = 0;

  if (count < 0) {
    io->readstatus = (int)count;
  }
  else {
    io->readstart = 0;
    io->readend = (size_t)count;
  }
}

int nuppstreamread (uv_stream_t *stream, void *bytes, size_t size) {
  NuppStreamIO *io = stream->data;

  if (!size) {
    return 0;
  }

  size_t available = io->readend - io->readstart;

  if (available) {
    size_t count = size < available ? size : available;
    memcpy(bytes, io->inbound + io->readstart, count);
    io->readstart += count;

    return (int)count;
  }

  if (io->readstatus) {
    return io->readstatus == UV_EOF ? 0 : io->readstatus;
  }

  int status = nuppstreamstartread(stream);

  return status < 0 ? status : UV_EAGAIN;
}

int nuppstreamstartread (uv_stream_t *stream) {
  NuppStreamIO *io = stream->data;

  if (io->reading || nuppstreamreadable(io)) {
    return 0;
  }

  int status = uv_read_start(stream, readbuffer, received);

  if (status == 0) {
    io->reading = 1;
  }

  return status;
}

int nuppstreamreadable (const NuppStreamIO *io) {
  return io->readstart != io->readend || io->readstatus != 0;
}

static void written (uv_write_t *request, int status) {
  NuppStreamIO *io = request->data;
  io->pending = 0;
  io->writestatus = status;
}

int nuppstreamwrite (uv_stream_t *stream, const void *bytes, size_t size) {
  NuppStreamIO *io = stream->data;

  if (io->writestatus < 0) {
    return io->writestatus;
  }

  if (!size) {
    return 0;
  }

  if (io->pending) {
    return UV_EAGAIN;
  }

  unsigned int count =
      size < sizeof(io->outbound) ? (unsigned int)size : sizeof(io->outbound);
  memcpy(io->outbound, bytes, count);
  uv_buf_t buffer = uv_buf_init(io->outbound, count);
  io->write.data = io;
  int status = uv_write(&io->write, stream, &buffer, 1, written);

  if (status < 0) {
    return status;
  }

  io->pending = (int)count;

  return (int)count;
}

int nuppstreampending (const NuppStreamIO *io) {
  return io->writestatus < 0 ? io->writestatus : io->pending;
}
