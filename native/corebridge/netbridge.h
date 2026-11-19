/**
 * @file
 * @brief Scoped TCP and asynchronous resolution on the core's owned loop.
 */

#ifndef NUPP_CORE_NETBRIDGE_H
#define NUPP_CORE_NETBRIDGE_H

#include <stdint.h>

enum {
  NUPP_NET_LISTEN = 1,
  NUPP_NET_CONNECT,
  NUPP_NET_ACCEPT,
  NUPP_NET_CONNECT_POLL,
  NUPP_NET_CLOSE,
  NUPP_NET_READ,
  NUPP_NET_WRITE,
  NUPP_NET_ENDED,
  NUPP_NET_PENDING,
  NUPP_NET_SHUTDOWN,
  NUPP_NET_SHUTTING,
  NUPP_NET_ADDRESS,
  NUPP_NET_NODELAY,
  NUPP_NET_KEEPALIVE,
  NUPP_NET_ERROR,
  NUPP_NET_BIND_DATAGRAM,
  NUPP_NET_RECEIVE_DATAGRAM,
  NUPP_NET_SEND_DATAGRAM,
  NUPP_NET_BROADCAST,
  NUPP_NET_MULTICAST_TTL,
  NUPP_NET_MULTICAST_LOOP,
  NUPP_NET_JOIN,
  NUPP_NET_LEAVE,
  NUPP_NET_LISTEN_LOCAL,
  NUPP_NET_CONNECT_LOCAL
};

enum { NUPP_NET_AGAIN = INT32_MIN };

/**
 * Performs one operation on the owning reactor thread. The scope and key
 * must match. Bytes are borrowed only for the call; read and address write
 * at most size bytes. LISTEN and CONNECT pack port in the low 16 bits of
 * option and backlog or timeout ms above it. LISTEN uses bit 48 for reuse.
 * ADDRESS replies with decimal port, a newline and numeric host bytes.
 */
int64_t nuppnetcall (void *scope, uint64_t op, uint64_t key, void *bytes,
                     uint64_t size, uint64_t option);

/** Retires scope identities without retaining a borrow of guest memory. */
void nuppnetdetach (void *scope);

/** Frees drained handles and requests on the owner thread. */
void nuppnetsweep (void);

/** Retires every scope before the loop itself closes. */
void nuppnetshutdown (void);
int nuppnetpending (void);

#endif
