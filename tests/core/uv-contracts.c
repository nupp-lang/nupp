/**
 * @file
 * @brief Checks native reactor operations and lifecycle contracts.
 */
#include "../../native/core-bridge/uv.c" /* NOLINT(bugprone-suspicious-include) */
#include <assert.h>
#include <stdio.h>
#include <pthread.h>
#include <sys/stat.h>
#ifdef __APPLE__
#include <sys/event.h>
#include <sys/wait.h>
#endif

static void readiness (void) {
  uv_loop_t *loop = nupp_uv_loop();
  assert(loop && nupp_uv_loop() == loop);
  int descriptors[2];
  assert(!pipe(descriptors));
  int64_t first = nupp_uv_open(-1), second = nupp_uv_open(-1);
  assert(first > 0 && second > first);
  assert(nupp_uv_valid_poller((uint64_t)first) == 1);
  service->running = 1;
  assert(nupp_uv_nowait() == -EBUSY);
  service->running = 0;
  assert(!nupp_uv_nowait());
  assert(!nupp_uv_arm((uint64_t)first, descriptors[0], 1));
  assert(!nupp_uv_arm((uint64_t)second, descriptors[0], 1));
  assert(service->watches && !service->watches->next);
  assert(!nupp_uv_wait((uint64_t)first, 0));
  assert(write(descriptors[1], "x", 1) == 1);
  assert(nupp_uv_wait((uint64_t)first, 1000000000) ==
         ((int64_t)descriptors[0] << 5 | 1));
  assert(nupp_uv_wait((uint64_t)second, 0) ==
         ((int64_t)descriptors[0] << 5 | 1));
  assert(!nupp_uv_wait((uint64_t)first, 0));
  assert(!nupp_uv_arm((uint64_t)first, descriptors[0], 1));
  assert(!nupp_uv_arm((uint64_t)second, descriptors[0], 1));
  assert(!nupp_uv_close((uint64_t)first));
  assert(nupp_uv_wait((uint64_t)first, 0) == -EBADF);
  assert(!nupp_uv_valid_poller((uint64_t)first));
  assert(fcntl(descriptors[0], F_GETFD) >= 0);
  assert(nupp_uv_wait((uint64_t)second, 1000000000) > 0);
  assert(!nupp_uv_arm((uint64_t)second, descriptors[0], 1));
  assert(nupp_uv_wait((uint64_t)second, 1000000000) > 0);
  assert(!nupp_uv_close((uint64_t)second));
  assert(nupp_uv_loop() == loop && !service->watches_count &&
         !service->subscriptions_count);
  close(descriptors[0]);
  close(descriptors[1]);
}

static void files (void) {
  assert((int64_t)nuppiosubmit(1, 0, 0, 1) == -EFAULT);
  int wake = (int)nuppiostart(1);
  assert(wake >= 0);
  assert(nuppiostart(8) == (uint64_t)wake);
  assert(fcntl(wake, F_GETFL) & O_NONBLOCK);
  assert(fcntl(wake, F_GETFD) & FD_CLOEXEC);
  char path[] = "/tmp/nupp-uv-contract-XXXXXX";
  int fd = mkstemp(path);
  assert(fd >= 0);
  char data[] = "owned";
  uint64_t ticket = nuppiosubmit(3, (uint64_t)fd, (uintptr_t)data, 5);
  assert((int64_t)ticket > 0);
  memset(data, '?', 5);
  assert(nuppiosettle(ticket) == 5);
  assert(lseek(fd, 0, SEEK_SET) == 0);
  ticket = nuppiosubmit(2, (uint64_t)fd, 0, 8);

  for (unsigned i = 0; !service->finished && i < 10000; ++i) {
    assert(!pump(UV_RUN_ONCE, 100000000, NULL));
  }

  assert(service->finished);
  assert(nuppiotake() == ticket);
  char out[8] = {0};
  assert(nuppiofinish(ticket, (uintptr_t)out, sizeof(out)) == 5);
  assert(!memcmp(out, "owned", 5));
  assert((int64_t)nuppiofinish(ticket, 0, 0) == -EINVAL);
  uint64_t first = nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path));
  uint64_t second = nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path));
  int64_t first_fd = (int64_t)nuppiosettle(first);
  assert(first_fd >= 0);

  for (unsigned attempt = 0; !service->finished && attempt < 100; ++attempt) {
    assert(!pump(UV_RUN_ONCE, 100000000, NULL));
  }

  assert(nuppiotake() == second);
  int64_t second_fd = (int64_t)nuppiofinish(second, 0, 0);
  assert(second_fd >= 0);
  close((int)first_fd);
  close((int)second_fd);

  ticket = nuppiosubmit(2, (uint64_t)fd, 0, 1);
  assert(nuppiosettle(ticket) == 0); /* EOF */
  assert((int64_t)nuppiosubmit(2, UINT64_MAX, 0, 1) == -EBADF);
  int invalid = dup(fd);
  assert(invalid >= 0);
  close(invalid);
  ticket = nuppiosubmit(2, (uint64_t)invalid, 0, 1);
  assert((int64_t)nuppiosettle(ticket) == -EBADF);
  assert(lseek(fd, 0, SEEK_SET) == 0);
  ticket = nuppiosubmit(2, (uint64_t)fd, 0, 8);
  nupp_uv_preserve_file((uint64_t)fd);
  assert(!close(fd));
  int replacement = open("/dev/null", O_RDONLY);
  assert(replacement >= 0);

  if (replacement != fd) {
    assert(dup2(replacement, fd) == fd);
    close(replacement);
  }

  assert(nuppiosettle(ticket) == 5);
  close(fd);

  ticket = nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path));
  assert(nuppiocancel(ticket) == 1);
  assert(nuppiocancel(ticket) == 0);
  assert((int64_t)nuppiosettle(ticket) == -EINVAL);
  ticket = nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path));
  assert(!pump(UV_RUN_NOWAIT, 0, NULL));
  assert(!nuppiocancel(ticket)); /* A native request still owes its callback. */
  int64_t result = (int64_t)nuppiosettle(ticket);
  assert(result == UV_ECANCELED || result >= 0);

  if (result >= 0) {
    close((int)result);
  }

  assert(!nuppiotake());
  assert(!service->jobs_count && !service->bytes);

  uint64_t tickets[MAX_JOBS];

  for (unsigned i = 0; i < MAX_JOBS; ++i) {
    tickets[i] = nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path));
    assert((int64_t)tickets[i] > 0);
  }

  assert((int64_t)nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path)) ==
         -EAGAIN);

  for (unsigned i = 0; i < MAX_JOBS; ++i) {
    assert(nuppiocancel(tickets[i]) == 1);
  }

  assert((int64_t)nuppiosubmit(2, 0, 0, MAX_BYTES + 1) == -EAGAIN);
  assert(!service->jobs_count && !service->bytes);
  unlink(path);
}

static void teardown (void) {
  int descriptors[2];
  assert(!pipe(descriptors));
  int64_t token = nupp_uv_open(descriptors[0]);
  assert(token > 0);
  assert(!nupp_uv_arm((uint64_t)token, descriptors[0], 1));
  const char path[] = "/dev/null";
  uint64_t ticket = nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path));
  assert((int64_t)ticket > 0);
  assert(!pump(UV_RUN_NOWAIT, 0, NULL));
  char withdrawn[] = "/tmp/nupp-uv-shutdown-XXXXXX";
  int temporary = mkstemp(withdrawn);
  assert(temporary >= 0);
  close(temporary);
  assert(!unlink(withdrawn));
  uint64_t pending =
      nuppiosubmit(1, O_CREAT | O_WRONLY | (UINT64_C(0600) << 32),
                   (uintptr_t)withdrawn, strlen(withdrawn));
  assert((int64_t)pending > 0);
  assert(!nupp_uv_shutdown());
  assert(access(withdrawn, F_OK) == -1 && errno == ENOENT);
  assert(!service && fcntl(descriptors[0], F_GETFD) == -1 && errno == EBADF);
  close(descriptors[1]);
  assert(!nupp_uv_shutdown());
  int64_t next = nupp_uv_open(-1);
  assert(next > token);
  assert(nupp_uv_close((uint64_t)token) == -EBADF);
  assert(!nupp_uv_close((uint64_t)next));
  uv_idle_t borrowed;
  assert(!uv_idle_init(nupp_uv_loop(), &borrowed));
  assert(nupp_uv_shutdown() == UV_EBUSY);
  uv_close((uv_handle_t *)&borrowed, NULL);
  assert(!nupp_uv_shutdown());
}

static void process_filter (void) {
#ifdef __APPLE__
  int queue = kqueue();
  assert(queue >= 0);
  int64_t token = nupp_uv_open(queue);
  assert(token > 0);
  int gate[2];
  assert(!pipe(gate));
  pid_t child = fork();
  assert(child >= 0);

  if (!child) {
    close(gate[1]);
    char byte;
    ssize_t got = read(gate[0], &byte, 1);
    _exit(got == 1 ? 7 : 8);
  }

  close(gate[0]);
  struct kevent change, event;
  EV_SET(&change, (uintptr_t)child, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT,
         0, NULL);
  assert(!kevent(queue, &change, 1, NULL, 0, NULL));
  assert(!nupp_uv_arm((uint64_t)token, queue, 1));
  assert(write(gate[1], "x", 1) == 1);
  close(gate[1]);
  assert(nupp_uv_wait((uint64_t)token, 1000000000) ==
         ((int64_t)queue << 5 | 1));
  struct timespec zero = {0, 0};
  assert(kevent(queue, NULL, 0, &event, 1, &zero) == 1);
  assert(event.ident == (uintptr_t)child && event.filter == EVFILT_PROC);
  int status;
  assert(waitpid(child, &status, 0) == child);
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 7);
  assert(!nupp_uv_close((uint64_t)token));
  assert(!nupp_uv_shutdown());
#endif
}

typedef struct ThreadOwner {
  uv_loop_t *loop;
  uint64_t token;
} ThreadOwner;

static void *thread_loop (void *argument) {
  const ThreadOwner *parent = argument;
  uv_loop_t *loop = nupp_uv_loop();
  assert(loop && loop != parent->loop);
  assert(nupp_uv_open(-1) > 0);
  assert(!nupp_uv_valid_poller(parent->token));
  assert((int64_t)nuppiostart(1) >= 0);
  const char path[] = "/dev/null";
  uint64_t ticket = nuppiosubmit(1, O_RDONLY, (uintptr_t)path, strlen(path));
  int64_t descriptor = (int64_t)nuppiosettle(ticket);
  assert(descriptor >= 0);
  close((int)descriptor);
  assert(!nupp_uv_shutdown());

  return NULL;
}

static void thread_ownership (void) {
  uv_loop_t *loop = nupp_uv_loop();
  assert(loop);
  int64_t token = nupp_uv_open(-1);
  assert(token > 0);
  ThreadOwner parent = {loop, (uint64_t)token};
  pthread_t thread;
  assert(!pthread_create(&thread, NULL, thread_loop, &parent));
  assert(!pthread_join(thread, NULL));
  assert(nupp_uv_loop() == loop && nupp_uv_valid_poller(parent.token));
  assert(!nupp_uv_shutdown());
}

static void socket_timer_broker (void) {
  int pair[2];
  assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, pair));
  int64_t owner = nupp_uv_socket_open(pair[0]);
  assert(owner > 0 && nupp_uv_socket_open(pair[0]) == -EEXIST);
  int64_t observer = nupp_uv_socket_observe((uint64_t)owner);
  assert(observer > 0);
  assert(!nupp_uv_socket_arm((uint64_t)owner, 1));
  assert(!nupp_uv_socket_arm((uint64_t)observer, 1));
  assert(service->watches_count == 1);
  assert(write(pair[1], "a", 1) == 1);
  assert(!nupp_uv_socket_take((uint64_t)observer));
  assert(!nupp_uv_nowait());
  assert(nupp_uv_socket_take((uint64_t)observer) == 1);
  assert(!nupp_uv_socket_take((uint64_t)observer));
  assert(!nupp_uv_socket_drop((uint64_t)observer));
  assert(fcntl(pair[0], F_GETFD) >= 0);
  assert(nupp_uv_socket_take((uint64_t)owner) == 1);
  assert(!nupp_uv_socket_retire((uint64_t)owner));

  /* Replace the socket at the same fd before the old close callback. */
  int fresh[2];
  assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, fresh));
  assert(dup2(fresh[0], pair[0]) == pair[0]);
  close(fresh[0]);
  int64_t next = nupp_uv_socket_open(pair[0]);
  assert(next > owner && nupp_uv_socket_observe((uint64_t)owner) == -EBADF);
  assert(!nupp_uv_socket_arm((uint64_t)next, 1));
  assert(!nupp_uv_nowait());
  assert(!nupp_uv_socket_take((uint64_t)next));

  int64_t timer = nupp_uv_timer_open();
  assert(timer > 0);
  assert(!nupp_uv_timer_replace((uint64_t)timer, 60000));
  assert(!nupp_uv_timer_replace((uint64_t)timer, 0));
  assert(!nupp_uv_timer_take((uint64_t)timer));
  assert(!nupp_uv_nowait());
  assert(nupp_uv_timer_take((uint64_t)timer) == 1);
  assert(!nupp_uv_timer_take((uint64_t)timer));
  assert(!nupp_uv_timer_replace((uint64_t)timer, 0));
  assert(!nupp_uv_timer_replace((uint64_t)timer, -1));
  assert(!nupp_uv_nowait());
  assert(!nupp_uv_timer_take((uint64_t)timer));

  assert(!nupp_uv_begin_shutdown());
  assert(nupp_uv_shutdown() == -EBUSY);
  assert(nupp_uv_timer_open() == -ECANCELED);
  assert(nupp_uv_socket_observe((uint64_t)next) == -ECANCELED);
  assert(nupp_uv_socket_arm((uint64_t)next, 1) == -ECANCELED);
  assert(nupp_uv_timer_replace((uint64_t)timer, 0) == -ECANCELED);
  assert(!nupp_uv_socket_retire((uint64_t)next));
  assert(!nupp_uv_timer_close((uint64_t)timer));
  assert(nupp_uv_timer_take((uint64_t)timer) == -EBADF);
  assert(!nupp_uv_shutdown());
  assert(fcntl(pair[0], F_GETFD) >= 0);
  close(pair[0]);
  close(pair[1]);
  close(fresh[1]);
}

void nupp_test_uv (void) {
  assert(uv_version() == UV_VERSION_HEX);
  readiness();
  files();
  teardown();
  process_filter();
  thread_ownership();
  socket_timer_broker();
  puts("libuv transport lifecycle contracts passed");
}
