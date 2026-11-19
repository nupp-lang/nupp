/**
 * @file
 * @brief Moves bytes through libuv without retaining guest storage.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "tcp.h"
#include <stdlib.h>
#include <string.h>

/* The proof bounds the backing arrays while exercising the same operations. */
#ifndef NUPP_TCP_WINDOW_BYTES
#define NUPP_TCP_WINDOW_BYTES 16384
#endif

enum { WINDOW = NUPP_TCP_WINDOW_BYTES };

struct NuppTcp {
  uv_tcp_t stream;
  uv_connect_t connection;
  uv_write_t write;
  uv_shutdown_t shutdown;

  /** A submitted write and a stopped read each retain one bounded buffer. */
  char inbound[WINDOW];
  char outbound[WINDOW];
  size_t readstart, readend;
  int reading, readstatus, pending, writestatus;
  int connecting, connectstatus, listenerror;
  int shuttingdown, shutdownstatus;
  int closing, closed;
};

int nupptcpopen (uv_loop_t *loop, NuppTcp **out) {
  *out = NULL;
  NuppTcp *tcp = calloc(1, sizeof(*tcp));

  if (!tcp) {
    return UV_ENOMEM;
  }

  int status = uv_tcp_init(loop, &tcp->stream);

  if (status < 0) {
    free(tcp);

    return status;
  }

  tcp->stream.data = tcp;
  tcp->connectstatus = UV_ENOTCONN;
  tcp->shutdownstatus = UV_ENOTCONN;
  *out = tcp;

  return 0;
}

static void waiting (uv_stream_t *stream, int status) {
  NuppTcp *tcp = stream->data;
  tcp->listenerror = status;
}

int nupptcplisten (NuppTcp *tcp, const struct sockaddr *address, int backlog) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  int status = uv_tcp_bind(&tcp->stream, address, 0);

  return status < 0 ? status
                    : uv_listen((uv_stream_t *)&tcp->stream, backlog, waiting);
}

int nupptcplocal (NuppTcp *tcp, struct sockaddr *address, int *size) {
  return tcp->closing ? UV_EBADF
                      : uv_tcp_getsockname(&tcp->stream, address, size);
}

int nupptcpaccept (NuppTcp *listener, NuppTcp *stream) {
  if (listener->closing || stream->closing) {
    return UV_EBADF;
  }

  if (listener->listenerror < 0) {
    int status = listener->listenerror;
    listener->listenerror = 0;

    return status;
  }

  int status = uv_accept((uv_stream_t *)&listener->stream,
                         (uv_stream_t *)&stream->stream);

  if (status == 0) {
    stream->connectstatus = 0;
  }

  return status;
}

static void connected (uv_connect_t *request, int status) {
  NuppTcp *tcp = request->data;
  tcp->connectstatus = tcp->closing ? UV_ECANCELED : status;
}

int nupptcpconnect (NuppTcp *tcp, const struct sockaddr *address) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  if (tcp->connecting) {
    return UV_EALREADY;
  }

  tcp->connection.data = tcp;
  int status =
      uv_tcp_connect(&tcp->connection, &tcp->stream, address, connected);

  if (status == 0) {
    tcp->connecting = 1;
    tcp->connectstatus = UV_EAGAIN;
  }

  return status;
}

int nupptcpconnected (const NuppTcp *tcp) {
  return tcp->connectstatus;
}

static void readbuffer (uv_handle_t *handle, size_t suggested,
                        uv_buf_t *buffer) {
  (void)suggested;
  NuppTcp *tcp = handle->data;
  *buffer = uv_buf_init(tcp->inbound, sizeof(tcp->inbound));
}

static void received (uv_stream_t *stream, ssize_t count,
                      const uv_buf_t *buffer) {
  (void)buffer;
  NuppTcp *tcp = stream->data;

  if (count == 0) {
    return;
  }

  uv_read_stop(stream);
  tcp->reading = 0;

  if (count < 0) {
    tcp->readstatus = (int)count;
  }
  else {
    tcp->readstart = 0;
    tcp->readend = (size_t)count;
  }
}

int nupptcpreceive (NuppTcp *tcp, void *bytes, size_t size) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  if (!size) {
    return 0;
  }

  size_t available = tcp->readend - tcp->readstart;

  if (available) {
    size_t count = size < available ? size : available;
    memcpy(bytes, tcp->inbound + tcp->readstart, count);
    tcp->readstart += count;

    return (int)count;
  }

  if (tcp->readstatus) {
    return tcp->readstatus == UV_EOF ? 0 : tcp->readstatus;
  }

  if (tcp->reading) {
    return UV_EAGAIN;
  }

  int status = uv_read_start((uv_stream_t *)&tcp->stream, readbuffer, received);

  if (status < 0) {
    return status;
  }

  tcp->reading = 1;

  return UV_EAGAIN;
}

static void written (uv_write_t *request, int status) {
  NuppTcp *tcp = request->data;
  tcp->pending = 0;
  tcp->writestatus = status;
}

int nupptcpsend (NuppTcp *tcp, const void *bytes, size_t size) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  if (tcp->writestatus < 0) {
    return tcp->writestatus;
  }

  if (tcp->shuttingdown) {
    return UV_EPIPE;
  }

  if (!size) {
    return 0;
  }

  if (tcp->pending) {
    return UV_EAGAIN;
  }

  unsigned int count = size < WINDOW ? (unsigned int)size : WINDOW;
  memcpy(tcp->outbound, bytes, count);
  uv_buf_t buffer = uv_buf_init(tcp->outbound, count);
  tcp->write.data = tcp;
  int status =
      uv_write(&tcp->write, (uv_stream_t *)&tcp->stream, &buffer, 1, written);

  if (status < 0) {
    return status;
  }

  tcp->pending = (int)count;

  return (int)count;
}

int nupptcppending (const NuppTcp *tcp) {
  return tcp->writestatus < 0 ? tcp->writestatus : tcp->pending;
}

static void halfclosed (uv_shutdown_t *request, int status) {
  NuppTcp *tcp = request->data;
  tcp->shutdownstatus = status;
}

int nupptcpshutdown (NuppTcp *tcp) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  if (tcp->shuttingdown) {
    return tcp->shutdownstatus == UV_EAGAIN ? 0 : tcp->shutdownstatus;
  }

  tcp->shutdown.data = tcp;
  int status =
      uv_shutdown(&tcp->shutdown, (uv_stream_t *)&tcp->stream, halfclosed);

  if (status == 0) {
    tcp->shuttingdown = 1;
    tcp->shutdownstatus = UV_EAGAIN;
  }

  return status;
}

int nupptcpwriteclosed (const NuppTcp *tcp) {
  return tcp->shutdownstatus;
}

static void closed (uv_handle_t *handle) {
  NuppTcp *tcp = handle->data;
  tcp->closed = 1;
}

void nupptcpclose (NuppTcp *tcp) {
  if (!tcp->closing) {
    tcp->closing = 1;
    uv_close((uv_handle_t *)&tcp->stream, closed);
  }
}

int nupptcpfree (NuppTcp *tcp) {
  if (!tcp->closed) {
    return UV_EBUSY;
  }

  free(tcp);

  return 0;
}
