/**
 * @file
 * @brief Owned libuv TCP streams and listener handles.
 */

#ifndef NUPP_CORE_TCP_H
#define NUPP_CORE_TCP_H

#include <uv.h>

typedef struct NuppTcp NuppTcp;

/** Allocates an endpoint for the owning reactor thread. */
int nupptcpopen (uv_loop_t *loop, NuppTcp **out);
int nupptcpopenlocal (uv_loop_t *loop, NuppTcp **out);

/** Starts listening at a numeric address. Address storage is borrowed. */
int nupptcplisten (NuppTcp *tcp, const struct sockaddr *address, int backlog,
                   unsigned int flags);

/** Listens on a POSIX local path, whose directory entry is caller-owned. */
int nupptcplistenlocal (NuppTcp *tcp, const char *path, size_t size,
                        int backlog);

/** Copies the local address into caller storage. */
int nupptcplocal (NuppTcp *tcp, struct sockaddr *address, int *size);

/** Copies the peer address into caller storage. */
int nupptcppeer (NuppTcp *tcp, struct sockaddr *address, int *size);

/** Returns whether a peer can be accepted, or a pending listener error. */
int nupptcplistenready (NuppTcp *tcp);

/** Attempts to accept into a fresh endpoint on the same loop. */
int nupptcpaccept (NuppTcp *listener, NuppTcp *stream);

/** Submits one connection attempt. Address storage is borrowed. */
int nupptcpconnect (NuppTcp *tcp, const struct sockaddr *address);
int nupptcpconnectlocal (NuppTcp *tcp, const char *path, size_t size);

/** Reports the connection result or UV_EAGAIN while it is still pending. */
int nupptcpconnected (const NuppTcp *tcp);

/** Copies bytes, reports 0 at EOF, or UV_EAGAIN while waiting for input. */
int nupptcpreceive (NuppTcp *tcp, void *bytes, size_t size);

/** Copies to one bounded write slot. Returns the accepted byte count. */
int nupptcpsend (NuppTcp *tcp, const void *bytes, size_t size);

/** Reports bytes pending in the write slot or its persistent failure. */
int nupptcppending (const NuppTcp *tcp);

/** Reports clean EOF after the buffered input is consumed. */
int nupptcpended (const NuppTcp *tcp);

/** Applies the libuv TCP options to the live socket. */
int nupptcpnodelay (NuppTcp *tcp, int enable);
int nupptcpkeepalive (NuppTcp *tcp, int enable, unsigned int seconds);

/** Reports whether the caller requested a write half-close. */
int nupptcpshutting (const NuppTcp *tcp);

/** Starts a write half-close after previously accepted bytes are delivered. */
int nupptcpshutdown (NuppTcp *tcp);

/** Reports the half-close result or UV_EAGAIN until the callback arrived. */
int nupptcpwriteclosed (const NuppTcp *tcp);

/** Starts close on the owning loop. Any outstanding callbacks retain `tcp`. */
void nupptcpclose (NuppTcp *tcp);

/** Releases a closed endpoint. Returns UV_EBUSY until the loop has drained. */
int nupptcpfree (NuppTcp *tcp);

#endif
