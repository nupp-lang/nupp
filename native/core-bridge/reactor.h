/**
 * @file
 * @brief Owner-thread reactor operations for descriptors, sockets, timers, and
 * file work.
 */

#ifndef NUPP_CORE_REACTOR_H
#define NUPP_CORE_REACTOR_H
#include <stdint.h>

#ifdef _WIN32

/** The one-shot file completion key, outside the CRT descriptor range. */
#define NUPP_UV_FILE_COMPLETION INT64_C(0x100000000)

/** Checks whether the descriptor names an open CRT file on Win64. */
int nupp_uv_valid_file (int64_t descriptor);
#endif

/* The packet's six I/O imports use the same calling contract as transport.h. */
uint64_t nuppiostart (uint64_t threads);
uint64_t nuppiosubmit (uint64_t kind, uint64_t word, uint64_t base,
                       uint64_t bytes);
uint64_t nuppiotake (void);
uint64_t nuppiofinish (uint64_t ticket, uint64_t out, uint64_t room);
uint64_t nuppiocancel (uint64_t ticket);

/* Spends a ticket after its native callback. Transfers opened descriptors
 * to the caller and discards read bytes. */
uint64_t nuppiosettle (uint64_t ticket);

struct uv_loop_s;

/* Raw completion transport only. Tokens are never operating-system fds. */
/** Owner-thread borrow, NULL on initialization failure or shutdown. Never drive
 * recursively;
 * adapters retire every attached request/handle before runtime shutdown. */
struct uv_loop_s *nupp_uv_loop (void);

/** One nonblocking owner-loop turn: 0, or a negative error such as -EBUSY
 * for recursive entry. Callbacks only enqueue; no service means no work. */
int nupp_uv_nowait (void);

/** 1 for a live subscription on this thread, 0 for missing/retired tokens. */
int nupp_uv_valid_poller (uint64_t token);

/** Capture queued file work against the descriptor before Nupp closes it. */
void nupp_uv_preserve_file (uint64_t descriptor);

/** Positive token or negative error. Owns process_fd only on success; -1 omits
 * it. */
int64_t nupp_uv_open (int64_t process_fd);

/** Borrowed compatibility descriptor, or -EBADF for a retired token. */
int64_t nupp_uv_processfd (uint64_t token);

/** One-shot interest (read=1/write=2); zero withdraws without closing the fd.
 */
int64_t nupp_uv_arm (uint64_t token, int64_t fd, uint64_t interest);

/** Encoded fd*32+readiness, zero for no event, or negative error. 0 nanos is
 * nonblocking; UINT64_MAX waits without a timer. Callbacks never run guests. */
int64_t nupp_uv_wait (uint64_t token, uint64_t nanos);

/** Scheduler-only turn. Cached events and work ready for the owner allow
 * one nonblocking turn; zero is valid even when the adapter moved work. */
int64_t nupp_uv_wait_owner (uint64_t token, uint64_t nanos);

/** Read-only: deferred closes or armed/ready native work for the owner driver.
 */
int nupp_uv_owner_active (void);

typedef void (*nupp_uv_owner_step_fn)(void *ctx, uint32_t budget);
typedef uint32_t (*nupp_uv_owner_ready_fn)(void *ctx);

enum {
  NUPP_UV_OWNER_ACTIVE = 1,
  NUPP_UV_OWNER_NATIVE_READY = 2,
  NUPP_UV_OWNER_MANAGED_READY = 4
};

/** Bootstrap binds one native driver on the owner thread. It takes no guest
 * callbacks. ready is read-only and reports deliverable managed readiness.
 * Both callbacks run outside uv_run, under the same reentry guard. Clear
 * with three NULLs after adapter cleanup, before destroying the loop. */
int nupp_uv_set_owner_driver (nupp_uv_owner_step_fn step,
                              nupp_uv_owner_ready_fn ready, void *ctx);

/** 0 retires the token and drains its close callbacks; watched file fds
 * survive. A shared watch stays alive for other subscriptions. File jobs remain
 * owned by their tickets and require finish/settle independently. */
int64_t nupp_uv_close (uint64_t token);

/** One registration per canonical socket, owned by the adapter that closes it.
 * Win64 passes the full Winsock SOCKET. On POSIX it is the canonical fd.
 * Aliases must use the same owner token. Tokens never recycle. */
int64_t nupp_uv_socket_open (uintptr_t socket);

/** POSIX pollable fd, including resolver pipes and eventfd. Borrows the fd
 * through the same token API below. Retire the token before closing the fd.
 * libuv may set O_NONBLOCK when creating the watch. */
int64_t nupp_uv_descriptor_open (int64_t fd);

/** Creates an independent readiness subscription to an owner token. */
int64_t nupp_uv_socket_observe (uint64_t owner);

/** One-shot read=1/write=2; zero disarms and discards unread events. Take
 * consumes queued bits (read/write/hangup=4/error=8), without running the loop.
 */
int nupp_uv_socket_arm (uint64_t token, uint64_t interest);

/** Consumes queued readiness from the subscription. */
int nupp_uv_socket_take (uint64_t token);

/* Same bits and errors as take, without consuming or driving the loop. */
int nupp_uv_socket_ready (uint64_t token);

/** Drop only the observer. Retire all subscriptions before the owner closes its
 * socket or descriptor. Neither function closes it or drives the loop. */
int nupp_uv_socket_drop (uint64_t observer);

/** Retires the owner token and all its readiness subscriptions. */
int nupp_uv_socket_retire (uint64_t owner);

/** A separate timer from the loop's wait deadline. Replace clears old
 * readiness; -1 disarms, zero queues readiness for the next owner turn. */
int64_t nupp_uv_timer_open (void);

/** Replaces or disarms the timer and clears unread readiness. */
int nupp_uv_timer_replace (uint64_t token, int64_t delay_ms);

/** Consumes pending timer readiness. */
int nupp_uv_timer_take (uint64_t token);

/* Same readiness and errors as take, without consuming or driving the loop. */
int nupp_uv_timer_ready (uint64_t token);

/** Retires the timer token and schedules its handle for close. */
int nupp_uv_timer_close (uint64_t token);

/** Stop new admission to the active loop before adapter cleanup. Disarm,
 * detach, retire and drain remain valid. The runtime then calls shutdown, which
 * refuses live adapter tokens and drains the reactor-owned close callbacks. */
int nupp_uv_begin_shutdown (void);

/** Final runtime boundary: withdraw/settle jobs, close handles, drain
 * callbacks, then destroy the loop; 0 on quiescence, negative error on refusal.
 */
int64_t nupp_uv_shutdown (void);
#endif
