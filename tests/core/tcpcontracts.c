/**
 * @file
 * @brief Exercises bounded, owned TCP transfers over a real loopback peer.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "tcp.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define SECOND UINT64_C(1000000000)

static void step (uv_loop_t *loop, uint64_t deadline) {
  assert(uv_hrtime() < deadline);
  uv_run(loop, UV_RUN_NOWAIT);
  uv_sleep(1);
}

static NuppTcp *openendpoint (uv_loop_t *loop) {
  NuppTcp *endpoint;
  assert(nupptcpopen(loop, &endpoint) == 0);

  return endpoint;
}

static void transfer (uv_loop_t *loop, NuppTcp *sender, NuppTcp *receiver) {
  enum { SIZE = 40000 };

  char source[SIZE], output[SIZE];

  for (size_t i = 0; i < sizeof(source); i++) {
    source[i] = (char)(i % 113);
  }

  uint64_t deadline = uv_hrtime() + 5 * SECOND;
  assert(nupptcpreceive(receiver, output, sizeof(output)) == UV_EAGAIN);
  int count = nupptcpsend(sender, source, sizeof(source));
  assert(count > 0 && count < (int)sizeof(source));
  assert(nupptcppending(sender) == count);
  assert(nupptcpsend(sender, source, sizeof(source)) == UV_EAGAIN);
  size_t submitted = (size_t)count, received = 0;

  do {
    step(loop, deadline);
    count =
        nupptcpreceive(receiver, output + received, sizeof(output) - received);
    assert(count >= 0 || count == UV_EAGAIN);

    if (count > 0) {
      received += (size_t)count;
    }

    if (submitted < sizeof(source)) {
      count =
          nupptcpsend(sender, source + submitted, sizeof(source) - submitted);
      assert(count > 0 || count == UV_EAGAIN);

      if (count > 0) {
        submitted += (size_t)count;
      }
    }
  } while (received != sizeof(output));

  assert(submitted == sizeof(source));
  assert(memcmp(source, output, sizeof(output)) == 0);
  assert(nupptcpshutdown(sender) == 0);
  assert(nupptcpshutting(sender));
  assert(nupptcpshutdown(sender) == 0);
  assert(nupptcpsend(sender, source, 1) == UV_EPIPE);

  do {
    step(loop, deadline);
    count = nupptcpreceive(receiver, output, 1);
    assert(count == 0 || count == UV_EAGAIN);
  } while (count);

  while (nupptcpwriteclosed(sender) == UV_EAGAIN) {
    step(loop, deadline);
  }

  assert(nupptcpwriteclosed(sender) == 0);
  assert(!nupptcpshutting(sender));
  assert(nupptcppending(sender) == 0);
  assert(nupptcpsend(sender, source, 1) == UV_EPIPE);
  assert(nupptcpreceive(receiver, output, 1) == 0);
  assert(nupptcpsend(receiver, "ok", 2) == 2);

  size_t reply = 0;

  do {
    step(loop, deadline);
    count = nupptcpreceive(sender, output + reply, 2 - reply);
    assert(count > 0 || count == UV_EAGAIN);

    if (count > 0) {
      reply += (size_t)count;
    }
  } while (reply != 2);

  assert(memcmp(output, "ok", 2) == 0);
}

int main (void) {
  uv_loop_t loop;
  assert(uv_loop_init(&loop) == 0);
  NuppTcp *listener = openendpoint(&loop);
  NuppTcp *client = openendpoint(&loop);
  NuppTcp *server = openendpoint(&loop);
  NuppTcp *cancelled = openendpoint(&loop);

  struct sockaddr_in address;
  int size = sizeof(address);
  assert(uv_ip4_addr("127.0.0.1", 0, &address) == 0);
  assert(nupptcplisten(listener, (const struct sockaddr *)&address, 8, 0) == 0);
  assert(nupptcplocal(listener, (struct sockaddr *)&address, &size) == 0);
  assert(address.sin_port != 0);
  assert(nupptcpaccept(listener, server) == UV_EAGAIN);
  assert(nupptcpconnect(client, (const struct sockaddr *)&address) == 0);
  assert(nupptcpconnected(client) == UV_EAGAIN);

  uint64_t deadline = uv_hrtime() + 5 * SECOND;
  int result;

  do {
    step(&loop, deadline);
    result = nupptcpaccept(listener, server);
    assert(result == 0 || result == UV_EAGAIN);
  } while (result);

  while (nupptcpconnected(client) == UV_EAGAIN) {
    step(&loop, deadline);
  }

  assert(nupptcpconnected(client) == 0);
  assert(nupptcpconnected(server) == 0);
  transfer(&loop, client, server);

  char byte;
  assert(nupptcpreceive(client, &byte, 1) == UV_EAGAIN);
  assert(nupptcpsend(server, "unread", 6) == 6);
  assert(nupptcpconnect(cancelled, (const struct sockaddr *)&address) == 0);
  nupptcpclose(cancelled);
  assert(nupptcpfree(cancelled) == UV_EBUSY);
  nupptcpclose(cancelled);
  nupptcpclose(client);
  nupptcpclose(server);
  assert(nupptcpfree(client) == UV_EBUSY);
  assert(nupptcpfree(server) == UV_EBUSY);
  nupptcpclose(listener);
  uv_run(&loop, UV_RUN_DEFAULT);
  assert(nupptcpconnected(cancelled) == UV_ECANCELED);
  assert(nupptcpfree(cancelled) == 0);
  assert(nupptcpfree(client) == 0);
  assert(nupptcpfree(server) == 0);
  assert(nupptcpfree(listener) == 0);
  assert(uv_loop_close(&loop) == 0);
  puts("libuv TCP transport contracts passed");

  return 0;
}
