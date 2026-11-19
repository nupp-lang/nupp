/**
 * @file
 * @brief Single-datagram staging on the core's owning libuv loop.
 */

#ifndef NUPP_CORE_UDP_H
#define NUPP_CORE_UDP_H

#include <uv.h>

typedef struct NuppUdp NuppUdp;

enum { NUPP_UDP_WINDOW = 65536 };

/** Allocates and binds a socket. The address is borrowed for the call. */
int nuppudpopen (uv_loop_t *loop, NuppUdp **out);
int nuppudpbind (NuppUdp *udp, const struct sockaddr *address, unsigned flags);
int nuppudplocal (NuppUdp *udp, struct sockaddr *address, int *size);

/**
 * Returns a pending datagram's byte count, UV_EAGAIN, or an error.
 * Data and address are borrowed until consume or close on this thread.
 */
int nuppudpnext (NuppUdp *udp, const char **bytes,
                 const struct sockaddr **address, int *truncated);
void nuppudpconsume (NuppUdp *udp);

/** Offers a complete datagram synchronously. No supplied pointer is retained.
 */
int nuppudpsend (NuppUdp *udp, const struct sockaddr *address,
                 const void *bytes, size_t size);

/** Changes native socket options on the owner thread. */
int nuppudpbroadcast (NuppUdp *udp, int enabled);
int nuppudpttl (NuppUdp *udp, int ttl);
int nuppudploop (NuppUdp *udp, int enabled);
int nuppudpmembership (NuppUdp *udp, const char *group, const char *local,
                       int join);

/** Retires native I/O. Free succeeds after the close callback has drained. */
void nuppudpclose (NuppUdp *udp);
int nuppudpfree (NuppUdp *udp);

#endif
