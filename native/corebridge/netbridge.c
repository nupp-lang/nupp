/**
 * @file
 * @brief Native handles for the core TCP provider.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "netbridge.h"
#include "reactor.h"
#include "tcp.h"
#include "udp.h"
#include <inttypes.h>
#include <limits.h>
#ifndef _WIN32
#include <net/if.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_ENDPOINTS = 512, MAX_DNS = 32, HOST_ROOM = 256 };

enum { LISTENER, CONNECT, STREAM, DATAGRAM };

typedef union {
  struct sockaddr base;
  struct sockaddr_in v4;
  struct sockaddr_in6 v6;
} InternetAddress;

typedef struct Endpoint {
  struct Endpoint *next;
  void *scope;
  uint64_t key, deadline;
  NuppTcp *tcp;
  NuppUdp *udp;
  uv_getaddrinfo_t lookup;
  struct addrinfo *addresses, *candidate;
  int kind, local, resolving, retiring, retrying, laststatus;
} Endpoint;

static _Thread_local Endpoint *endpoints;
static _Thread_local uint64_t issued;
static _Thread_local size_t count, lookups;

static Endpoint *find (void *scope, uint64_t key) {
  for (Endpoint *at = endpoints; at; at = at->next) {
    if (at->scope == scope && at->key == key && !at->retiring) {
      return at;
    }
  }

  return NULL;
}

static int allocate (void *scope, int kind, Endpoint **out) {
  if (count == MAX_ENDPOINTS || issued == INT64_MAX) {
    return UV_ENOBUFS;
  }

  Endpoint *endpoint = calloc(1, sizeof(*endpoint));

  if (!endpoint) {
    return UV_ENOMEM;
  }

  endpoint->scope = scope;
  endpoint->key = ++issued;
  endpoint->kind = kind;
  endpoint->next = endpoints;
  endpoints = endpoint;
  count++;
  *out = endpoint;

  return 0;
}

static void retire (Endpoint *endpoint) {
  endpoint->retiring = 1;
  endpoint->scope = NULL;

  if (endpoint->resolving) {
    uv_cancel((uv_req_t *)&endpoint->lookup);
  }

  if (endpoint->tcp) {
    nupptcpclose(endpoint->tcp);
  }

  if (endpoint->udp) {
    nuppudpclose(endpoint->udp);
  }
}

void nuppnetsweep (void) {
  Endpoint **at = &endpoints;

  while (*at) {
    Endpoint *endpoint = *at;

    if (!endpoint->retiring || endpoint->resolving ||
        (endpoint->tcp && nupptcpfree(endpoint->tcp) == UV_EBUSY) ||
        (endpoint->udp && nuppudpfree(endpoint->udp) == UV_EBUSY)) {
      at = &endpoint->next;
      continue;
    }

    if (endpoint->addresses) {
      uv_freeaddrinfo(endpoint->addresses);
    }

    *at = endpoint->next;
    free(endpoint);
    count--;
  }
}

void nuppnetdetach (void *scope) {
  for (Endpoint *endpoint = endpoints; endpoint; endpoint = endpoint->next) {
    if (endpoint->scope == scope) {
      retire(endpoint);
    }
  }

  nuppnetsweep();
}

void nuppnetshutdown (void) {
  for (Endpoint *endpoint = endpoints; endpoint; endpoint = endpoint->next) {
    if (!endpoint->retiring) {
      retire(endpoint);
    }
  }

  nuppnetsweep();
}

int nuppnetpending (void) {
  return endpoints != NULL;
}

static int opentransport (Endpoint *endpoint) {
  uv_loop_t *loop = nupp_uv_loop();

  if (!loop) {
    return UV_ENOMEM;
  }

  return endpoint->local ? nupptcpopenlocal(loop, &endpoint->tcp)
                         : nupptcpopen(loop, &endpoint->tcp);
}

static void resolved (uv_getaddrinfo_t *request, int status,
                      struct addrinfo *addresses) {
  Endpoint *endpoint = request->data;
  endpoint->resolving = 0;
  lookups--;
  endpoint->laststatus = status ? status : UV_EAI_NONAME;
  endpoint->addresses = addresses;
  endpoint->candidate = addresses;
}

static int resolve (Endpoint *endpoint, const char *host, unsigned port) {
  if (lookups == MAX_DNS) {
    return UV_ENOBUFS;
  }

  char service[6];
  snprintf(service, sizeof(service), "%u", port);
  struct addrinfo hints = {.ai_family = AF_UNSPEC,
                           .ai_socktype = SOCK_STREAM,
                           .ai_protocol = IPPROTO_TCP};
  endpoint->lookup.data = endpoint;
  uv_loop_t *loop = nupp_uv_loop();
  int status = loop ? uv_getaddrinfo(loop, &endpoint->lookup, resolved, host,
                                     service, &hints)
                    : UV_ENOMEM;

  if (status == 0) {
    endpoint->resolving = 1;
    lookups++;
  }

  return status;
}

static int scopeid (const char *zone, uint32_t *index) {
  const char *digits = zone + (zone[0] == '+');
  size_t length = strspn(digits, "0123456789");

  if (length && !digits[length]) {
    uint64_t number = strtoull(digits, NULL, 10);

    if (number > UINT32_MAX) {
      return UV_EINVAL;
    }

    *index = (uint32_t)number;

    return 0;
  }

#ifndef _WIN32
  *index = if_nametoindex(zone);

  if (*index) {
    return 0;
  }

#endif

  return UV_EINVAL;
}

static int numerichost (InternetAddress *address, const char *host, int port) {
  const char *zone = strchr(host, '%');

  if (zone) {
    char literal[INET6_ADDRSTRLEN];
    size_t size = (size_t)(zone - host);

    if (size >= sizeof(literal)) {
      return UV_EINVAL;
    }

    memcpy(literal, host, size);
    literal[size] = '\0';
    uint32_t index;
    int status = uv_ip6_addr(literal, port, &address->v6);

    if (status == 0) {
      status = scopeid(zone + 1, &index);

      if (status == 0) {
        address->v6.sin6_scope_id = index;
      }
    }

    return status;
  }

  if (uv_ip4_addr(host, port, &address->v4) == 0) {
    return 0;
  }

  return uv_ip6_addr(host, port, &address->v6);
}

static int64_t openendpoint (void *scope, int kind, const char *bytes,
                             uint64_t size, uint64_t option) {
  if (!bytes || !size || size >= HOST_ROOM || memchr(bytes, 0, (size_t)size) ||
      option >> 49) {
    return UV_EINVAL;
  }

  char host[HOST_ROOM];
  memcpy(host, bytes, (size_t)size);
  host[size] = '\0';
  unsigned port = (unsigned)(option & UINT16_MAX);
  uint64_t argument = (option >> 16) & UINT32_MAX;

  if (argument > INT_MAX || (kind == LISTENER && !argument)) {
    return UV_EINVAL;
  }

  InternetAddress number;
  const struct sockaddr *address =
      numerichost(&number, host, (int)port) < 0 ? NULL : &number.base;

  if (!address && (kind != CONNECT || strchr(host, '%'))) {
    return UV_EINVAL;
  }

  Endpoint *endpoint;
  int status = allocate(scope, kind, &endpoint);

  if (status < 0) {
    return status;
  }

  if (kind == CONNECT) {
    endpoint->deadline = uv_hrtime() + argument * UINT64_C(1000000);
  }

  if (kind == DATAGRAM) {
    uv_loop_t *loop = nupp_uv_loop();
    status = loop ? nuppudpopen(loop, &endpoint->udp) : UV_ENOMEM;

    if (status == 0) {
      status = nuppudpbind(endpoint->udp, address,
                           option >> 48 ? UV_UDP_REUSEPORT : 0);
    }
  }
  else {
    status = address ? opentransport(endpoint) : resolve(endpoint, host, port);

    if (status == 0 && address) {
      status = kind == LISTENER
                   ? nupptcplisten(endpoint->tcp, address, (int)argument,
                                   option >> 48 ? UV_TCP_REUSEPORT : 0)
                   : nupptcpconnect(endpoint->tcp, address);
    }
  }

  if (status < 0) {
    retire(endpoint);

    return status;
  }

  return (int64_t)endpoint->key;
}

static int64_t acceptpeer (Endpoint *listener) {
  int status = nupptcplistenready(listener->tcp);

  if (status <= 0) {
    return status < 0 ? status : NUPP_NET_AGAIN;
  }

  Endpoint *stream;
  status = allocate(listener->scope, STREAM, &stream);

  if (status < 0) {
    return status;
  }

  stream->local = listener->local;
  status = opentransport(stream);

  if (status == 0) {
    status = nupptcpaccept(listener->tcp, stream->tcp);
  }

  if (status < 0) {
    retire(stream);

    return status == UV_EAGAIN ? NUPP_NET_AGAIN : status;
  }

  return (int64_t)stream->key;
}

static int64_t openlocal (void *scope, int kind, const char *path,
                          uint64_t size, uint64_t option) {
  if (!path || !size || size >= HOST_ROOM || memchr(path, 0, (size_t)size) ||
      option > INT_MAX || (kind == LISTENER && !option)) {
    return UV_EINVAL;
  }

  Endpoint *endpoint;
  int status = allocate(scope, kind, &endpoint);

  if (status < 0) {
    return status;
  }

  endpoint->local = 1;
  status = opentransport(endpoint);

  if (status == 0) {
    if (kind == LISTENER) {
      status =
          nupptcplistenlocal(endpoint->tcp, path, (size_t)size, (int)option);
    }
    else {
      endpoint->deadline = uv_hrtime() + option * UINT64_C(1000000);
      status = nupptcpconnectlocal(endpoint->tcp, path, (size_t)size);
    }
  }

  if (status < 0) {
    retire(endpoint);

    return status;
  }

  return (int64_t)endpoint->key;
}

static int64_t pollconnect (Endpoint *endpoint) {
  if (!endpoint->resolving && endpoint->tcp && !endpoint->retrying) {
    int status = nupptcpconnected(endpoint->tcp);

    if (status == 0) {
      if (issued == INT64_MAX) {
        return UV_ENOBUFS;
      }

      endpoint->kind = STREAM;
      endpoint->key = ++issued;

      if (endpoint->addresses) {
        uv_freeaddrinfo(endpoint->addresses);
        endpoint->addresses = NULL;
        endpoint->candidate = NULL;
      }

      return (int64_t)endpoint->key;
    }

    if (status != UV_EAGAIN) {
      endpoint->laststatus = status;
      nupptcpclose(endpoint->tcp);
      endpoint->retrying = 1;
    }
  }

  if (uv_hrtime() >= endpoint->deadline) {
    retire(endpoint);

    return UV_ETIMEDOUT;
  }

  if (endpoint->resolving) {
    return NUPP_NET_AGAIN;
  }

  if (endpoint->tcp) {
    if (!endpoint->retrying || nupptcpfree(endpoint->tcp) == UV_EBUSY) {
      return NUPP_NET_AGAIN;
    }

    endpoint->tcp = NULL;
    endpoint->retrying = 0;
  }

  struct addrinfo *candidate = endpoint->candidate;

  if (!candidate) {
    return endpoint->laststatus;
  }

  endpoint->candidate = candidate->ai_next;
  int status = opentransport(endpoint);

  if (status < 0) {
    return status;
  }

  status = nupptcpconnect(endpoint->tcp, candidate->ai_addr);

  if (status < 0) {
    endpoint->laststatus = status;
    nupptcpclose(endpoint->tcp);
    endpoint->retrying = 1;
  }

  return NUPP_NET_AGAIN;
}

static int formataddress (const struct sockaddr *value, char *host,
                          unsigned *port) {
  if (value->sa_family == AF_INET) {
    const struct sockaddr_in *v4 = (const struct sockaddr_in *)value;
    *port = ntohs(v4->sin_port);

    return uv_ip4_name(v4, host, HOST_ROOM);
  }

  if (value->sa_family == AF_INET6) {
    const struct sockaddr_in6 *v6 = (const struct sockaddr_in6 *)value;
    *port = ntohs(v6->sin6_port);
    int status = uv_ip6_name(v6, host, HOST_ROOM);

    if (status < 0 || !v6->sin6_scope_id) {
      return status;
    }

    size_t size = strlen(host), room = HOST_ROOM - size;
    int written =
        snprintf(host + size, room, "%%%" PRIu32, (uint32_t)v6->sin6_scope_id);

    return written < 0 || (size_t)written >= room ? UV_ENOBUFS : 0;
  }

  return UV_EAFNOSUPPORT;
}

static int address (Endpoint *endpoint, int peer, char *out, uint64_t room) {
  struct sockaddr_storage storage;
  struct sockaddr *value = (struct sockaddr *)&storage;
  int size = sizeof(storage);
  int status;

  if (endpoint->kind == DATAGRAM) {
    status = peer ? UV_EINVAL : nuppudplocal(endpoint->udp, value, &size);
  }
  else {
    status = peer ? nupptcppeer(endpoint->tcp, value, &size)
                  : nupptcplocal(endpoint->tcp, value, &size);
  }

  if (status < 0) {
    return status;
  }

  char host[HOST_ROOM];
  unsigned port;
  status = formataddress(value, host, &port);

  if (status < 0) {
    return status;
  }

  int written = snprintf(out, (size_t)room, "%u\n%s", port, host);

  return written < 0 || (uint64_t)written >= room ? UV_ENOBUFS : written;
}

static int receivedatagram (NuppUdp *udp, char *out, uint64_t room,
                            uint64_t maximum) {
  const char *bytes;
  const struct sockaddr *source;
  int cut;
  int count = nuppudpnext(udp, &bytes, &source, &cut);

  if (count == UV_EAGAIN) {
    return NUPP_NET_AGAIN;
  }

  if (count < 0) {
    nuppudpconsume(udp);

    return count;
  }

  char host[HOST_ROOM];
  unsigned port;
  int status = formataddress(source, host, &port);

  if (status < 0) {
    nuppudpconsume(udp);

    return status;
  }

  uint64_t copied = (uint64_t)count < maximum ? (uint64_t)count : maximum;
  int head = snprintf(out, (size_t)room, "%u\n%d\n%s\n", port,
                      cut || copied < (uint64_t)count, host);

  if (head < 0 || (uint64_t)head >= room || copied > room - (uint64_t)head) {
    return UV_ENOBUFS;
  }

  memcpy(out + head, bytes, (size_t)copied);
  nuppudpconsume(udp);

  return head + (int)copied;
}

/** Copies one bounded text field and returns the unconsumed binary suffix. */
static const char *field (const char *start, const char *end, char *out,
                          size_t room) {
  if (start == end) {
    return NULL;
  }

  const char *split = memchr(start, '\n', (size_t)(end - start));

  if (!split || (size_t)(split - start) >= room ||
      memchr(start, 0, (size_t)(split - start))) {
    return NULL;
  }

  size_t size = (size_t)(split - start);
  memcpy(out, start, size);
  out[size] = '\0';

  return split + 1;
}

static int senddatagram (NuppUdp *udp, const char *bytes, uint64_t size) {
  if (!bytes || size > NUPP_UDP_WINDOW + HOST_ROOM + 7) {
    return UV_EINVAL;
  }

  const char *end = bytes + size;
  char service[6], host[HOST_ROOM];
  const char *next = field(bytes, end, service, sizeof(service));
  const char *body = next ? field(next, end, host, sizeof(host)) : NULL;
  unsigned port = 0;

  if (!body || !service[0]) {
    return UV_EINVAL;
  }

  for (const char *at = service; *at; at++) {
    if (*at < '0' || *at > '9') {
      return UV_EINVAL;
    }

    port = port * 10 + (unsigned)(*at - '0');
  }

  InternetAddress to;

  if (port > UINT16_MAX || numerichost(&to, host, (int)port) < 0) {
    return UV_EINVAL;
  }

  return nuppudpsend(udp, &to.base, body, (size_t)(end - body));
}

static int membership (NuppUdp *udp, const char *bytes, uint64_t size,
                       int join) {
  if (!bytes || size > UINT64_C(2) * HOST_ROOM) {
    return UV_EINVAL;
  }

  const char *end = bytes + size;
  char group[HOST_ROOM], local[HOST_ROOM];
  const char *rest = field(bytes, end, group, sizeof(group));

  if (!rest || field(rest, end, local, sizeof(local)) != end) {
    return UV_EINVAL;
  }

  return nuppudpmembership(udp, group, local[0] ? local : NULL, join);
}

static int datagram (NuppUdp *udp, uint64_t op, void *bytes, uint64_t size,
                     uint64_t option) {
  switch (op) {
    case NUPP_NET_RECEIVE_DATAGRAM:
      return receivedatagram(udp, bytes, size, option);
    case NUPP_NET_SEND_DATAGRAM:
      return senddatagram(udp, bytes, size);
    case NUPP_NET_BROADCAST:
      return nuppudpbroadcast(udp, option != 0);
    case NUPP_NET_MULTICAST_TTL:
      return option <= 255 ? nuppudpttl(udp, (int)option) : UV_EINVAL;
    case NUPP_NET_MULTICAST_LOOP:
      return nuppudploop(udp, option != 0);
    case NUPP_NET_JOIN:
    case NUPP_NET_LEAVE:
      return membership(udp, bytes, size, op == NUPP_NET_JOIN);
    default:
      return UV_EINVAL;
  }
}

int64_t nuppnetcall (void *scope, uint64_t op, uint64_t key, void *bytes,
                     uint64_t size, uint64_t option) {
  if (!scope || (!bytes && size)) {
    return UV_EINVAL;
  }

  if (op == NUPP_NET_ERROR) {
    const char *message = uv_strerror((int)(int64_t)key);
    int written = snprintf(bytes, (size_t)size, "%s", message);

    return written >= 0 && (uint64_t)written < size ? written : UV_ENOBUFS;
  }

  if (op == NUPP_NET_LISTEN || op == NUPP_NET_CONNECT) {
    return openendpoint(scope, op == NUPP_NET_LISTEN ? LISTENER : CONNECT,
                        bytes, size, option);
  }

  if (op == NUPP_NET_BIND_DATAGRAM) {
    return openendpoint(scope, DATAGRAM, bytes, size, option);
  }

  if (op == NUPP_NET_LISTEN_LOCAL || op == NUPP_NET_CONNECT_LOCAL) {
    return openlocal(scope, op == NUPP_NET_LISTEN_LOCAL ? LISTENER : CONNECT,
                     bytes, size, option);
  }

  Endpoint *endpoint = find(scope, key);

  if (!endpoint) {
    return op == NUPP_NET_CLOSE ? 0 : UV_EBADF;
  }

  if (op == NUPP_NET_CLOSE) {
    retire(endpoint);

    return 0;
  }

  if (op == NUPP_NET_ACCEPT && endpoint->kind == LISTENER) {
    return acceptpeer(endpoint);
  }

  if (op == NUPP_NET_CONNECT_POLL && endpoint->kind == CONNECT) {
    return pollconnect(endpoint);
  }

  if (op == NUPP_NET_ADDRESS && endpoint->kind != CONNECT) {
    return address(endpoint, option != 0, bytes, size);
  }

  if (endpoint->kind == DATAGRAM) {
    return datagram(endpoint->udp, op, bytes, size, option);
  }

  if (endpoint->kind != STREAM) {
    return UV_EINVAL;
  }

  NuppTcp *tcp = endpoint->tcp;
  int status;

  switch (op) {
    case NUPP_NET_READ:
      status = nupptcpreceive(tcp, bytes, (size_t)size);

      return status == UV_EAGAIN ? NUPP_NET_AGAIN : status;
    case NUPP_NET_WRITE:
      status = nupptcpsend(tcp, bytes, (size_t)size);

      return status == UV_EAGAIN ? NUPP_NET_AGAIN : status;
    case NUPP_NET_ENDED:
      return nupptcpended(tcp);
    case NUPP_NET_PENDING:
      return nupptcppending(tcp);
    case NUPP_NET_SHUTDOWN:
      return nupptcpshutdown(tcp);
    case NUPP_NET_SHUTTING:
      return nupptcpshutting(tcp);
    case NUPP_NET_NODELAY:
      return nupptcpnodelay(tcp, option != 0);
    case NUPP_NET_KEEPALIVE:
      return option > UINT64_C(1) + UINT32_MAX
                 ? UV_EINVAL
                 : nupptcpkeepalive(tcp, option != 0,
                                    (unsigned int)((option + 998) / 1000));
    default:
      return UV_EINVAL;
  }
}
