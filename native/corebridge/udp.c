/**
 * @file
 * @brief Owns one libuv datagram socket and at most one received datagram.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "udp.h"
#include <stdlib.h>
#include <string.h>

struct NuppUdp {
  uv_udp_t handle;
  struct sockaddr_storage source;
  char bytes[NUPP_UDP_WINDOW];
  int reading, ready, status, truncated, closed;
};

int nuppudpopen (uv_loop_t *loop, NuppUdp **out) {
  *out = NULL;
  NuppUdp *udp = calloc(1, sizeof(*udp));

  if (!udp) {
    return UV_ENOMEM;
  }

  int status = uv_udp_init(loop, &udp->handle);

  if (status < 0) {
    free(udp);

    return status;
  }

  udp->handle.data = udp;
  *out = udp;

  return 0;
}

int nuppudpbind (NuppUdp *udp, const struct sockaddr *address, unsigned flags) {
  return uv_udp_bind(&udp->handle, address, flags);
}

int nuppudplocal (NuppUdp *udp, struct sockaddr *address, int *size) {
  return uv_udp_getsockname(&udp->handle, address, size);
}

static void buffer (uv_handle_t *handle, size_t suggested, uv_buf_t *out) {
  (void)suggested;
  NuppUdp *udp = handle->data;
  *out = uv_buf_init(udp->bytes, sizeof(udp->bytes));
}

static void received (uv_udp_t *handle, ssize_t count, const uv_buf_t *input,
                      const struct sockaddr *source, unsigned flags) {
  (void)input;
  NuppUdp *udp = handle->data;

  if (count == 0 && !source) {
    return;
  }

  uv_udp_recv_stop(handle);
  udp->reading = 0;
  udp->ready = 1;
  udp->status = (int)count;
  udp->truncated = !!(flags & UV_UDP_PARTIAL);

  if (count >= 0) {
    if (source->sa_family == AF_INET) {
      memcpy(&udp->source, source, sizeof(struct sockaddr_in));
    }
    else if (source->sa_family == AF_INET6) {
      memcpy(&udp->source, source, sizeof(struct sockaddr_in6));
    }
    else {
      udp->status = UV_EAFNOSUPPORT;
    }
  }
}

int nuppudpnext (NuppUdp *udp, const char **bytes,
                 const struct sockaddr **address, int *truncated) {
  if (udp->ready) {
    *bytes = udp->bytes;
    *address = (const struct sockaddr *)&udp->source;
    *truncated = udp->truncated;

    return udp->status;
  }

  if (!udp->reading) {
    int status = uv_udp_recv_start(&udp->handle, buffer, received);

    if (status < 0) {
      return status;
    }

    udp->reading = 1;
  }

  return UV_EAGAIN;
}

void nuppudpconsume (NuppUdp *udp) {
  udp->ready = 0;
}

int nuppudpsend (NuppUdp *udp, const struct sockaddr *address,
                 const void *bytes, size_t size) {
  if (size > NUPP_UDP_WINDOW) {
    return UV_EMSGSIZE;
  }

  uv_buf_t payload = uv_buf_init((char *)bytes, (unsigned int)size);

  return uv_udp_try_send(&udp->handle, &payload, 1, address);
}

int nuppudpbroadcast (NuppUdp *udp, int enabled) {
  return uv_udp_set_broadcast(&udp->handle, enabled);
}

int nuppudpttl (NuppUdp *udp, int ttl) {
  return uv_udp_set_multicast_ttl(&udp->handle, ttl);
}

int nuppudploop (NuppUdp *udp, int enabled) {
  return uv_udp_set_multicast_loop(&udp->handle, enabled);
}

int nuppudpmembership (NuppUdp *udp, const char *group, const char *local,
                       int join) {
  return uv_udp_set_membership(&udp->handle, group, local,
                               join ? UV_JOIN_GROUP : UV_LEAVE_GROUP);
}

static void closed (uv_handle_t *handle) {
  NuppUdp *udp = handle->data;
  udp->closed = 1;
}

void nuppudpclose (NuppUdp *udp) {
  uv_handle_t *handle = (uv_handle_t *)&udp->handle;

  if (!uv_is_closing(handle)) {
    uv_close(handle, closed);
  }
}

int nuppudpfree (NuppUdp *udp) {
  if (!udp->closed) {
    return UV_EBUSY;
  }

  free(udp);

  return 0;
}
