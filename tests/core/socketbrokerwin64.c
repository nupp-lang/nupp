/**
 * @file
 * @brief Checks that the Win64 socket broker preserves full-width handles.
 *
 * A sentinel SOCKET and two distinct high-bit values exercise the broker
 * without requiring Winsock to allocate a high handle.
 */
#include <uv.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>

static uv_os_sock_t validated, registered_socket;
static unsigned validations, registrations;
static int synthetic = 1;

static int validate_socket (SOCKET socket, int level, int option, char *out,
                            int *room) {
  if (!synthetic) {
    return getsockopt(socket, level, option, out, room);
  }

  int type = SOCK_STREAM;
  assert(level == SOL_SOCKET && option == SO_TYPE && *room == sizeof(type));
  memcpy(out, &type, sizeof(type));
  validated = socket;
  validations++;

  return 0;
}

static int register_socket (uv_loop_t *loop, uv_poll_t *poll,
                            uv_os_sock_t socket) {
  if (!synthetic) {
    return uv_poll_init_socket(loop, poll, socket);
  }

  assert(loop && poll);
  registered_socket = socket;
  registrations++;

  /* Stop before poll_start: the test's handles do not belong to Winsock. */
  return UV_EINVAL;
}

#define getsockopt validate_socket
#define uv_poll_init_socket register_socket
#include "../../native/corebridge/uv.c" /* NOLINT(bugprone-suspicious-include) */
#undef uv_poll_init_socket
#undef getsockopt

static void width_and_stale_tokens (void) {
  _Static_assert(sizeof(uintptr_t) == 8 && sizeof(uv_os_sock_t) == 8,
                 "this contract exercises Win64 SOCKET values");
  _Static_assert(
      _Generic(&nupp_uv_socket_open, int64_t (*)(uintptr_t): 1, default: 0),
      "socket registration accepts a full native socket word");

  const uintptr_t first = UINT64_C(0x800000000000002a);
  const uintptr_t second = UINT64_C(0x800001000000002a);
  assert(nupp_uv_socket_open((uintptr_t)INVALID_SOCKET) == -EBADF);
  assert(!validations && !registrations);
  assert(nupp_uv_descriptor_open((int64_t)(uint32_t)first) == -ENOSYS);

  int64_t owner = nupp_uv_socket_open(first);
  assert(owner > 0 && validated == first && validations == 1);
  assert(nupp_uv_socket_open(first) == -EEXIST && validations == 1);
  int64_t other = nupp_uv_socket_open(second);
  assert(other > owner && validated == second && validations == 2);
  int64_t observer = nupp_uv_socket_observe((uint64_t)owner);
  assert(observer > other);
  assert(nupp_uv_socket_arm((uint64_t)observer, 1) == UV_EINVAL);
  assert(registered_socket == first && registrations == 1);
  assert(nupp_uv_socket_arm((uint64_t)other, 2) == UV_EINVAL);
  assert(registered_socket == second && registrations == 2);
  assert(!nupp_uv_socket_retire((uint64_t)owner));
  assert(nupp_uv_socket_arm((uint64_t)observer, 1) == -EBADF);
  assert(nupp_uv_socket_take((uint64_t)owner) == -EBADF);

  int64_t fresh = nupp_uv_socket_open(first);
  assert(fresh > observer && validations == 3);
  assert(nupp_uv_socket_observe((uint64_t)owner) == -EBADF);
  assert(!nupp_uv_socket_retire((uint64_t)fresh));
  assert(!nupp_uv_socket_retire((uint64_t)other));
  assert(!nupp_uv_shutdown());
}

typedef struct {
  SOCKET peer, accepted;
  uint64_t owner;
} SocketPair;

static SocketPair connect_pair (SOCKET listener,
                                const struct sockaddr_in *address) {
  SOCKET peer = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  assert(peer != INVALID_SOCKET);
  assert(!connect(peer, (const struct sockaddr *)address, sizeof(*address)));
  SOCKET accepted = accept(listener, NULL, NULL);
  assert(accepted != INVALID_SOCKET);
  int64_t owner = nupp_uv_socket_open((uintptr_t)accepted);
  assert(owner > 0);

  return (SocketPair){peer, accepted, (uint64_t)owner};
}

static void arm_idle_read (uint64_t owner) {
  assert(!nupp_uv_socket_arm(owner, 1));
  assert(!nupp_uv_socket_ready(owner));
  const uv_poll_t *poll = &poller(owner)->subscriptions->watch->handle;

  /* For the pinned Win64 libuv, prove an actual pending AFD read on IOCP.
   * The peer stays connected and sends no data between arm and retire. */
  assert(poll->peer_socket && poll->peer_socket != INVALID_SOCKET);
  assert(((poll->submitted_events_1 & UV_READABLE) &&
          !HasOverlappedIoCompleted(&poll->poll_req_1.u.io.overlapped)) ||
         ((poll->submitted_events_2 & UV_READABLE) &&
          !HasOverlappedIoCompleted(&poll->poll_req_2.u.io.overlapped)));
}

static void forbidden_owner_step (void *ctx, uint32_t budget) {
  (void)ctx;
  (void)budget;
  assert(0 && "shutdown cannot drive the owner");
}

static uint32_t forbidden_owner_ready (void *ctx) {
  (void)ctx;
  assert(0 && "shutdown cannot query the owner");

  return 0;
}

static void winsock_wait (void) {
  synthetic = 0;
  WSADATA startup;
  assert(!WSAStartup(MAKEWORD(2, 2), &startup));
  SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  assert(listener != INVALID_SOCKET);
  struct sockaddr_in address = {0};
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  assert(!bind(listener, (struct sockaddr *)&address, sizeof(address)));
  assert(!listen(listener, 1));
  int address_bytes = sizeof(address);
  assert(!getsockname(listener, (struct sockaddr *)&address, &address_bytes));

  int64_t turn = nupp_uv_open(-1);
  assert(turn > 0);

  /* The pinned IOCP backend dequeues at most 128 requests per loop turn. */
  enum { PAIRS = 129 };

  SocketPair pairs[PAIRS];
  pairs[0] = connect_pair(listener, &address);
  uint64_t owner = pairs[0].owner;
  int64_t observer = nupp_uv_socket_observe(owner);
  assert(observer > 0);
  assert(!nupp_uv_socket_arm(owner, 1));
  assert(!nupp_uv_socket_arm((uint64_t)observer, 1));
  assert(send(pairs[0].peer, "x", 1, 0) == 1);

  for (int i = 0; i < 10 && !nupp_uv_socket_ready(owner); ++i) {
    assert(!nupp_uv_wait_owner((uint64_t)turn, 100000000));
  }

  assert(nupp_uv_socket_take(owner) == 1);
  assert(nupp_uv_socket_take((uint64_t)observer) == 1);
  assert(!nupp_uv_socket_take((uint64_t)observer));
  int64_t timer = nupp_uv_timer_open();
  assert(timer > 0);
  assert(!nupp_uv_timer_replace((uint64_t)timer, 0));
  assert(!nupp_uv_nowait());
  assert(nupp_uv_timer_take((uint64_t)timer) == 1);
  assert(!nupp_uv_timer_replace((uint64_t)timer, 60000));
  char received;
  assert(recv(pairs[0].accepted, &received, 1, 0) == 1 && received == 'x');
  assert(!nupp_uv_close((uint64_t)turn));
  arm_idle_read(owner);

  for (size_t i = 1; i < PAIRS; ++i) {
    pairs[i] = connect_pair(listener, &address);
    arm_idle_read(pairs[i].owner);
  }

  assert(!closesocket(listener));
  uv_timer_t unretired;
  assert(!uv_timer_init(nupp_uv_loop(), &unretired));
  assert(!nupp_uv_set_owner_driver(forbidden_owner_step, forbidden_owner_ready,
                                   NULL));
  assert(!nupp_uv_begin_shutdown());
  assert(nupp_uv_shutdown() == -EBUSY);

  for (size_t i = 0; i < PAIRS; ++i) {
    assert(!nupp_uv_socket_retire(pairs[i].owner));
    assert(!closesocket(pairs[i].accepted));
    assert(!closesocket(pairs[i].peer));
  }

  assert(nupp_uv_socket_ready((uint64_t)observer) == -EBADF);
  assert(!nupp_uv_timer_close((uint64_t)timer));
  Service *backing = service;
  assert(service->closing_watches == PAIRS && service->closing_timers == 1);
  assert(nupp_uv_shutdown() == -EBUSY);
  assert(service == backing && service->closing_watches == PAIRS);
  assert(!nupp_uv_set_owner_driver(NULL, NULL, NULL));

  /* Drain all broker closes, then retain the loop on a foreign live handle.
   * The successful retry must not use the now-closed deadline timer. */
  assert(nupp_uv_shutdown() == UV_EBUSY);
  assert(service == backing && !service->closing_watches &&
         !service->closing_timers);
  assert(uv_is_closing((uv_handle_t *)&service->timer));
  uv_close((uv_handle_t *)&unretired, NULL);
  assert(!nupp_uv_shutdown());
  assert(!service);
  assert(!WSACleanup());
}

int main (void) {
  width_and_stale_tokens();
  winsock_wait();

  return 0;
}
