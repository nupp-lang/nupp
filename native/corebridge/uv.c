/**
 * @file
 * @brief libuv transport for native work and readiness notifications.
 *
 * libuv callbacks cannot enter managed Nupp. This transport holds only copied
 * bytes, native requests and opaque subscriptions; Nupp owns all task policy.
 * All calls and callbacks run on the loop's owning thread. libuv alone runs
 * filesystem work on its pool; no worker sees a Nupp value or heap pointer.
 */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "transport.h"
#include "reactor.h"
#include "filetickets.h"
#include "transport.h"
#ifdef NUPP_CORE_NET
#include "netbridge.h"
#endif
#if !defined(_WIN32) || defined(NUPP_WIN64_PROCESS)
#include "process.h"
#endif
#include <uv.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) && defined(NUPP_WIN64_PROCESS)
#include "winpipe.h"
#endif

#ifdef _WIN32
#include <io.h>
#else
#include <sys/socket.h>
#include <unistd.h>
#endif

typedef struct Poller Poller;
typedef struct Watch Watch;
typedef struct Subscription Subscription;
typedef struct Timer Timer;
typedef struct Job Job;

typedef struct {
  int fd;

#ifdef _WIN32
  int is_socket;
  uv_os_sock_t socket;
#endif
} PollTarget;

struct Watch {
  uv_poll_t handle;
  Watch *next;
  PollTarget target;
  int close_fd;
};

struct Subscription {
  Watch *watch;
  Subscription *next;
  int interest, ready;
};

struct Poller {
  uint64_t token, owner;
  int process_fd;
  PollTarget target;
  Subscription *subscriptions;
  Poller *next;
#ifdef _WIN32
  int file_completion;
#endif
};

struct Timer {
  uv_timer_t handle;
  uint64_t token;
  int ready;
  Timer *next;
};

struct Job {
  FileTicket ticket; /* Initial member so ticket links can recover the job. */
  uv_fs_t request;
  uv_buf_t buffer;
  uint64_t kind, word;
  unsigned char *bytes;
  int descriptor, descriptor_error;
};

typedef struct Service {
  uv_loop_t loop;
  uv_timer_t timer;
  nupp_uv_owner_step_fn owner_step;
  nupp_uv_owner_ready_fn owner_ready;
  void *owner_ctx;
  Poller *pollers;
  Timer *timers;
  Watch *watches;
  FileTickets files;
  size_t active_limit, watches_count, subscriptions_count;
  size_t adapter_count, closing_timers, closing_watches;
  int wake[2], running, shutting_down;
} Service;

static _Thread_local Service *service;

/* Identities never alias across owner threads or loop lifetimes. */
static _Atomic uint64_t issued;

static uint64_t issue (void) {
  uint64_t current = atomic_load_explicit(&issued, memory_order_relaxed);

  while (current < INT64_MAX) {
    if (atomic_compare_exchange_weak_explicit(&issued, &current, current + 1,
                                              memory_order_relaxed,
                                              memory_order_relaxed)) {
      return current + 1;
    }
  }

  return 0;
}

/* shortcut: 256 requests, 128 MiB copied bytes, 4096 watches/8192
 * subscriptions; expand the Nupp admission budget before supporting workloads
 * above these caps. */
enum {
  MAX_JOBS = 256,
  MAX_BYTES = 128 * 1024 * 1024,
  MAX_WATCHES = 4096,
  MAX_SUBSCRIPTIONS = 8192
};

static uint64_t failed (int error) {
  return (uint64_t)-(int64_t)error;
}

#ifdef _WIN32
#ifdef _MSC_VER
static void __cdecl ignore_invalid_file_parameter (const wchar_t *expression,
                                                   const wchar_t *function,
                                                   const wchar_t *file,
                                                   unsigned int line,
                                                   uintptr_t reserved) {
  (void)expression;
  (void)function;
  (void)file;
  (void)line;
  (void)reserved;
}
#endif

int nupp_uv_valid_file (int64_t descriptor) {
  if (descriptor < 0 || descriptor > INT_MAX) {
    return 0;
  }

  /* MSVC's release CRT can terminate on a recycled fd. Install a
   * thread-local handler only for the non-owning descriptor lookup. */
#ifdef _MSC_VER
  _invalid_parameter_handler previous =
      _set_thread_local_invalid_parameter_handler(
          ignore_invalid_file_parameter);
#endif
  uintptr_t handle = (uintptr_t)uv_get_osfhandle((int)descriptor);
#ifdef _MSC_VER
  _set_thread_local_invalid_parameter_handler(previous);
#endif

  return handle && handle < UINTPTR_MAX - 1;
}

#endif

static void close_descriptor (int fd) {
#ifdef _WIN32
  _close(fd);
#else
  close(fd);
#endif
}

static PollTarget descriptor (int fd) {
  return (PollTarget){.fd = fd};
}

static int same_target (PollTarget left, PollTarget right) {
#ifdef _WIN32

  if (left.is_socket != right.is_socket) {
    return 0;
  }

  if (left.is_socket) {
    return left.socket == right.socket;
  }

#endif

  return left.fd == right.fd;
}

static int init_poll (uv_loop_t *loop, uv_poll_t *handle, PollTarget target) {
#ifdef _WIN32

  /* uv_poll_init on Windows would interpret a CRT descriptor as a SOCKET. */
  return target.is_socket ? uv_poll_init_socket(loop, handle, target.socket)
                          : -ENOSYS;
#else

  return uv_poll_init(loop, handle, target.fd);
#endif
}

static void timeout (uv_timer_t *timer) {
  (void)timer;
}

static int ensure (void) {
  if (service) {
    return 0;
  }

  Service *s = calloc(1, sizeof(*s));

  if (!s) {
    return -ENOMEM;
  }

  s->wake[0] = s->wake[1] = -1;
  int status = uv_loop_init(&s->loop);

  if (status) {
    free(s);

    return status;
  }

  status = uv_timer_init(&s->loop, &s->timer);

  if (status) {
    uv_loop_close(&s->loop);
    free(s);

    return status;
  }

  fileticketsinit(&s->files);
  service = s;

  return 0;
}

static int admit (void) {
  int status = ensure();

  if (status) {
    return status;
  }

  return service->shutting_down ? -ECANCELED : 0;
}

/* Native process/socket adapters borrow this loop on its owner thread. They
 * must retire their requests/handles before the runtime's final shutdown. */
struct uv_loop_s *nupp_uv_loop (void) {
  return admit() ? NULL : &service->loop;
}

static Poller *poller (uint64_t token) {
  for (Poller *p = service ? service->pollers : NULL; p; p = p->next) {
    if (p->token == token) {
      return p;
    }
  }

  return NULL;
}

int nupp_uv_valid_poller (uint64_t token) {
  Poller *p = poller(token);

  return p && !p->owner;
}

static void closed (uv_handle_t *handle) {
  Watch *w = handle->data;

  if (w->close_fd >= 0) {
    close_descriptor(w->close_fd);
  }

  service->watches_count--;
  service->closing_watches--;
  free(w);
}

static int refresh (Watch *w);

static void watch_error (Watch *w) {
  for (Poller *p = service->pollers; p; p = p->next) {
    for (Subscription *s = p->subscriptions; s; s = s->next) {
      if (s->watch == w && s->interest) {
        s->ready |= 8;
        s->interest = 0;
      }
    }
  }

  uv_poll_stop(&w->handle);
}

static void ready (uv_poll_t *handle, int status, int events) {
  Watch *w = handle->data;
  int bits = status < 0 ? 8
                        : ((events & UV_READABLE) ? 1 : 0) |
                              ((events & UV_WRITABLE) ? 2 : 0) |
                              ((events & UV_DISCONNECT) ? 4 : 0);

  for (Poller *p = service->pollers; p; p = p->next) {
    for (Subscription *s = p->subscriptions; s; s = s->next) {
      if (s->watch != w || !s->interest) {
        continue;
      }

      int got = bits & (s->interest | 4 | 8);

      if (got) {
        s->ready |= got;
        s->interest = 0;
      }
    }
  }

  if (refresh(w) < 0) {
    watch_error(w);
  }
}

static int refresh (Watch *w) {
  int interest = 0;

  for (Poller *p = service->pollers; p; p = p->next) {
    for (Subscription *s = p->subscriptions; s; s = s->next) {
      if (s->watch == w) {
        interest |= s->interest;
      }
    }
  }

  int events =
      ((interest & 1) ? UV_READABLE : 0) | ((interest & 2) ? UV_WRITABLE : 0);

  return events ? uv_poll_start(&w->handle, events, ready)
                : uv_poll_stop(&w->handle);
}

static int64_t open_poller (int process_fd, const PollTarget *target,
                            uint64_t owner) {
  int status = admit();

  if (status) {
    return status;
  }

  if (target &&
      service->adapter_count + service->closing_timers >= MAX_SUBSCRIPTIONS) {
    return -EAGAIN;
  }

  uint64_t token = issue();

  if (!token) {
    return -EOVERFLOW;
  }

  Poller *p = calloc(1, sizeof(*p));

  if (!p) {
    return -ENOMEM;
  }

  p->token = token;
  p->process_fd = process_fd;

  if (target) {
    p->target = *target;
    p->owner = owner ? owner : token;
    service->adapter_count++;
  }

  p->next = service->pollers;
  service->pollers = p;

  return (int64_t)p->token;
}

static int subscribe (Poller *p, PollTarget target, Subscription **out) {
  if (service->subscriptions_count == MAX_SUBSCRIPTIONS) {
    return -EAGAIN;
  }

  Subscription *s = calloc(1, sizeof(*s));

  if (!s) {
    return -ENOMEM;
  }

  Watch *w = service->watches;

  while (w && !same_target(w->target, target)) {
    w = w->next;
  }

  if (!w) {
    if (service->watches_count == MAX_WATCHES) {
      free(s);

      return -EAGAIN;
    }

    w = calloc(1, sizeof(*w));

    if (!w) {
      free(s);

      return -ENOMEM;
    }

    int status = init_poll(&service->loop, &w->handle, target);

    if (status) {
      free(w);
      free(s);

      return status;
    }

    w->handle.data = w;
    w->target = target;
    w->close_fd = -1;
    w->next = service->watches;
    service->watches = w;
    service->watches_count++;
  }

  s->watch = w;
  s->next = p->subscriptions;
  p->subscriptions = s;
  service->subscriptions_count++;
  *out = s;

  return 0;
}

static int disarm (Subscription **at) {
  Subscription *s = *at;

  if (!s) {
    return 0;
  }

  Watch *w = s->watch;
  *at = s->next;
  free(s);
  service->subscriptions_count--;
  int used = 0;

  for (Poller *other = service->pollers; other; other = other->next) {
    for (Subscription *sub = other->subscriptions; sub; sub = sub->next) {
      if (sub->watch == w) {
        used = 1;
      }
    }
  }

  if (used) {
    int status = refresh(w);

    if (status < 0) {
      watch_error(w);
    }

    return status;
  }

  Watch **wat = &service->watches;

  while (*wat && *wat != w) {
    wat = &(*wat)->next;
  }

  if (!*wat) {
    return -EIO;
  }

  *wat = w->next;
  uv_poll_stop(&w->handle);
  service->closing_watches++;
  uv_close((uv_handle_t *)&w->handle, closed);

  return 0;
}

static int arm (Poller *p, PollTarget target, int interest) {
  if (interest && service->shutting_down) {
    return -ECANCELED;
  }

  Subscription **at = &p->subscriptions;

  while (*at && !same_target((*at)->watch->target, target)) {
    at = &(*at)->next;
  }

  Subscription *s = *at;

  if (!interest) {
    return disarm(at);
  }

  if (!s) {
    int status = subscribe(p, target, &s);

    if (status) {
      return status;
    }

    at = &p->subscriptions;
  }

  s->ready = 0;
  s->interest = (int)interest;
  int status = refresh(s->watch);

  if (status) {
    disarm(at);
  }

  return status;
}

int64_t nupp_uv_open (int64_t process_fd) {
  if (process_fd < -1 || process_fd > INT_MAX) {
    return -EINVAL;
  }

#ifdef _WIN32

  if (process_fd >= 0) {
    return -ENOSYS;
  }

#endif

  return open_poller((int)process_fd, NULL, 0);
}

int64_t nupp_uv_processfd (uint64_t token) {
  Poller *p = poller(token);

  return p && !p->owner ? p->process_fd : -EBADF;
}

int64_t nupp_uv_arm (uint64_t token, int64_t fd, uint64_t interest) {
  Poller *p = poller(token);

  if (!p || p->owner) {
    return -EBADF;
  }

#ifdef _WIN32

  if (fd == NUPP_UV_FILE_COMPLETION && service->active_limit) {
    if (interest > 1) {
      return -EINVAL;
    }

    if (interest && service->shutting_down) {
      return -ECANCELED;
    }

    p->file_completion = (int)interest;

    return 0;
  }

#endif

  if (fd < 0 || fd > INT_MAX || interest > 3) {
    return -EINVAL;
  }

#if defined(_WIN32) && defined(NUPP_WIN64_PROCESS)

  if (nuppwinpipekey(fd)) {
    return interest && service->shutting_down
               ? -ECANCELED
               : nuppwinpipearm(token, fd, (int)interest);
  }

#endif

  return arm(p, descriptor((int)fd), (int)interest);
}

static int adapter_available (PollTarget target) {
  for (Poller *p = service ? service->pollers : NULL; p; p = p->next) {
    if (p->owner == p->token && same_target(p->target, target)) {
      return -EEXIST;
    }
  }

  return 0;
}

int64_t nupp_uv_socket_open (uintptr_t socket) {
#ifdef _WIN32
  _Static_assert(sizeof(uv_os_sock_t) == sizeof(uintptr_t),
                 "the broker must retain every bit of a Winsock SOCKET");

  if (socket == (uintptr_t)INVALID_SOCKET) {
    return -EBADF;
  }

  PollTarget target = {.is_socket = 1, .socket = (uv_os_sock_t)socket};
#else

  if (socket > INT_MAX) {
    return -EBADF;
  }

  PollTarget target = descriptor((int)socket);
#endif

  int status = adapter_available(target);

  if (status) {
    return status;
  }

  int type;

#ifdef _WIN32
  int size = sizeof(type);

  if (getsockopt(target.socket, SOL_SOCKET, SO_TYPE, (char *)&type, &size)) {
    return uv_translate_sys_error(WSAGetLastError());
  }

#else
  socklen_t size = sizeof(type);

  if (getsockopt(target.fd, SOL_SOCKET, SO_TYPE, &type, &size)) {
    return -errno;
  }

#endif

  return open_poller(-1, &target, 0);
}

int64_t nupp_uv_socket_observe (uint64_t owner) {
  Poller *p = poller(owner);

  if (!p || p->owner != owner) {
    return -EBADF;
  }

  return open_poller(-1, &p->target, owner);
}

int nupp_uv_socket_arm (uint64_t token, uint64_t interest) {
  Poller *p = poller(token);

  if (!p || !p->owner) {
    return -EBADF;
  }

  if (interest > 3) {
    return -EINVAL;
  }

  return arm(p, p->target, (int)interest);
}

int nupp_uv_socket_ready (uint64_t token) {
  Poller *p = poller(token);

  if (!p || !p->owner) {
    return -EBADF;
  }

  const Subscription *s = p->subscriptions;

  return s ? s->ready : 0;
}

int nupp_uv_socket_take (uint64_t token) {
  Poller *p = poller(token);

  if (!p || !p->owner) {
    return -EBADF;
  }

  Subscription *s = p->subscriptions;

  if (!s) {
    return 0;
  }

  int bits = s->ready;
  s->ready = 0;

  return bits;
}

static void drop_socket (Poller **at) {
  Poller *p = *at;
  arm(p, p->target, 0);
  *at = p->next;
  free(p);
  service->adapter_count--;
}

int64_t nupp_uv_descriptor_open (int64_t fd) {
  if (fd < 0 || fd > INT_MAX) {
    return -EBADF;
  }

#ifdef _WIN32

  return -ENOSYS;
#else
  PollTarget target = descriptor((int)fd);
  int status = adapter_available(target);

  if (status) {
    return status;
  }

  if (fcntl((int)fd, F_GETFD) < 0) {
    return -errno;
  }

  int64_t token = open_poller(-1, &target, 0);

  if (token < 0) {
    return token;
  }

  /* open_poller prepends the owner. Validate without arming any interest. */
  Subscription *s;
  status = subscribe(service->pollers, target, &s);

  if (status) {
    drop_socket(&service->pollers);

    return status;
  }

  return token;
#endif
}

int nupp_uv_socket_drop (uint64_t observer) {
  if (!service) {
    return -EBADF;
  }

  Poller **at = &service->pollers;

  while (*at && (*at)->token != observer) {
    at = &(*at)->next;
  }

  if (!*at || !(*at)->owner || (*at)->owner == observer) {
    return -EBADF;
  }

  drop_socket(at);

  return 0;
}

int nupp_uv_socket_retire (uint64_t owner) {
  Poller *p = poller(owner);

  if (!p || p->owner != owner) {
    return -EBADF;
  }

  PollTarget target = p->target;
  Poller **at = &service->pollers;

  while (*at) {
    if ((*at)->owner == owner) {
      drop_socket(at);
    }
    else {

      /* Withdraw any generic native subscription before the actual close. */
      if (!(*at)->owner) {
        arm(*at, target, 0);
      }

      at = &(*at)->next;
    }
  }

  return 0;
}

static Timer **timer_at (uint64_t token) {
  Timer **at = &service->timers;

  while (*at && (*at)->token != token) {
    at = &(*at)->next;
  }

  return at;
}

int64_t nupp_uv_timer_open (void) {
  int status = admit();

  if (status) {
    return status;
  }

  if (service->adapter_count + service->closing_timers >= MAX_SUBSCRIPTIONS) {
    return -EAGAIN;
  }

  uint64_t token = issue();

  if (!token) {
    return -EOVERFLOW;
  }

  Timer *timer = calloc(1, sizeof(*timer));

  if (!timer) {
    return -ENOMEM;
  }

  status = uv_timer_init(&service->loop, &timer->handle);

  if (status) {
    free(timer);

    return status;
  }

  timer->token = token;
  timer->handle.data = timer;
  timer->next = service->timers;
  service->timers = timer;
  service->adapter_count++;

  return (int64_t)token;
}

static void timer_ready (uv_timer_t *handle) {
  Timer *timer = handle->data;
  timer->ready = 1;
}

int nupp_uv_timer_replace (uint64_t token, int64_t delay_ms) {
  Timer *timer = service ? *timer_at(token) : NULL;

  if (!timer) {
    return -EBADF;
  }

  if (delay_ms < -1) {
    return -EINVAL;
  }

  if (delay_ms >= 0 && service->shutting_down) {
    return -ECANCELED;
  }

  timer->ready = 0;

  if (delay_ms == -1) {
    return uv_timer_stop(&timer->handle);
  }

  uv_update_time(&service->loop);

  return uv_timer_start(&timer->handle, timer_ready, (uint64_t)delay_ms, 0);
}

int nupp_uv_timer_ready (uint64_t token) {
  const Timer *timer = service ? *timer_at(token) : NULL;

  return timer ? timer->ready : -EBADF;
}

int nupp_uv_timer_take (uint64_t token) {
  Timer *timer = service ? *timer_at(token) : NULL;

  if (!timer) {
    return -EBADF;
  }

  int ready_now = timer->ready;
  timer->ready = 0;

  return ready_now;
}

static void timer_closed (uv_handle_t *handle) {
  service->closing_timers--;
  free(handle->data);
}

int nupp_uv_timer_close (uint64_t token) {
  if (!service) {
    return -EBADF;
  }

  Timer **at = timer_at(token);
  Timer *timer = *at;

  if (!timer) {
    return -EBADF;
  }

  *at = timer->next;
  service->adapter_count--;
  service->closing_timers++;
  uv_close((uv_handle_t *)&timer->handle, timer_closed);

  return 0;
}

static void dispose (Job *job) {
  if (job->descriptor >= 0) {
    close_descriptor(job->descriptor);
  }

  free(job->bytes);
  free(job);
}

static void finish_job (Job *job, int64_t result) {
  /* The ticket owns its duplicate and bytes until disposal at collection. */
  fileticketcomplete(&service->files, &job->ticket, result);

#ifndef _WIN32
  const unsigned char byte = 1;

  /* A full pipe already announces queued results; notifications coalesce. */
  while (write(service->wake[1], &byte, 1) < 0 && errno == EINTR) {
  }

#endif
}

static void completed (uv_fs_t *request) {
  Job *job = request->data;
  int64_t result = request->result;
  uv_fs_req_cleanup(request);

#ifdef _WIN32

  /* Libuv's negative Windows errors use a separate numbering scheme from
   * the CRT errors the guest's file layer reports. */
  if (result < 0) {
    switch (result) {
      case UV_EACCES:
        result = -EACCES;
        break;
      case UV_EAGAIN:
        result = -EAGAIN;
        break;
      case UV_EBADF:
        result = -EBADF;
        break;
      case UV_EBUSY:
        result = -EBUSY;
        break;
      case UV_ECANCELED:
        result = -ECANCELED;
        break;
      case UV_EEXIST:
        result = -EEXIST;
        break;
      case UV_EINVAL:
        result = -EINVAL;
        break;
      case UV_EISDIR:
        result = -EISDIR;
        break;
      case UV_EMFILE:
        result = -EMFILE;
        break;
      case UV_ENAMETOOLONG:
        result = -ENAMETOOLONG;
        break;
      case UV_ENOENT:
        result = -ENOENT;
        break;
      case UV_ENOMEM:
        result = -ENOMEM;
        break;
      case UV_ENOSPC:
        result = -ENOSPC;
        break;
      case UV_ENOTDIR:
        result = -ENOTDIR;
        break;
      case UV_EPERM:
        result = -EPERM;
        break;
      case UV_EPIPE:
        result = -EPIPE;
        break;
      default:
        result = -EIO;
        break;
    }
  }

#endif
  finish_job(job, result);
}

static void hold_descriptor (Job *job) {
  if (job->kind == 1 || job->descriptor >= 0 || job->descriptor_error) {
    return;
  }

#ifdef _WIN32

  if (!nupp_uv_valid_file((int64_t)job->word)) {
    job->descriptor_error = EBADF;

    return;
  }

  job->descriptor = _dup((int)job->word);

  if (job->descriptor < 0) {
    job->descriptor_error = errno;
  }

#else

  do {
    job->descriptor = fcntl((int)job->word, F_DUPFD_CLOEXEC, 0);
  } while (job->descriptor < 0 && errno == EINTR);

  if (job->descriptor < 0) {
    job->descriptor_error = errno;
  }

#endif
}

void nupp_uv_preserve_file (uint64_t descriptor) {

  /* Usually capture at dispatch. Closing early must capture before the
   * descriptor can be recycled, even if the job hasn't reached libuv. */
  for (FileTicket *ticket = service ? service->files.jobs : NULL; ticket;
       ticket = ticket->next) {
    Job *job = (Job *)ticket;

    if (!ticket->submitted && job->word == descriptor) {
      hold_descriptor(job);
    }
  }
}

#ifdef _WIN32

/* The pool import transports the flags already issued by hostfiles.nupp.
 * Translate its Darwin values before passing them to the Windows libuv ABI. */
static int file_open_flags (uint32_t flags) {
  enum {
    ACCESS = 0x3,
    APPEND = 0x8,
    CREATE = 0x200,
    TRUNCATE = 0x400,
    EXCLUSIVE = 0x800,
    CLOSE_ON_EXEC = 0x1000000
  };

  if ((flags &
       ~(ACCESS | APPEND | CREATE | TRUNCATE | EXCLUSIVE | CLOSE_ON_EXEC)) ||
      (flags & ACCESS) == ACCESS) {
    return -ENOTSUP;
  }

  static const int access[] = {UV_FS_O_RDONLY, UV_FS_O_WRONLY, UV_FS_O_RDWR};
  int result = access[flags & ACCESS] | _O_BINARY;

  if (flags & APPEND) {
    result |= UV_FS_O_APPEND;
  }

  if (flags & CREATE) {
    result |= UV_FS_O_CREAT;
  }

  if (flags & TRUNCATE) {
    result |= UV_FS_O_TRUNC;
  }

  if (flags & EXCLUSIVE) {
    result |= UV_FS_O_EXCL;
  }

  return result;
}

#endif

static void submit_jobs (void) {
  for (FileTicket *ticket = service->files.jobs; ticket;
       ticket = ticket->next) {
    Job *job = (Job *)ticket;

    if (service->files.active == service->active_limit) {
      break;
    }

    if (ticket->submitted) {
      continue;
    }

    hold_descriptor(job);
    fileticketsubmit(&service->files, ticket);
    job->request.data = job;
    int status;

    if (job->descriptor_error) {
      finish_job(job, -job->descriptor_error);
      continue;
    }

    if (job->kind == 1) {
      int flags = (int)(uint32_t)job->word;

#ifdef _WIN32
      flags = file_open_flags((uint32_t)job->word);

      if (flags < 0) {
        finish_job(job, flags);
        continue;
      }

#endif

      status = uv_fs_open(&service->loop, &job->request, (char *)job->bytes,
                          flags, (int)(job->word >> 32), completed);
    }
    else if (job->kind == 2) {
      status = uv_fs_read(&service->loop, &job->request, job->descriptor,
                          &job->buffer, 1, -1, completed);
    }
    else {
      status = uv_fs_write(&service->loop, &job->request, job->descriptor,
                           &job->buffer, 1, -1, completed);
    }

    if (status < 0) {
      job->request.result = status;
      completed(&job->request);
    }
  }
}

int nupp_uv_set_owner_driver (nupp_uv_owner_step_fn step,
                              nupp_uv_owner_ready_fn ready, void *ctx) {
  if ((step == NULL) != (ready == NULL) || (!step && ctx)) {
    return -EINVAL;
  }

  if (service && service->running) {
    return -EBUSY;
  }

  if (step) {
    int status = admit();

    if (status) {
      return status;
    }

    if (service->owner_step) {
      return -EBUSY;
    }
  }

  if (service) {
    service->owner_step = step;
    service->owner_ready = ready;
    service->owner_ctx = ctx;
  }

  return 0;
}

int nupp_uv_owner_active (void) {
  if (!service || service->running) {
    return 0;
  }

  if (service->closing_watches || service->closing_timers) {
    return 1;
  }

  if (!service->owner_step || service->shutting_down) {
    return 0;
  }

  for (const Timer *timer = service->timers; timer; timer = timer->next) {
    if (timer->ready || uv_is_active((const uv_handle_t *)&timer->handle)) {
      return 1;
    }
  }

  for (const Poller *p = service->pollers; p; p = p->next) {
    const Subscription *s = p->subscriptions;

    if (p->owner == p->token && s && (s->interest || s->ready)) {
      return 1;
    }
  }

  return 0;
}

static int poller_ready (Poller *poller) {
#if defined(_WIN32) && defined(NUPP_WIN64_PROCESS)

  if (nuppwinpipeevent(poller->token, 0)) {
    return 1;
  }

#endif

#ifdef _WIN32

  if (poller->file_completion && service->files.finished) {
    return 1;
  }

#endif

  for (Subscription *s = poller->subscriptions; s; s = s->next) {
    if (s->ready) {
      return 1;
    }
  }

  return 0;
}

static int pump (uv_run_mode mode, uint64_t nanos, Poller *owner_wait) {
  if (service->running) {
    return -EBUSY;
  }

  service->running = 1;

  enum { OWNER_BUDGET = 32 };

  uint64_t started = owner_wait ? uv_hrtime() : 0;
  int drive = service->owner_step && !service->shutting_down;

  if (drive) {
    service->owner_step(service->owner_ctx, OWNER_BUDGET);
  }

  if (owner_wait && mode == UV_RUN_ONCE) {
    uint32_t ready = drive ? service->owner_ready(service->owner_ctx) : 0;

    if (poller_ready(owner_wait) ||
        (ready & (NUPP_UV_OWNER_NATIVE_READY | NUPP_UV_OWNER_MANAGED_READY))) {
      mode = UV_RUN_NOWAIT;
    }
  }

  submit_jobs();

  if (owner_wait && mode == UV_RUN_ONCE && nanos != UINT64_MAX) {
    uint64_t elapsed = uv_hrtime() - started;

    if (elapsed >= nanos) {
      mode = UV_RUN_NOWAIT;
    }
    else {
      nanos -= elapsed;
    }
  }

  int has_deadline = !uv_is_closing((uv_handle_t *)&service->timer);

  if (has_deadline && mode == UV_RUN_ONCE && nanos != UINT64_MAX) {
    if (owner_wait) {
      uv_update_time(&service->loop);
    }

    uint64_t millis = nanos / 1000000 + (nanos % 1000000 != 0);
    uv_timer_start(&service->timer, timeout, millis, 0);
  }

  uv_run(&service->loop, mode);

#if defined(NUPP_CORE_NET) && defined(NUPP_CORE_TLS)

  if (!service->shutting_down) {
    nuppnetadvance();
  }

#endif

#ifdef NUPP_CORE_NET
  nuppnetsweep();
#endif

#if defined(_WIN32) && defined(NUPP_WIN64_PROCESS)
  nuppwinpipesweep();
#endif

  if (has_deadline) {
    uv_timer_stop(&service->timer);
  }

  if (drive) {
    service->owner_step(service->owner_ctx, OWNER_BUDGET);
  }

  service->running = 0;

  return 0;
}

int nupp_uv_nowait (void) {
  return service ? pump(UV_RUN_NOWAIT, 0, NULL) : 0;
}

static int64_t event (Poller *p) {
#if defined(_WIN32) && defined(NUPP_WIN64_PROCESS)
  int64_t pipe = nuppwinpipeevent(p->token, 1);

  if (pipe) {
    return pipe;
  }

#endif

#ifdef _WIN32

  if (p->file_completion && service->files.finished) {
    p->file_completion = 0;

    return (NUPP_UV_FILE_COMPLETION << 5) | 1;
  }

#endif

#if !defined(_WIN32) || defined(NUPP_WIN64_PROCESS)
  int64_t child = nupp_process_event(p->token);

  if (child) {
    return child;
  }

#endif

  for (Subscription *s = p->subscriptions; s; s = s->next) {
    if (!s->ready) {
      continue;
    }

    int bits = s->ready;
    s->ready = 0;

    return ((int64_t)s->watch->target.fd << 5) | bits;
  }

  return 0;
}

int64_t nupp_uv_wait (uint64_t token, uint64_t nanos) {
  Poller *p = poller(token);

  if (!p || p->owner) {
    return -EBADF;
  }

  int64_t found = event(p);

  if (found) {
    return found;
  }

  int status = pump(nanos ? UV_RUN_ONCE : UV_RUN_NOWAIT, nanos, NULL);

  return status ? status : event(p);
}

int64_t nupp_uv_wait_owner (uint64_t token, uint64_t nanos) {
  Poller *p = poller(token);

  if (!p || p->owner) {
    return -EBADF;
  }

  int status = pump(nanos ? UV_RUN_ONCE : UV_RUN_NOWAIT, nanos, p);

  return status ? status : event(p);
}

int64_t nupp_uv_close (uint64_t token) {
  if (!service) {
    return -EBADF;
  }

  if (service->running) {
    return -EBUSY;
  }

  Poller **at = &service->pollers;

  while (*at && (*at)->token != token) {
    at = &(*at)->next;
  }

  Poller *p = *at;

  if (!p || p->owner) {
    return -EBADF;
  }

  Watch *owned = service->watches;

  while (owned && !same_target(owned->target, descriptor(p->process_fd))) {
    owned = owned->next;
  }

  if (owned) {
    owned->close_fd = p->process_fd;
  }
  else if (p->process_fd >= 0) {
    close_descriptor(p->process_fd);
  }

  p->process_fd = -1;

  while (p->subscriptions) {
    int status = disarm(&p->subscriptions);

    if (status) {
      return status;
    }
  }

#if !defined(_WIN32) || defined(NUPP_WIN64_PROCESS)
  nupp_process_forget_poller(token);
#endif
#if defined(_WIN32) && defined(NUPP_WIN64_PROCESS)
  nuppwinpipeforget(token);
#endif
  *at = p->next;
  free(p);

  /* Close callbacks retain native storage through a normal loop turn. */
  return pump(UV_RUN_NOWAIT, 0, NULL);
}

uint64_t nuppiostart (uint64_t threads) {
  if (!threads || threads > 64) {
    return failed(EINVAL);
  }

  int status = admit();

  if (status) {
    return (uint64_t)(int64_t)status;
  }

#ifdef _WIN32

  if (!service->active_limit) {
    service->active_limit = (size_t)threads;
  }

  return NUPP_UV_FILE_COMPLETION;
#else

  if (service->wake[0] >= 0) {
    return (uint64_t)service->wake[0];
  }

  if (pipe(service->wake) < 0) {
    return failed(errno);
  }

  for (int i = 0; i < 2; ++i) {
    int flags = fcntl(service->wake[i], F_GETFL);

    if (flags < 0 || fcntl(service->wake[i], F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(service->wake[i], F_SETFD, FD_CLOEXEC) < 0) {
      int error = errno;
      close(service->wake[0]);
      close(service->wake[1]);
      service->wake[0] = service->wake[1] = -1;

      return failed(error);
    }
  }

  service->active_limit = (size_t)threads;

  return (uint64_t)service->wake[0];
#endif
}

uint64_t nuppiosubmit (uint64_t kind, uint64_t word, uint64_t base,
                       uint64_t bytes) {
  if (kind < 1 || kind > 3 || bytes > UINT_MAX || bytes == SIZE_MAX) {
    return failed(EINVAL);
  }

  if (kind != 1 && word > INT_MAX) {
    return failed(EBADF);
  }

  if (!base && bytes && kind != 2) {
    return failed(EFAULT);
  }

  if (!service || !service->active_limit) {
    return failed(EINVAL);
  }

  if (service->shutting_down) {
    return failed(ECANCELED);
  }

  if (service->files.count >= MAX_JOBS ||
      bytes > MAX_BYTES - service->files.bytes) {
    return failed(EAGAIN);
  }

  uint64_t ticket = issue();

  if (!ticket) {
    return failed(EOVERFLOW);
  }

  Job *job = calloc(1, sizeof(*job));

  if (!job) {
    return failed(ENOMEM);
  }

  size_t capacity = (size_t)bytes + (kind == 1);
  job->bytes = capacity ? malloc(capacity) : NULL;

  if (capacity && !job->bytes) {
    free(job);

    return failed(ENOMEM);
  }

  if (kind != 2 && bytes) {
    memcpy(job->bytes, (void *)(uintptr_t)base, (size_t)bytes);
  }

  if (kind == 1) {
    job->bytes[bytes] = 0;
  }

  job->kind = kind;
  job->word = word;
  job->ticket.count = (size_t)bytes;
  job->descriptor = -1;
  job->buffer = uv_buf_init((char *)job->bytes, (unsigned)bytes);
  job->ticket.id = ticket;
  fileticketadmit(&service->files, &job->ticket);

  return ticket;
}

uint64_t nuppiotake (void) {
  if (!service) {
    return 0;
  }

  int status = pump(UV_RUN_NOWAIT, 0, NULL);

  if (status) {
    return (uint64_t)(int64_t)status;
  }

  FileTicket *ticket = filetickettake(&service->files);

  return ticket ? ticket->id : 0;
}

uint64_t nuppiofinish (uint64_t ticket, uint64_t out, uint64_t room) {
  if (!service) {
    return failed(EINVAL);
  }

  FileTicket **at = fileticketfind(&service->files, ticket);
  Job *job = (Job *)fileticketcollect(&service->files, at, 1);

  if (!job) {
    return failed(EINVAL);
  }

  uint64_t result = (uint64_t)job->ticket.result;

  if (out && job->kind == 2 && job->ticket.result > 0) {
    memcpy((void *)(uintptr_t)out, job->bytes,
           result < room ? (size_t)result : (size_t)room);
  }

  dispose(job);

  return result;
}

uint64_t nuppiocancel (uint64_t ticket) {
  if (!service) {
    return 0;
  }

  FileTicket **at = fileticketfind(&service->files, ticket);
  Job *job = (Job *)fileticketcancel(&service->files, at);

  if (job) {
    dispose(job);

    return 1;
  }

  /* Successful uv_cancel still owes a callback: take/finish must drain it. */
  job = (Job *)*at;

  if (job && !job->ticket.done) {
    (void)uv_cancel((uv_req_t *)&job->request);
  }

  return 0;
}

uint64_t nuppiosettle (uint64_t ticket) {
  if (!service) {
    return failed(EINVAL);
  }

  FileTicket **at = fileticketfind(&service->files, ticket);
  FileTicket *pending = *at;

  if (!pending) {
    return failed(EINVAL);
  }

  while (!pending->done) {
    int status = pump(UV_RUN_ONCE, UINT64_MAX, NULL);

    if (status) {
      return (uint64_t)(int64_t)status;
    }
  }

  Job *job = (Job *)fileticketcollect(&service->files, at, 0);
  uint64_t result = (uint64_t)job->ticket.result;
  dispose(job);

  return result;
}

int nupp_uv_begin_shutdown (void) {
  if (!service) {
    return 0;
  }

  if (service->running) {
    return -EBUSY;
  }

  service->shutting_down = 1;

  return 0;
}

#ifdef _WIN32

static int drain_closing (void) {
  if (!service->closing_watches && !service->closing_timers) {
    return 0;
  }

  /* Closing a Winsock watch can leave IOCP requests in flight. Keep the
   * still-open wait timer as a single deadline across all completion batches.
   * shortcut: 5s for close completions; revisit for slower supported providers.
   */
  enum { CLOSE_TIMEOUT_MS = 5000 };

  uv_update_time(&service->loop);
  int status = uv_timer_start(&service->timer, timeout, CLOSE_TIMEOUT_MS, 0);

  if (status) {
    return status;
  }

  service->running = 1;

  while ((service->closing_watches || service->closing_timers) &&
         uv_is_active((uv_handle_t *)&service->timer)) {
    uv_run(&service->loop, UV_RUN_ONCE);
  }

  service->running = 0;
  uv_timer_stop(&service->timer);

  return service->closing_watches || service->closing_timers ? -ETIMEDOUT : 0;
}

#endif

int64_t nupp_uv_shutdown (void) {
  if (!service) {
    return 0;
  }

  int status = nupp_uv_begin_shutdown();

  if (status) {
    return status;
  }

  if (service->owner_step || service->adapter_count) {
    return -EBUSY;
  }

  /* Retire queued work before closing watchers drives another loop turn. */
  FileTicket *queued = service->files.jobs;

  while (queued) {
    FileTicket *next = queued->next;

    if (!queued->submitted) {
      nuppiocancel(queued->id);
    }

    queued = next;
  }

#if !defined(_WIN32) || defined(NUPP_WIN64_PROCESS)
  status = nupp_process_shutdown();

  if (status) {
    return status;
  }

  while (nupp_process_pending()) {
    status = pump(UV_RUN_ONCE, UINT64_MAX, NULL);

    if (status) {
      return status;
    }
  }

#endif

#if defined(_WIN32) && defined(NUPP_WIN64_PROCESS)
  nuppwinpipeshutdown();

  while (nuppwinpipepending()) {
    status = pump(UV_RUN_ONCE, UINT64_MAX, NULL);

    if (status) {
      return status;
    }
  }

#endif

#ifdef NUPP_CORE_NET
  nuppnetshutdown();

  while (nuppnetpending()) {
    status = pump(UV_RUN_ONCE, UINT64_MAX, NULL);

    if (status) {
      return status;
    }
  }

#endif

  while (service->pollers) {
    status = (int)nupp_uv_close(service->pollers->token);

    if (status) {
      return status;
    }
  }

  while (service->files.jobs) {
    const Job *job = (const Job *)service->files.jobs;
    uint64_t ticket = job->ticket.id, kind = job->kind;

    if (nuppiocancel(ticket)) {
      continue;
    }

    int64_t result = (int64_t)nuppiosettle(ticket);

    if (service->files.jobs && service->files.jobs->id == ticket) {
      return result;
    }

    if (kind == 1 && result >= 0) {
      close_descriptor((int)result);
    }
  }

  uv_handle_t *timer = (uv_handle_t *)&service->timer;

  if (!uv_is_closing(timer)) {
#ifdef _WIN32
    status = drain_closing();

    if (status) {

      /* Closing handles and the loop still own their backing. A later
       * shutdown can retry with the same stopped, unclosed wait timer. */
      return status;
    }

#endif
    uv_close(timer, NULL);
  }

  status = pump(UV_RUN_NOWAIT, 0, NULL);

  if (status) {
    return status;
  }

  /* A remaining handle or request still owns its backing. */
  status = uv_loop_close(&service->loop);

  if (status) {
    return status;
  }

  if (service->wake[0] >= 0) {
    close_descriptor(service->wake[0]);
    close_descriptor(service->wake[1]);
  }

  free(service);
  service = NULL;

  return 0;
}
