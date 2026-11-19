/**
 * @file
 * @brief Exercises scoped TCP calls and DNS on the bridge's owned reactor.
 */

#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#elif !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif

#include "netbridge.h"
#include "reactor.h"
#include <uv.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <unistd.h>
#endif

static int64_t call (void *scope, uint64_t op, int64_t key, uint64_t option) {
  return nuppnetcall(scope, op, (uint64_t)key, NULL, 0, option);
}

static void datagrams (void *scope, uint64_t poller, uint64_t deadline) {
  int64_t from =
      nuppnetcall(scope, NUPP_NET_BIND_DATAGRAM, 0, "127.0.0.1", 9, 0);
  int64_t to = nuppnetcall(scope, NUPP_NET_BIND_DATAGRAM, 0, "127.0.0.1", 9, 0);
  assert(from > 0 && to > 0 && from != to);
  char address[64], packet[64], out[64];
  assert(nuppnetcall(scope, NUPP_NET_ADDRESS, (uint64_t)to, address,
                     sizeof(address), 0) > 0);
  unsigned long port = strtoul(address, NULL, 10);
  assert(port > 0 && port <= UINT16_MAX);
  int head = snprintf(packet, sizeof(packet), "%lu\n127.0.0.1\n", port);
  assert(head > 0 && head + 3 < (int)sizeof(packet));

  for (int size = 0; size <= 3; size += 3) {
    memcpy(packet + head, "x\0z", (size_t)size);
    assert(nuppnetcall(scope, NUPP_NET_SEND_DATAGRAM, (uint64_t)from, packet,
                       (uint64_t)(head + size), 0) == size);
    int64_t copied;

    do {
      assert(uv_hrtime() < deadline);
      copied = nuppnetcall(scope, NUPP_NET_RECEIVE_DATAGRAM, (uint64_t)to, out,
                           sizeof(out) - 1, 2);
      assert(copied >= 0 || copied == NUPP_NET_AGAIN);
      assert(nupp_uv_wait(poller, 1000000) == 0);
    } while (copied == NUPP_NET_AGAIN);

    out[copied] = '\0';
    char *sizeflag = strchr(out, '\n');
    assert(sizeflag && sizeflag[1] == (size ? '1' : '0'));
    char *body = strchr(sizeflag + 1, '\n');
    assert(body && strncmp(body + 1, "127.0.0.1\n", 10) == 0);
    body += 11;

    if (size) {
      assert(copied - (body - out) == 2 && body[0] == 'x' && body[1] == 0);
    }
    else {
      assert(out + copied == body);
    }
  }
}

#ifdef __APPLE__
static void zoneddatagrams (void *scope, uint64_t poller, uint64_t deadline) {
  char host[] = "fe80::1%lo0";
  int64_t from =
      nuppnetcall(scope, NUPP_NET_BIND_DATAGRAM, 0, host, sizeof(host) - 1, 0);

  if (from == UV_EADDRNOTAVAIL) {
    puts("link-local IPv6 loopback address unavailable");

    return;
  }

  assert(from > 0);
  int64_t to = nuppnetcall(scope, NUPP_NET_BIND_DATAGRAM, 0, "::", 2, 0);
  assert(to > 0);
  char address[64], packet[64], out[64];
  assert(nuppnetcall(scope, NUPP_NET_ADDRESS, (uint64_t)to, address,
                     sizeof(address), 0) > 0);
  unsigned long port = strtoul(address, NULL, 10);
  int head = snprintf(packet, sizeof(packet), "%lu\n%s\nx", port, host);

  for (int turn = 0; turn < 2; turn++) {
    assert(head > 0 && head < (int)sizeof(packet));
    assert(nuppnetcall(scope, NUPP_NET_SEND_DATAGRAM, (uint64_t)from, packet,
                       (uint64_t)head, 0) == 1);
    int64_t size;

    do {
      assert(uv_hrtime() < deadline);
      assert(nupp_uv_wait(poller, 1000000) == 0);
      size = nuppnetcall(scope, NUPP_NET_RECEIVE_DATAGRAM, (uint64_t)to, out,
                         sizeof(out) - 1, 1);
      assert(size >= 0 || size == NUPP_NET_AGAIN);
    } while (size == NUPP_NET_AGAIN);

    out[size] = '\0';
    port = strtoul(out, NULL, 10);
    char *peer = strstr(out, "\n0\n");
    assert(peer);
    peer += 3;
    char *body = strchr(peer, '\n');
    assert(body && strcmp(body, "\nx") == 0);
    *body = '\0';
    assert(strncmp(peer, "fe80::1%", 8) == 0 && strtoul(peer + 8, NULL, 10));
    head = snprintf(packet, sizeof(packet), "%lu\n%s\nx", port, peer);
    int64_t sent = from;
    from = to;
    to = sent;
  }

  puts("link-local IPv6 datagram reply preserved its interface");
}
#endif

#ifndef _WIN32
static void localsockets (void *scope, uint64_t poller, uint64_t deadline) {
  char directory[] = "/tmp/nupp-local-socket.XXXXXX";
  assert(mkdtemp(directory));
  char path[64];
  int length = snprintf(path, sizeof(path), "%s/listener", directory);
  assert(length > 0 && length < (int)sizeof(path));
  int64_t listener =
      nuppnetcall(scope, NUPP_NET_LISTEN_LOCAL, 0, path, (uint64_t)length, 4);
  int64_t request = nuppnetcall(scope, NUPP_NET_CONNECT_LOCAL, 0, path,
                                (uint64_t)length, 2000);
  assert(listener > 0 && request > 0);
  int64_t from = NUPP_NET_AGAIN, to = NUPP_NET_AGAIN;

  while (from == NUPP_NET_AGAIN || to == NUPP_NET_AGAIN) {
    assert(uv_hrtime() < deadline);
    assert(nupp_uv_wait(poller, 1000000) == 0);

    if (from == NUPP_NET_AGAIN) {
      from = call(scope, NUPP_NET_CONNECT_POLL, request, 0);
      assert(from > 0 || from == NUPP_NET_AGAIN);
    }

    if (to == NUPP_NET_AGAIN) {
      to = call(scope, NUPP_NET_ACCEPT, listener, 0);
      assert(to > 0 || to == NUPP_NET_AGAIN);
    }
  }

  assert(nuppnetcall(scope, NUPP_NET_WRITE, (uint64_t)from, "x", 1, 0) == 1);
  char byte;
  int64_t got;

  do {
    assert(uv_hrtime() < deadline);
    assert(nupp_uv_wait(poller, 1000000) == 0);
    got = nuppnetcall(scope, NUPP_NET_READ, (uint64_t)to, &byte, 1, 0);
    assert(got == 1 || got == NUPP_NET_AGAIN);
  } while (got == NUPP_NET_AGAIN);

  assert(byte == 'x');
  assert(call(scope, NUPP_NET_CLOSE, listener, 0) == 0);
  assert(nupp_uv_nowait() == 0);
  assert(unlink(path) == 0 && rmdir(directory) == 0);
}
#endif

int main (void) {
  int server, client;
  int64_t listener = nuppnetcall(&server, NUPP_NET_LISTEN, 0, "127.0.0.1", 9,
                                 UINT64_C(8) << 16);
  assert(listener > 0);
  assert(call(&client, NUPP_NET_ACCEPT, listener, 0) == UV_EBADF);
  assert(call(&server, NUPP_NET_ACCEPT, listener, 0) == NUPP_NET_AGAIN);
  char address[64];
  assert(nuppnetcall(&server, NUPP_NET_ADDRESS, (uint64_t)listener, address,
                     sizeof(address), 0) > 0);
  unsigned long port = strtoul(address, NULL, 10);
  assert(port > 0 && port <= UINT16_MAX);
  uint64_t options = port | (UINT64_C(5000) << 16);
  int64_t request =
      nuppnetcall(&client, NUPP_NET_CONNECT, 0, "localhost", 9, options);
  assert(request > 0);
  int64_t poller = nupp_uv_open(-1);
  assert(poller > 0);
  int64_t from = NUPP_NET_AGAIN, to = NUPP_NET_AGAIN;
  uint64_t deadline = uv_hrtime() + UINT64_C(5000000000);

  while (from == NUPP_NET_AGAIN || to == NUPP_NET_AGAIN) {
    assert(uv_hrtime() < deadline);
    assert(nupp_uv_wait((uint64_t)poller, 1000000) == 0);

    if (from == NUPP_NET_AGAIN) {
      from = call(&client, NUPP_NET_CONNECT_POLL, request, 0);
      assert(from > 0 || from == NUPP_NET_AGAIN);
    }

    if (to == NUPP_NET_AGAIN) {
      to = call(&server, NUPP_NET_ACCEPT, listener, 0);
      assert(to > 0 || to == NUPP_NET_AGAIN);
    }
  }

  assert(from != request);
  assert(call(&client, NUPP_NET_CLOSE, request, 0) == 0);
  assert(call(&client, NUPP_NET_NODELAY, from, 1) == 0);
  char sent[] = "net", got[4];
  assert(nuppnetcall(&client, NUPP_NET_WRITE, (uint64_t)from, sent, 3, 0) == 3);
  memset(sent, 0, sizeof(sent));
  assert(call(&client, NUPP_NET_SHUTDOWN, from, 0) == 0);
  size_t copied = 0;
  int64_t result;

  do {
    assert(uv_hrtime() < deadline);
    assert(nupp_uv_wait((uint64_t)poller, 1000000) == 0);
    result = nuppnetcall(&server, NUPP_NET_READ, (uint64_t)to, got + copied,
                         sizeof(got) - copied, 0);
    assert(result >= 0 || result == NUPP_NET_AGAIN);

    if (result > 0) {
      copied += (size_t)result;
      assert(copied < sizeof(got));
    }
  } while (result != 0);

  assert(copied == 3 && memcmp(got, "net", 3) == 0);
  assert(call(&server, NUPP_NET_ENDED, to, 0) == 1);
  datagrams(&client, (uint64_t)poller, deadline);
#ifdef __APPLE__
  zoneddatagrams(&client, (uint64_t)poller, deadline);
#endif
  char badzone[] = "::1%4294967296";
  assert(nuppnetcall(&client, NUPP_NET_BIND_DATAGRAM, 0, badzone,
                     sizeof(badzone) - 1, 0) == UV_EINVAL);
#ifndef _WIN32
  localsockets(&client, (uint64_t)poller, deadline);
#endif
  assert(nuppnetcall(&client, NUPP_NET_CONNECT, 0, "localhost", 9, options) >
         0);
  nuppnetdetach(&client);
  assert(call(&client, NUPP_NET_PENDING, from, 0) == UV_EBADF);
  nuppnetdetach(&server);
  assert(call(&server, NUPP_NET_ACCEPT, listener, 0) == UV_EBADF);
  assert(nupp_uv_shutdown() == 0 && !nuppnetpending());
  puts("core socket and DNS contracts passed");

  return 0;
}
