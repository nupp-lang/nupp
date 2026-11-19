#define _POSIX_C_SOURCE 200809L
#include "process.h"
#include "reactor.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define SECOND UINT64_C(1000000000)

static uint64_t start (const char *file, const char *script, char **env,
                       const char *cwd, int input, int output, int error,
                       uint64_t search) {
  char *args[] = {(char *)file, "-c", (char *)script, NULL};
  int64_t spawned =
      nupp_process_spawn(file, args, env, cwd, input, output, error, search);
  assert(spawned > 0);

  return (uint64_t)spawned;
}

static void pipe_pair (int *reader, int *writer, int keep_read) {
  int64_t fds = nupp_process_pipe(keep_read, !keep_read);
  assert(fds > 0);
  *reader = (int)(uint32_t)fds;
  *writer = (int)((uint64_t)fds >> 32);
  assert(fcntl(*reader, F_GETFD) & FD_CLOEXEC);
  assert(fcntl(*writer, F_GETFD) & FD_CLOEXEC);
  assert(!!(fcntl(*reader, F_GETFL) & O_NONBLOCK) == keep_read);
  assert(!!(fcntl(*writer, F_GETFL) & O_NONBLOCK) == !keep_read);
}

static int64_t await_reap (uint64_t poller, uint64_t child) {
  int64_t result = 0;

  while (!result) {
    assert(nupp_uv_wait(poller, SECOND) >= 0);
    result = nupp_process_reap(child);
  }

  return result;
}

static void wait_readable (uint64_t poller, int fd) {
  assert(nupp_uv_arm(poller, fd, 1) == 0);
  int64_t event;

  do {
    event = nupp_uv_wait(poller, SECOND);
    assert(event >= 0);
  } while (!event);

  assert(event >> 5 == fd);
  assert(nupp_uv_arm(poller, fd, 0) == 0);
}

void nupp_process_contracts (void) {
  alarm(15);
  assert(setenv("PATH", "/usr/bin:/bin", 1) == 0);
  int64_t first = nupp_uv_open(-1), second = nupp_uv_open(-1);
  assert(first > 0 && second > 0 && first != second);

  char *missing[] = {"no-such-nupp-process", NULL};
  assert(nupp_process_spawn(missing[0], missing, NULL, NULL, -1, -1, -1, 1) ==
         -ENOENT);
  assert(nupp_process_spawn("sh", missing, NULL, NULL, -1, -1, -1, 0) ==
         -ENOENT);

  char *env[] = {"PATH=/no-such-path", "ONLY=ready", NULL};
  uint64_t early = start(
      "sh", "test \"$PATH:$ONLY:$PWD\" = '/no-such-path:ready:/' && exit 7",
      env, "/", -1, -1, -1, 1);
  /* Advance to actual native exit before installing the language watch. */
  int64_t registered;

  do {
    assert(nupp_uv_wait((uint64_t)first, SECOND) >= 0);
    registered = nupp_process_watch((uint64_t)first, early >> 32);

    if (!registered) {
      assert(nupp_process_unwatch((uint64_t)first, early >> 32) == 0);
    }
  } while (!registered);

  assert(registered == -ESRCH);
  assert(nupp_process_reap(early >> 32) == 263);
  assert(nupp_process_reap(early >> 32) == -ECHILD);
  assert(nupp_process_kill(early >> 32, SIGKILL) == -ESRCH);
  assert(waitpid((pid_t)(uint32_t)early, NULL, WNOHANG) == -1 &&
         errno == ECHILD);

  int read_fd, write_fd;
  pipe_pair(&read_fd, &write_fd, 0);
  uint64_t inherited =
      start("/bin/sh", "exit 0", NULL, NULL, -1, write_fd, -1, 0);
  assert(fcntl(write_fd, F_GETFL) & O_NONBLOCK);
  assert(await_reap((uint64_t)first, inherited >> 32) == 256);
  close(read_fd);
  close(write_fd);

  pipe_pair(&read_fd, &write_fd, 1);
  uint64_t tree = start("/bin/sh", "sleep 30 & printf x; wait", NULL, NULL, -1,
                        write_fd, write_fd, 0);
  assert(nupp_process_kill(early >> 32, SIGKILL) == -ESRCH);
  close(write_fd);
  wait_readable((uint64_t)first, read_fd);
  char byte;
  assert(read(read_fd, &byte, 1) == 1 && byte == 'x');
  assert(nupp_process_watch((uint64_t)first, tree >> 32) == 0);
  assert(nupp_process_watch((uint64_t)first, tree >> 32) == 0);
  assert(nupp_process_watch((uint64_t)second, tree >> 32) == 0);
  assert(nupp_uv_close((uint64_t)second) == 0);
  assert(nupp_process_watch((uint64_t)second, tree >> 32) == -EBADF);
  assert(nupp_process_unwatch((uint64_t)second, tree >> 32) == -EBADF);
  assert(nupp_process_kill(tree >> 32, SIGKILL) == 0);
  int64_t event;

  do {
    event = nupp_uv_wait((uint64_t)first, SECOND);
    assert(event >= 0);
  } while (!event);

  assert(event == (int64_t)((tree >> 32) * 32 + 16));
  assert(nupp_process_reap(tree >> 32) == 512 + SIGKILL);
  assert(nupp_uv_wait((uint64_t)first, 0) == 0);
  assert(nupp_process_event((uint64_t)second) == 0);
  wait_readable((uint64_t)first, read_fd);
  assert(read(read_fd, &byte, 1) == 0);
  close(read_fd);

  /* A descendant still owns stdout when libuv reaps the leader. Release
   * the descendant through stdin only after collecting the leader's exit. */
  int input_reader, input_writer;
  pipe_pair(&input_reader, &input_writer, 0);
  pipe_pair(&read_fd, &write_fd, 1);
  uint64_t late = start(
      "/bin/sh",
      "exec 3<&0; (IFS= read -r line <&3 && printf '%s' \"$line\") & exit 9",
      NULL, NULL, input_reader, write_fd, -1, 0);
  close(input_reader);
  close(write_fd);
  assert(await_reap((uint64_t)first, late >> 32) == 265);
  assert(nupp_process_kill(late >> 32, SIGKILL) == -ESRCH);
  assert(write(input_writer, "late\n", 5) == 5);
  close(input_writer);
  wait_readable((uint64_t)first, read_fd);
  char late_output[4];
  assert(read(read_fd, late_output, sizeof(late_output)) ==
         (ssize_t)sizeof(late_output));
  assert(memcmp(late_output, "late", sizeof(late_output)) == 0);
  wait_readable((uint64_t)first, read_fd);
  assert(read(read_fd, &byte, 1) == 0);
  close(read_fd);

  pipe_pair(&read_fd, &write_fd, 0);
  uint64_t closed =
      start("/bin/sh", "exec 0<&-; exit 0", NULL, NULL, read_fd, -1, -1, 0);
  close(read_fd);
  assert(await_reap((uint64_t)first, closed >> 32) == 256);
#ifdef __APPLE__
  assert(write(write_fd, "x", 1) == -1 && errno == EPIPE);
#endif
  close(write_fd);

  uint64_t pending =
      start("/bin/sh", "sleep 30 & wait", NULL, NULL, -1, -1, -1, 0);
  assert(nupp_process_watch((uint64_t)first, pending >> 32) == 0);
  assert(nupp_uv_shutdown() == 0);
  assert(nupp_uv_shutdown() == 0);
  assert(waitpid((pid_t)(uint32_t)pending, NULL, WNOHANG) == -1 &&
         errno == ECHILD);
  assert(nupp_process_reap(pending >> 32) == -ECHILD);
  alarm(0);
  puts("libuv process contracts passed");
}
