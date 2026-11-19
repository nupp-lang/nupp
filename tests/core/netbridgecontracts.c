/**
 * @file
 * @brief Exercises scoped TCP calls and DNS on the bridge's owned reactor.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "netbridge.h"
#include "reactor.h"
#include <uv.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int64_t call (void *scope, uint64_t op, int64_t key, uint64_t option) {
  return nuppnetcall(scope, op, (uint64_t)key, NULL, 0, option);
}

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
  assert(nuppnetcall(&client, NUPP_NET_CONNECT, 0, "localhost", 9, options) >
         0);
  nuppnetdetach(&client);
  assert(call(&client, NUPP_NET_PENDING, from, 0) == UV_EBADF);
  nuppnetdetach(&server);
  assert(call(&server, NUPP_NET_ACCEPT, listener, 0) == UV_EBADF);
  assert(nupp_uv_shutdown() == 0 && !nuppnetpending());
  puts("core TCP and DNS contracts passed");

  return 0;
}
