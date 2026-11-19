#ifndef NUPP_CORE_REACTOR_H
#define NUPP_CORE_REACTOR_H
#include <stdint.h>
struct uv_loop_s;
/* Raw completion transport only. Tokens are never operating-system fds. */
/* Owner-thread borrow, NULL on initialization failure. Never drive recursively;
 * adapters retire every attached request/handle before runtime shutdown. */
struct uv_loop_s *nupp_uv_loop (void);
/* One nonblocking owner-loop turn: 0, or a negative error such as -EBUSY
 * for recursive entry. Callbacks only enqueue; no service means no work. */
int nupp_uv_nowait (void);
/* 1 for a live subscription on this thread, 0 for missing/retired tokens. */
int nupp_uv_valid_poller (uint64_t token);
/* Capture queued file work against the descriptor before Nupp closes it. */
void nupp_uv_preserve_file (uint64_t descriptor);
/* Positive token or negative error. Owns process_fd only on success; -1 omits
 * it. */
int64_t nupp_uv_open (int64_t process_fd);
/* Borrowed compatibility descriptor, or -EBADF for a retired token. */
int64_t nupp_uv_processfd (uint64_t token);
/* One-shot interest (read=1/write=2); zero withdraws without closing the fd. */
int64_t nupp_uv_arm (uint64_t token, int64_t fd, uint64_t interest);
/* Encoded fd*32+readiness, zero for no event, or negative error. 0 nanos is
 * nonblocking; UINT64_MAX waits without a timer. Callbacks never run guests. */
int64_t nupp_uv_wait (uint64_t token, uint64_t nanos);
/* 0 retires the token and drains its close callbacks; watched file fds survive.
 * A shared watch stays alive for other subscriptions. File jobs remain owned
 * by their tickets and require finish/settle independently. */
int64_t nupp_uv_close (uint64_t token);
/* Final runtime boundary: withdraw/settle jobs, close handles, drain callbacks,
 * then destroy the loop; 0 on quiescence, negative error on refusal. */
int64_t nupp_uv_shutdown (void);
#endif
