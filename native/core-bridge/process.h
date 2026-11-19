#ifndef NUPP_CORE_PROCESS_H
#define NUPP_CORE_PROCESS_H

#include <stdint.h>

/* Owner-thread calls. Spawn borrows strings and fds only for the call. The
 * positive result has the watch identity above bit 31 and the OS pid below. */
int64_t nupp_process_spawn (const char *file, char **args, char **env,
                            const char *cwd, int64_t input, int64_t output,
                            int64_t error, uint64_t search);
int64_t nupp_process_pipe (uint64_t read_nonblock, uint64_t write_nonblock);
int64_t nupp_process_watch (uint64_t poller, uint64_t child);
int64_t nupp_process_unwatch (uint64_t poller, uint64_t child);
int64_t nupp_process_reap (uint64_t child);
int64_t nupp_process_kill (uint64_t child, uint64_t signal);

/* Reactor hooks. Draining remains the responsibility of the loop owner. */
int64_t nupp_process_event (uint64_t poller);
void nupp_process_forget_poller (uint64_t poller);
int nupp_process_shutdown (void);
int nupp_process_pending (void);

#endif
