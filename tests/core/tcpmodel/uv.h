/**
 * @file
 * @brief Minimal libuv declarations for CBMC's TCP callback model.
 *
 * The native build and C lint use the pinned libuv header. The proof models
 * callbacks and retained buffers independently of libuv's platform layout.
 */

#ifndef NUPP_TEST_TCP_MODEL_UV_H
#define NUPP_TEST_TCP_MODEL_UV_H

#include <stddef.h>
#include <sys/types.h>

struct sockaddr;

typedef struct {
  int unused;
} uv_loop_t;

typedef struct {
  void *data;
} uv_handle_t;

typedef uv_handle_t uv_tcp_t;
typedef uv_handle_t uv_stream_t;

typedef struct {
  void *data;
} uv_connect_t, uv_write_t, uv_shutdown_t;

typedef struct {
  char *base;
  size_t len;
} uv_buf_t;

typedef void (*uv_connection_cb)(uv_stream_t *, int);
typedef void (*uv_connect_cb)(uv_connect_t *, int);
typedef void (*uv_alloc_cb)(uv_handle_t *, size_t, uv_buf_t *);
typedef void (*uv_read_cb)(uv_stream_t *, ssize_t, const uv_buf_t *);
typedef void (*uv_write_cb)(uv_write_t *, int);
typedef void (*uv_shutdown_cb)(uv_shutdown_t *, int);
typedef void (*uv_close_cb)(uv_handle_t *);

enum {
  UV_EAGAIN = -11,
  UV_EALREADY = -114,
  UV_EBADF = -9,
  UV_EBUSY = -16,
  UV_ECANCELED = -125,
  UV_EOF = -4095,
  UV_EIO = -5,
  UV_ENOMEM = -12,
  UV_ENOTCONN = -107,
  UV_EPIPE = -32
};

int uv_tcp_init (uv_loop_t *, uv_tcp_t *);
int uv_tcp_bind (uv_tcp_t *, const struct sockaddr *, unsigned);
int uv_listen (uv_stream_t *, int, uv_connection_cb);
int uv_tcp_getsockname (const uv_tcp_t *, struct sockaddr *, int *);
int uv_tcp_getpeername (const uv_tcp_t *, struct sockaddr *, int *);
int uv_tcp_nodelay (uv_tcp_t *, int);
int uv_tcp_keepalive (uv_tcp_t *, int, unsigned);
int uv_accept (uv_stream_t *, uv_stream_t *);
int uv_tcp_connect (uv_connect_t *, uv_tcp_t *, const struct sockaddr *,
                    uv_connect_cb);
uv_buf_t uv_buf_init (char *, unsigned);
int uv_read_start (uv_stream_t *, uv_alloc_cb, uv_read_cb);
int uv_read_stop (uv_stream_t *);
int uv_write (uv_write_t *, uv_stream_t *, const uv_buf_t[], unsigned,
              uv_write_cb);
int uv_shutdown (uv_shutdown_t *, uv_stream_t *, uv_shutdown_cb);
void uv_close (uv_handle_t *, uv_close_cb);

#endif
