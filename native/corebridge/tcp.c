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

#ifndef _WIN32
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#endif

enum { WRITE_OPEN, WRITE_ENDING, WRITE_ENDED };

struct NuppTcp {
  NuppStreamIO io;

  union {
    uv_tcp_t internet;
    uv_pipe_t local;
  } socket;

  uv_connect_t connection;
  uv_shutdown_t shutdown;
  int connecting, connectstatus, listenerror, listenready;
  int writestate, shutdownstatus;
  int closing, closed, local;
};

static uv_stream_t *handle (NuppTcp *tcp) {
  return tcp->local ? (uv_stream_t *)&tcp->socket.local
                    : (uv_stream_t *)&tcp->socket.internet;
}

static int openstream (uv_loop_t *loop, int local, NuppTcp **out) {
  *out = NULL;
  NuppTcp *tcp = calloc(1, sizeof(*tcp));

  if (!tcp) {
    return UV_ENOMEM;
  }

  tcp->local = local;
  int status = local ? uv_pipe_init(loop, &tcp->socket.local, 0)
                     : uv_tcp_init(loop, &tcp->socket.internet);

  if (status < 0) {
    free(tcp);

    return status;
  }

  handle(tcp)->data = &tcp->io;
  tcp->connectstatus = UV_ENOTCONN;
  tcp->shutdownstatus = UV_ENOTCONN;
  *out = tcp;

  return 0;
}

int nupptcpopen (uv_loop_t *loop, NuppTcp **out) {
  return openstream(loop, 0, out);
}

int nupptcpopenlocal (uv_loop_t *loop, NuppTcp **out) {
#ifdef _WIN32
  (void)loop;
  (void)out;

  return UV_ENOSYS;
#else

  return openstream(loop, 1, out);
#endif
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
  if (tcp->closing || tcp->local) {
    return UV_EBADF;
  }

  int status = uv_tcp_bind(&tcp->socket.internet, address, flags);

  return status < 0 ? status : uv_listen(handle(tcp), backlog, waiting);
}

int nupptcplistenlocal (NuppTcp *tcp, const char *path, size_t size,
                        int backlog) {
#ifdef _WIN32
  (void)tcp;
  (void)path;
  (void)size;
  (void)backlog;

  return UV_ENOSYS;
#else
  struct sockaddr_un address = {0};

  if (tcp->closing || !tcp->local || !size ||
      size >= sizeof(address.sun_path)) {
    return UV_EINVAL;
  }

  socklen_t length =
      (socklen_t)(offsetof(struct sockaddr_un, sun_path) + size + 1);
  address.sun_family = AF_UNIX;
#ifdef __APPLE__
  address.sun_len = (unsigned char)length;
#endif
  memcpy(address.sun_path, path, size);

  /* Own the descriptor without giving libuv an unlinkable pathname. A caller
   * controls the lifetime of the directory entry, including any replacement. */
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);

  if (fd < 0) {
    return uv_translate_sys_error(errno);
  }

  if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 ||
      bind(fd, (const struct sockaddr *)&address, length) < 0) {
    int status = uv_translate_sys_error(errno);
    close(fd);

    return status;
  }

  int status = uv_pipe_open(&tcp->socket.local, fd);

  if (status < 0) {
    close(fd);

    return status;
  }

  return uv_listen(handle(tcp), backlog, waiting);
#endif
}

int nupptcplocal (NuppTcp *tcp, struct sockaddr *address, int *size) {
  return tcp->closing || tcp->local
             ? UV_EBADF
             : uv_tcp_getsockname(&tcp->socket.internet, address, size);
}

int nupptcppeer (NuppTcp *tcp, struct sockaddr *address, int *size) {
  return tcp->closing || tcp->local
             ? UV_EBADF
             : uv_tcp_getpeername(&tcp->socket.internet, address, size);
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
  if (listener->closing || stream->closing ||
      listener->local != stream->local) {
    return UV_EBADF;
  }

  if (listener->listenerror < 0) {
    int status = listener->listenerror;
    listener->listenerror = 0;

    return status;
  }

  int status = uv_accept(handle(listener), handle(stream));

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

  if (tcp->connecting || tcp->local) {
    return UV_EALREADY;
  }

  tcp->connection.data = tcp;
  int status = uv_tcp_connect(&tcp->connection, &tcp->socket.internet, address,
                              connected);

  if (status == 0) {
    tcp->connecting = 1;
    tcp->connectstatus = UV_EAGAIN;
  }

  return status;
}

int nupptcpconnectlocal (NuppTcp *tcp, const char *path, size_t size) {
  if (tcp->closing || !tcp->local || tcp->connecting) {
    return UV_EINVAL;
  }

  tcp->connection.data = tcp;
  int status = uv_pipe_connect2(&tcp->connection, &tcp->socket.local, path,
                                size, UV_PIPE_NO_TRUNCATE, connected);

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
  return tcp->closing ? UV_EBADF : nuppstreamread(handle(tcp), bytes, size);
}

int nupptcpsend (NuppTcp *tcp, const void *bytes, size_t size) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  if (tcp->writestate != WRITE_OPEN) {
    return UV_EPIPE;
  }

  return nuppstreamwrite(handle(tcp), bytes, size);
}

int nupptcppending (const NuppTcp *tcp) {
  if (tcp->writestate == WRITE_ENDED && tcp->shutdownstatus < 0) {
    return tcp->shutdownstatus;
  }

  return nuppstreampending(&tcp->io);
}

int nupptcpended (const NuppTcp *tcp) {
  return tcp->io.readstatus == UV_EOF && tcp->io.readstart == tcp->io.readend;
}

int nupptcpnodelay (NuppTcp *tcp, int enable) {
  return tcp->local ? UV_ENOTSUP
                    : uv_tcp_nodelay(&tcp->socket.internet, enable);
}

int nupptcpkeepalive (NuppTcp *tcp, int enable, unsigned int seconds) {
  return tcp->local ? UV_ENOTSUP
                    : uv_tcp_keepalive(&tcp->socket.internet, enable, seconds);
}

int nupptcpshutting (const NuppTcp *tcp) {
  return tcp->writestate == WRITE_ENDING;
}

static void halfclosed (uv_shutdown_t *request, int status) {
  NuppTcp *tcp = request->data;
  tcp->shutdownstatus = status;
  tcp->writestate = WRITE_ENDED;
}

int nupptcpshutdown (NuppTcp *tcp) {
  if (tcp->closing) {
    return UV_EBADF;
  }

  if (tcp->writestate != WRITE_OPEN) {
    return tcp->writestate == WRITE_ENDING ? 0 : tcp->shutdownstatus;
  }

  tcp->shutdown.data = tcp;
  int status = uv_shutdown(&tcp->shutdown, handle(tcp), halfclosed);

  if (status == 0) {
    tcp->writestate = WRITE_ENDING;
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
    uv_close((uv_handle_t *)handle(tcp), closed);
  }
}

int nupptcpfree (NuppTcp *tcp) {
  if (!tcp->closed) {
    return UV_EBUSY;
  }

  free(tcp);

  return 0;
}
