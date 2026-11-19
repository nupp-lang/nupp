/**
 * @file
 * @brief Moves bytes through libuv without retaining guest storage.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "tcp.h"
#include "streamio.h"
#include <stdlib.h>

struct NuppTcp {
  NuppStreamIO io;
  uv_tcp_t stream;
  uv_connect_t connection;
  uv_shutdown_t shutdown;
  int connecting, connectstatus, listenerror, listenready;
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

  tcp->stream.data = &tcp->io;
  tcp->connectstatus = UV_ENOTCONN;
  tcp->shutdownstatus = UV_ENOTCONN;
  *out = tcp;

  return 0;
}

static void waiting (uv_stream_t *stream, int status) {
  NuppTcp *tcp = stream->data;
  tcp->listenerror = status;

  if (status == 0) {
    tcp->listenready++;
  }
}

int nupptcplisten (NuppTcp *tcp, const struct sockaddr *address, int backlog,
                   unsigned int flags) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  int status = uv_tcp_bind(&tcp->stream, address, flags);

  return status < 0 ? status
                    : uv_listen((uv_stream_t *)&tcp->stream, backlog, waiting);
}

int nupptcplocal (NuppTcp *tcp, struct sockaddr *address, int *size) {
  return tcp->closing ? UV_EBADF
                      : uv_tcp_getsockname(&tcp->stream, address, size);
}

int nupptcppeer (NuppTcp *tcp, struct sockaddr *address, int *size) {
  return tcp->closing ? UV_EBADF
                      : uv_tcp_getpeername(&tcp->stream, address, size);
}

int nupptcplistenready (NuppTcp *tcp) {
  if (tcp->listenerror < 0) {
    int status = tcp->listenerror;
    tcp->listenerror = 0;

    return status;
  }

  return tcp->listenready;
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

  if (status == UV_EAGAIN) {
    listener->listenready = 0;
  }

  if (status == 0) {
    if (listener->listenready) {
      listener->listenready--;
    }

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

int nupptcpreceive (NuppTcp *tcp, void *bytes, size_t size) {
  return tcp->closing
             ? UV_EBADF
             : nuppstreamread((uv_stream_t *)&tcp->stream, bytes, size);
}

int nupptcpsend (NuppTcp *tcp, const void *bytes, size_t size) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  if (tcp->shuttingdown) {
    return UV_EPIPE;
  }

  return nuppstreamwrite((uv_stream_t *)&tcp->stream, bytes, size);
}

int nupptcppending (const NuppTcp *tcp) {
  return nuppstreampending(&tcp->io);
}

int nupptcpended (const NuppTcp *tcp) {
  return tcp->io.readstatus == UV_EOF && tcp->io.readstart == tcp->io.readend;
}

int nupptcpnodelay (NuppTcp *tcp, int enable) {
  return uv_tcp_nodelay(&tcp->stream, enable);
}

int nupptcpkeepalive (NuppTcp *tcp, int enable, unsigned int seconds) {
  return uv_tcp_keepalive(&tcp->stream, enable, seconds);
}

int nupptcpshutting (const NuppTcp *tcp) {
  return tcp->shuttingdown;
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
