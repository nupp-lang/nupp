/**
 * @file
 * @brief Owner-thread process operations and exit notifications.
 */

#ifndef NUPP_CORE_PROCESS_H
#define NUPP_CORE_PROCESS_H

#include <stdint.h>

/** Owner-thread calls. Spawn borrows strings and fds only for the call. The
 * positive result has the watch identity above bit 31 and the OS pid below. */
int64_t nupp_process_spawn (const char *file, char **args, char **env,
                            const char *cwd, int64_t input, int64_t output,
                            int64_t error, uint64_t search);

/** Opens a pipe. Packs the read fd below the write fd in the result. */
int64_t nupp_process_pipe (uint64_t read_nonblock, uint64_t write_nonblock);

/** Arms a one-shot notification for a child on a live poller. */
int64_t nupp_process_watch (uint64_t poller, uint64_t child);

/** Withdraws a child watch from a live poller. */
int64_t nupp_process_unwatch (uint64_t poller, uint64_t child);

/**
 * Returns zero while the child runs, then consumes its exit result.
 * A missing or already reaped child returns -ECHILD.
 */
int64_t nupp_process_reap (uint64_t child);

/** Signals the live child's process group. */
int64_t nupp_process_kill (uint64_t child, uint64_t signal);

/* Reactor hooks. Draining remains the responsibility of the loop owner. */
/**
 * Consumes one ready child notification for the poller, or returns zero.
 * The event carries the child identity above the readiness bits.
 */
int64_t nupp_process_event (uint64_t poller);

/** Withdraws every child watch associated with a poller. */
void nupp_process_forget_poller (uint64_t poller);

/**
 * Stops tracked children and withdraws their watches. The owner continues
 * driving the loop until pending process handles have closed.
 */
int nupp_process_shutdown (void);

/** Reports whether any child records still await disposal. */
int nupp_process_pending (void);

#endif
