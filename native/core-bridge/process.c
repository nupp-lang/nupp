/**
 * @file
 * @brief Tracks child processes and completes watches on the reactor owner
 * thread.
 *
 * Process completions on the reactor's owner thread. No callback holds guest
 * state. The child record survives both result collection and uv_close.
 */
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#elif defined(__APPLE__)
#define _DARWIN_C_SOURCE
#else
#define _POSIX_C_SOURCE 200809L
#endif
#include "process.h"
#include "reactor.h"
#include <uv.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <unistd.h>
#endif

typedef struct Wait {
  struct Wait *next;
  uint64_t poller;
} Wait;

typedef struct Child {
  struct Child *next;
  uv_process_t handle;
  Wait *waits;
  uint64_t id;
  int64_t result;
  int closed, consumed;
#ifdef _WIN32
  HANDLE job;
  uv_timer_t jobtimer;
  int jobclosed, killsignal;
#endif
} Child;

static _Thread_local Child *children;
static _Thread_local uint64_t issued;
static _Thread_local size_t child_count, wait_count;

/* shortcut: bounded native child and watch records; revisit when the runtime
 * has a larger process admission budget. Closing records count until drained.
 */
enum {
  MAX_CHILDREN = 4096,
  MAX_WAITS = 8192,
  EXITED = 16,
  EVENT_BITS = 5,
  KILL_SIGNAL = 9,
  TERM_SIGNAL = 15
};

static Child *child_at (uint64_t id) {
  if (!id) {
    return NULL;
  }

  for (Child *child = children; child; child = child->next) {
    if (child->id == id) {
      return child;
    }
  }

  return NULL;
}

static void dispose (Child *child) {
  if (!child->closed || !child->consumed || child->waits) {
    return;
  }

#ifdef _WIN32

#define JOB_EXIT_BASE UINT32_C(0xe0000000)
#define JOB_CHECK_MILLIS 50

  if (!child->jobclosed) {
    return;
  }

#endif

  Child **at = &children;

  while (*at && *at != child) {
    at = &(*at)->next;
  }

  if (!*at) {
    abort();
  }

  *at = child->next;
  child_count--;
  free(child);
}

static void closed (uv_handle_t *handle) {
  Child *child = handle->data;
  child->closed = 1;
  dispose(child);
}

#ifdef _WIN32

/** The Job Object owns descendants that outlive the root. Its completion
 * notifications can be lost, so release only after querying the kernel. */
static void jobclosed (uv_handle_t *handle) {
  Child *child = handle->data;
  child->jobclosed = 1;
  dispose(child);
}

static void closejob (Child *child) {
  CloseHandle(child->job);
  child->job = NULL;
  uv_close((uv_handle_t *)&child->jobtimer, jobclosed);
}

static int activejob (Child *child) {
  JOBOBJECT_BASIC_ACCOUNTING_INFORMATION counts;

  return QueryInformationJobObject(child->job,
                                   JobObjectBasicAccountingInformation, &counts,
                                   sizeof(counts), NULL) &&
         counts.ActiveProcesses != 0;
}

static void checkjob (uv_timer_t *timer) {
  Child *child = timer->data;

  if (!activejob(child)) {
    closejob(child);
  }
}

static int winerror (int status) {
  switch (status) {
    case UV_EACCES:
      return -EACCES;
    case UV_EBADF:
      return -EBADF;
    case UV_EINVAL:
      return -EINVAL;
    case UV_ENAMETOOLONG:
      return -ENAMETOOLONG;
    case UV_ENOENT:
      return -ENOENT;
    case UV_ENOMEM:
      return -ENOMEM;
    case UV_ENOTDIR:
      return -ENOTDIR;
    case UV_EPERM:
      return -EPERM;
    case UV_ESRCH:
      return -ESRCH;
    default:
      return -EIO;
  }
}

static int openjob (uv_loop_t *loop, Child *child) {
  HANDLE job = CreateJobObjectW(NULL, NULL);

  if (!job) {
    return winerror(uv_translate_sys_error((int)GetLastError()));
  }

  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                               sizeof(limits))) {
    int status = winerror(uv_translate_sys_error((int)GetLastError()));
    CloseHandle(job);

    return status;
  }

  int status = uv_timer_init(loop, &child->jobtimer);

  if (status < 0) {
    CloseHandle(job);

    return winerror(status);
  }

  child->job = job;
  child->jobtimer.data = child;

  return 0;
}

#endif

static void exited (uv_process_t *handle, int64_t code, int signal) {
  Child *child = handle->data;
#ifdef _WIN32

  /* A process can exit on its own between a kill and the IOCP callback. */
  signal = (uint32_t)code == JOB_EXIT_BASE + (unsigned)child->killsignal
               ? child->killsignal
               : 0;

  if (!activejob(child) ||
      uv_timer_start(&child->jobtimer, checkjob, JOB_CHECK_MILLIS,
                     JOB_CHECK_MILLIS) < 0) {
    closejob(child);
  }

#endif
  child->result = signal ? 512 + signal : 256 + (code & 255);
  uv_close((uv_handle_t *)handle, closed);
}

static int64_t start (uv_loop_t *loop, uv_process_options_t *options) {
  if (child_count == MAX_CHILDREN) {
    return -EAGAIN;
  }

  Child *child = calloc(1, sizeof(*child));

  if (!child) {
    return -ENOMEM;
  }

#ifdef _WIN32
  int status = openjob(loop, child);

  if (status < 0) {
    free(child);

    return status;
  }

  status = uv_spawn_with_job(loop, &child->handle, options, child->job);
#else
  int flags[3];

  for (int i = 0; i < 3; i++) {
    flags[i] = fcntl(options->stdio[i].data.fd, F_GETFL);
  }

  /* uv_spawn does not drive the loop. The owner publishes the identity
   * before the next loop turn can report even an immediate exit. */
  int status = uv_spawn(loop, &child->handle, options);

  /* libuv can clear O_NONBLOCK on an inherited description shared with
   * this process. Child pipe ends are already blocking. */
  for (int i = 0; i < 3; i++) {
    if (flags[i] < 0 || !(flags[i] & O_NONBLOCK)) {
      continue;
    }

    int fd = options->stdio[i].data.fd;
    int current = fcntl(fd, F_GETFL);

    if (current >= 0 && !(current & O_NONBLOCK)) {
      fcntl(fd, F_SETFL, current | O_NONBLOCK);
    }
  }

#endif

  child->handle.data = child;
  child->next = children;
  children = child;
  child_count++;

  if (status < 0) {

    /* With three inherited descriptors libuv has no stream to open after
     * spawn. A failed spawn still initializes the process handle. */
    child->consumed = 1;
#ifdef _WIN32
    closejob(child);
    status = winerror(status);
#endif
    uv_close((uv_handle_t *)&child->handle, closed);

    return status;
  }

  child->id = ++issued;

  return (int64_t)((child->id << 32) | (uint32_t)child->handle.pid);
}

#ifndef _WIN32
static const char *path_of (char **env) {
  for (; env && *env; ++env) {
    if (strncmp(*env, "PATH=", 5) == 0) {
      return *env + 5;
    }
  }

  return NULL;
}

static int64_t spawn_path (uv_loop_t *loop, uv_process_options_t *options,
                           const char *path) {
  const char *file = options->file;
  size_t namelen = strlen(file);
  size_t pathlen = path ? strlen(path) : 0;

  if (namelen > SIZE_MAX - 3 || pathlen > SIZE_MAX - namelen - 3) {
    return -ENAMETOOLONG;
  }

  size_t capacity = pathlen + namelen + 3;
  char *candidate = malloc(capacity);

  if (!candidate) {
    return -ENOMEM;
  }

  int64_t status = -ENOENT;
  int denied = 0;
  const char *at = path ? path : "";

  for (;;) {
    const char *end = strchr(at, ':');
    size_t length = end ? (size_t)(end - at) : strlen(at);

    if (length > INT_MAX) {
      status = -ENAMETOOLONG;
      break;
    }

    int written = snprintf(candidate, capacity, "%.*s/%s",
                           length ? (int)length : 1, length ? at : ".", file);

    if (written < 0 || (size_t)written >= capacity) {
      status = -ENAMETOOLONG;
      break;
    }

    options->file = candidate;
    status = start(loop, options);

    if (!path) {
      break;
    }

    if (status != -ENOENT && status != -ENOTDIR && status != -EACCES) {
      break;
    }

    if (status == -EACCES) {
      denied = 1;
    }

    if (!end) {
      status = denied ? -EACCES : -ENOENT;
      break;
    }

    at = end + 1;
  }

  free(candidate);

  return status;
}
#endif

int64_t nupp_process_spawn (const char *file, char **args, char **env,
                            const char *cwd, int64_t input, int64_t output,
                            int64_t error, uint64_t search) {
  if (!file || !args || !args[0] || input < -1 || output < -1 || error < -1 ||
      input > INT_MAX || output > INT_MAX || error > INT_MAX) {
    return -EINVAL;
  }

  if (!*file) {
    return -ENOENT;
  }

  if (issued == (uint64_t)INT32_MAX) {
    return -EOVERFLOW;
  }

  uv_loop_t *loop = nupp_uv_loop();

  if (!loop) {
    return -ENOMEM;
  }

  uv_stdio_container_t stdio[3];
  int64_t fds[] = {input, output, error};

  for (int i = 0; i < 3; i++) {
    stdio[i].flags = UV_INHERIT_FD;
    stdio[i].data.fd = fds[i] < 0 ? i : (int)fds[i];
  }

  uv_process_options_t options = {.exit_cb = exited,
                                  .file = file,
                                  .args = args,
                                  .env = env,
                                  .cwd = cwd,

  /* libuv creates a session/group before the child can execute. */
#ifdef _WIN32
                                  .flags = UV_PROCESS_WINDOWS_HIDE,
#else
                                  .flags = UV_PROCESS_DETACHED,
#endif
                                  .stdio_count = 3,
                                  .stdio = stdio};

#ifdef _WIN32

  if (search || strchr(file, '/') || strchr(file, '\\') ||
      (file[0] && file[1] == ':')) {
    return start(loop, &options);
  }

  size_t size = strlen(file) + sizeof(".\\");
  char *local = malloc(size);

  if (!local) {
    return -ENOMEM;
  }

  snprintf(local, size, ".\\%s", file);
  options.file = local;
  int64_t result = start(loop, &options);
  free(local);

  return result;
#else

  if (strchr(file, '/')) {
    return start(loop, &options);
  }

  if (!search) {
    return spawn_path(loop, &options, NULL);
  }

  /* The previous posix_spawnp looked at the parent's PATH even if exec
   * received a different environment. libuv looks at the offered env. */
  const char *parent = getenv("PATH");
  const char *given = env ? path_of(env) : parent;

  if ((!parent && !given) || (parent && given && strcmp(parent, given) == 0)) {
    return start(loop, &options);
  }

  return spawn_path(loop, &options, parent ? parent : "/usr/bin:/bin");
#endif
}

int64_t nupp_process_pipe (uint64_t read_nonblock, uint64_t write_nonblock) {
#ifdef _WIN32

  /* Guest pipe readiness needs an overlapped adapter before it can use the
   * Windows reactor. Returning a CRT fd here would silently block the owner. */
  if (read_nonblock || write_nonblock) {
    return -ENOSYS;
  }

#endif
  int fds[2];
  int status = uv_pipe(fds, read_nonblock ? UV_NONBLOCK_PIPE : 0,
                       write_nonblock ? UV_NONBLOCK_PIPE : 0);

  if (status < 0) {
#ifdef _WIN32

    return winerror(status);
#else

    return status;
#endif
  }

#ifdef F_SETNOSIGPIPE

  /* A closed child's stdin is an EPIPE on the parent's retained end. The
   * blocking end inherited by a child keeps its usual SIGPIPE behavior. */
  if (write_nonblock && fcntl(fds[1], F_SETNOSIGPIPE, 1) < 0) {
    status = -errno;
    close(fds[0]);
    close(fds[1]);

    return status;
  }

#endif

  return (int64_t)(((uint64_t)fds[1] << 32) | (uint32_t)fds[0]);
}

int64_t nupp_process_watch (uint64_t poller, uint64_t id) {
  if (!nupp_uv_valid_poller(poller)) {
    return -EBADF;
  }

  Child *child = child_at(id);

  if (!child || child->result) {
    return -ESRCH;
  }

  for (Wait *wait = child->waits; wait; wait = wait->next) {
    if (wait->poller == poller) {
      return 0;
    }
  }

  if (wait_count == MAX_WAITS) {
    return -EAGAIN;
  }

  Wait *wait = malloc(sizeof(*wait));

  if (!wait) {
    return -ENOMEM;
  }

  *wait = (Wait){.next = child->waits, .poller = poller};
  child->waits = wait;
  wait_count++;

  return 0;
}

static void unwatch (Child *child, uint64_t poller) {
  Wait **at = &child->waits;

  while (*at && (*at)->poller != poller) {
    at = &(*at)->next;
  }

  if (!*at) {
    return;
  }

  Wait *wait = *at;
  *at = wait->next;
  free(wait);
  wait_count--;
  dispose(child);
}

int64_t nupp_process_unwatch (uint64_t poller, uint64_t id) {
  if (!nupp_uv_valid_poller(poller)) {
    return -EBADF;
  }

  Child *child = child_at(id);

  if (child) {
    unwatch(child, poller);
  }

  return 0;
}

int64_t nupp_process_event (uint64_t poller) {
  for (Child *child = children; child; child = child->next) {
    if (!child->result) {
      continue;
    }

    for (Wait *wait = child->waits; wait; wait = wait->next) {
      if (wait->poller != poller) {
        continue;
      }

      int64_t event = (int64_t)((child->id << EVENT_BITS) | EXITED);
      unwatch(child, poller);

      return event;
    }
  }

  return 0;
}

void nupp_process_forget_poller (uint64_t poller) {
  for (Child *child = children, *next; child; child = next) {
    next = child->next;
    unwatch(child, poller);
  }
}

int64_t nupp_process_reap (uint64_t id) {
  Child *child = child_at(id);

  if (!child || child->consumed) {
    return -ECHILD;
  }

  int64_t result = child->result;

  if (result) {
    child->consumed = 1;
    dispose(child);
  }

  return result;
}

int64_t nupp_process_kill (uint64_t id, uint64_t signal) {
  Child *child = child_at(id);

  if (!child || child->result) {
    return -ESRCH;
  }

  if (signal > INT_MAX) {
    return -EINVAL;
  }

#ifdef _WIN32

  if (signal == 0) {
    return 0;
  }

  if (signal != KILL_SIGNAL && signal != TERM_SIGNAL) {
    return -EINVAL;
  }

  if (child->killsignal) {
    return 0;
  }

  if (!TerminateJobObject(child->job, JOB_EXIT_BASE + (unsigned)signal)) {
    return winerror(uv_translate_sys_error((int)GetLastError()));
  }

  child->killsignal = (int)signal;

  return 0;
#else

  return kill(-child->handle.pid, (int)signal) ? -errno : 0;
#endif
}

int nupp_process_shutdown (void) {
  for (Child *child = children, *next; child; child = next) {
    next = child->next;

    if (child->id && !child->result) {
      int64_t status = nupp_process_kill(child->id, KILL_SIGNAL);

      if (status < 0 && status != -ESRCH) {
        return (int)status;
      }
    }

#ifdef _WIN32
    else if (child->job &&
             !TerminateJobObject(child->job, JOB_EXIT_BASE + KILL_SIGNAL)) {
      return winerror(uv_translate_sys_error((int)GetLastError()));
    }
#endif

    while (child->waits) {
      Wait *wait = child->waits;
      child->waits = wait->next;
      free(wait);
      wait_count--;
    }

    child->consumed = 1;
    dispose(child);
  }

  return 0;
}

int nupp_process_pending (void) {
  return children != NULL;
}
