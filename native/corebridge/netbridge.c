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
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_ENDPOINTS = 512, MAX_DNS = 32, HOST_ROOM = 256 };

enum { LISTENER, CONNECT, STREAM };

typedef struct Endpoint {
  struct Endpoint *next;
  void *scope;
  uint64_t key, deadline;
  NuppTcp *tcp;
  uv_getaddrinfo_t lookup;
  struct addrinfo *addresses, *candidate;
  int kind, resolving, retiring, retrying, laststatus;
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
}

void nuppnetsweep (void) {
  Endpoint **at = &endpoints;

  while (*at) {
    Endpoint *endpoint = *at;

    if (!endpoint->retiring || endpoint->resolving ||
        (endpoint->tcp && nupptcpfree(endpoint->tcp) == UV_EBUSY)) {
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

  return loop ? nupptcpopen(loop, &endpoint->tcp) : UV_ENOMEM;
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

  struct sockaddr_in v4;
  struct sockaddr_in6 v6;
  const struct sockaddr *address = NULL;

  if (uv_ip4_addr(host, (int)port, &v4) == 0) {
    address = (const struct sockaddr *)&v4;
  }
  else if (uv_ip6_addr(host, (int)port, &v6) == 0) {
    address = (const struct sockaddr *)&v6;
  }

  if (kind == LISTENER && !address) {
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

  status = address ? opentransport(endpoint) : resolve(endpoint, host, port);

  if (status == 0 && address) {
    status = kind == LISTENER
                 ? nupptcplisten(endpoint->tcp, address, (int)argument,
                                 option >> 48 ? UV_TCP_REUSEPORT : 0)
                 : nupptcpconnect(endpoint->tcp, address);
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

static int address (Endpoint *endpoint, int peer, char *out, uint64_t room) {
  struct sockaddr_storage storage;
  struct sockaddr *value = (struct sockaddr *)&storage;
  int size = sizeof(storage);
  int status = peer ? nupptcppeer(endpoint->tcp, value, &size)
                    : nupptcplocal(endpoint->tcp, value, &size);

  if (status < 0) {
    return status;
  }

  char host[HOST_ROOM];
  unsigned port;

  if (value->sa_family == AF_INET) {
    const struct sockaddr_in *v4 = (const struct sockaddr_in *)value;
    status = uv_ip4_name(v4, host, sizeof(host));
    port = ntohs(v4->sin_port);
  }
  else if (value->sa_family == AF_INET6) {
    const struct sockaddr_in6 *v6 = (const struct sockaddr_in6 *)value;
    status = uv_ip6_name(v6, host, sizeof(host));
    port = ntohs(v6->sin6_port);
  }
  else {
    return UV_EAFNOSUPPORT;
  }

  if (status < 0) {
    return status;
  }

  int written = snprintf(out, (size_t)room, "%u\n%s", port, host);

  return written < 0 || (uint64_t)written >= room ? UV_ENOBUFS : written;
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
      return option > INT_MAX
                 ? UV_EINVAL
                 : nupptcpkeepalive(tcp, option != 0,
                                    (unsigned int)((option + 999) / 1000));
    default:
      return UV_EINVAL;
  }
}
