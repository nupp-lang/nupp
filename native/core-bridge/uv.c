/* libuv callbacks cannot enter managed Nupp. This transport holds only copied
 * bytes, native requests and opaque subscriptions; Nupp owns all task policy.
 * All calls and callbacks run on the loop's owning thread. libuv alone runs
 * filesystem work on its pool; no worker sees a Nupp value or heap pointer. */
#define _POSIX_C_SOURCE 200809L
#include "transport.h"
#include "reactor.h"
#include "process.h"
#include "transport.h"
#include <uv.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

typedef struct Poller Poller;
typedef struct Watch Watch;
typedef struct Subscription Subscription;
typedef struct Timer Timer;
typedef struct Job Job;

struct Watch {
  uv_poll_t handle;
  Watch *next;
  int fd, close_fd;
};

struct Subscription {
  Watch *watch;
  Subscription *next;
  int interest, ready;
};

struct Poller {
  uint64_t token, owner;
  int process_fd, socket_fd;
  Subscription *subscriptions;
  Poller *next;
};

struct Timer {
  uv_timer_t handle;
  uint64_t token;
  int ready;
  Timer *next;
};

struct Job {
  uv_fs_t request;
  uv_buf_t buffer;
  uint64_t ticket, kind, word;
  int64_t result;
  size_t count;
  unsigned char *bytes;
  int descriptor, descriptor_error;
  int submitted, done, taken;
  Job *next, *finished;
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
  Job *jobs, *finished, **finished_tail;
  size_t jobs_count, active_jobs, active_limit, bytes, watches_count,
      subscriptions_count;
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

  s->finished_tail = &s->finished;
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
    close(w->close_fd);
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

static int64_t open_poller (int process_fd, int socket_fd, uint64_t owner) {
  int status = admit();

  if (status) {
    return status;
  }

  if (socket_fd >= 0 &&
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
  p->socket_fd = socket_fd;

  if (socket_fd >= 0) {
    p->owner = owner ? owner : token;
    service->adapter_count++;
  }

  p->next = service->pollers;
  service->pollers = p;

  return (int64_t)p->token;
}

static int subscribe (Poller *p, int fd, Subscription **out) {
  if (service->subscriptions_count == MAX_SUBSCRIPTIONS) {
    return -EAGAIN;
  }

  Subscription *s = calloc(1, sizeof(*s));

  if (!s) {
    return -ENOMEM;
  }

  Watch *w = service->watches;

  while (w && w->fd != fd) {
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

    int status = uv_poll_init(&service->loop, &w->handle, fd);

    if (status) {
      free(w);
      free(s);

      return status;
    }

    w->handle.data = w;
    w->fd = fd;
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

static int arm (Poller *p, int fd, int interest) {
  if (interest && service->shutting_down) {
    return -ECANCELED;
  }

  Subscription **at = &p->subscriptions;

  while (*at && (*at)->watch->fd != fd) {
    at = &(*at)->next;
  }

  Subscription *s = *at;

  if (!interest) {
    return disarm(at);
  }

  if (!s) {
    int status = subscribe(p, fd, &s);

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

  return open_poller((int)process_fd, -1, 0);
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

  if (fd < 0 || fd > INT_MAX || interest > 3) {
    return -EINVAL;
  }

  return arm(p, (int)fd, (int)interest);
}

static int adapter_available (int64_t fd) {
  if (fd < 0 || fd > INT_MAX) {
    return -EBADF;
  }

  for (Poller *p = service ? service->pollers : NULL; p; p = p->next) {
    if (p->owner == p->token && p->socket_fd == fd) {
      return -EEXIST;
    }
  }

  return 0;
}

int64_t nupp_uv_socket_open (int64_t fd) {
  int status = adapter_available(fd);

  if (status) {
    return status;
  }

  int type;
  socklen_t size = sizeof(type);

  if (getsockopt((int)fd, SOL_SOCKET, SO_TYPE, &type, &size)) {
    return -errno;
  }

  return open_poller(-1, (int)fd, 0);
}

int64_t nupp_uv_socket_observe (uint64_t owner) {
  Poller *p = poller(owner);

  if (!p || p->owner != owner) {
    return -EBADF;
  }

  return open_poller(-1, p->socket_fd, owner);
}

int nupp_uv_socket_arm (uint64_t token, uint64_t interest) {
  Poller *p = poller(token);

  if (!p || !p->owner) {
    return -EBADF;
  }

  if (interest > 3) {
    return -EINVAL;
  }

  return arm(p, p->socket_fd, (int)interest);
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
  arm(p, p->socket_fd, 0);
  *at = p->next;
  free(p);
  service->adapter_count--;
}

int64_t nupp_uv_descriptor_open (int64_t fd) {
  int status = adapter_available(fd);

  if (status) {
    return status;
  }

  if (fcntl((int)fd, F_GETFD) < 0) {
    return -errno;
  }

  int64_t token = open_poller(-1, (int)fd, 0);

  if (token < 0) {
    return token;
  }

  /* open_poller prepends the owner. Validate without arming any interest. */
  Subscription *s;
  status = subscribe(service->pollers, (int)fd, &s);

  if (status) {
    drop_socket(&service->pollers);

    return status;
  }

  return token;
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

  int fd = p->socket_fd;
  Poller **at = &service->pollers;

  while (*at) {
    if ((*at)->owner == owner) {
      drop_socket(at);
    }
    else {
      /* Withdraw any generic native subscription before the actual close. */
      if (!(*at)->owner) {
        arm(*at, fd, 0);
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

static Job **find (uint64_t ticket) {
  Job **at = &service->jobs;

  while (*at && (*at)->ticket != ticket) {
    at = &(*at)->next;
  }

  return at;
}

static void dispose (Job **at) {
  Job *job = *at;
  *at = job->next;
  service->jobs_count--;
  service->bytes -= job->count;

  if (job->descriptor >= 0) {
    close(job->descriptor);
  }

  free(job->bytes);
  free(job);
}

static void completed (uv_fs_t *request) {
  Job *job = request->data;
  job->result = request->result;
  uv_fs_req_cleanup(request);
  /* The ticket owns its duplicate and bytes until dispose at collection. */
  service->active_jobs--;
  job->done = 1;
  *service->finished_tail = job;
  service->finished_tail = &job->finished;
  const unsigned char byte = 1;

  /* A full pipe already announces queued results; notifications coalesce. */
  while (write(service->wake[1], &byte, 1) < 0 && errno == EINTR) {
  }
}

static void hold_descriptor (Job *job) {
  if (job->kind == NUPP_IO_OPEN || job->descriptor >= 0 ||
      job->descriptor_error) {
    return;
  }

  do {
    job->descriptor = fcntl((int)job->word, F_DUPFD_CLOEXEC, 0);
  } while (job->descriptor < 0 && errno == EINTR);

  if (job->descriptor < 0) {
    job->descriptor_error = errno;
  }
}

void nupp_uv_preserve_file (uint64_t descriptor) {
  /* Usually capture at dispatch. Closing early must capture before the
   * descriptor can be recycled, even if the job hasn't reached libuv. */
  for (Job *job = service ? service->jobs : NULL; job; job = job->next) {
    if (!job->submitted && job->word == descriptor) {
      hold_descriptor(job);
    }
  }
}

static void submit_jobs (void) {
  for (Job *job = service->jobs; job; job = job->next) {
    if (service->active_jobs == service->active_limit) {
      break;
    }

    if (job->submitted) {
      continue;
    }

    hold_descriptor(job);
    job->submitted = 1;
    service->active_jobs++;
    job->request.data = job;
    int status;

    if (job->descriptor_error) {
      status = -job->descriptor_error;
    }
    else if (job->kind == NUPP_IO_OPEN) {
      status = uv_fs_open(&service->loop, &job->request, (char *)job->bytes,
                          (int)(uint32_t)job->word, (int)(job->word >> 32),
                          completed);
    }
    else if (job->kind == NUPP_IO_READ) {
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
  int64_t child = nupp_process_event(p->token);

  if (child) {
    return child;
  }

  for (Subscription *s = p->subscriptions; s; s = s->next) {
    if (!s->ready) {
      continue;
    }

    int bits = s->ready;
    s->ready = 0;

    return ((int64_t)s->watch->fd << 5) | bits;
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

  while (owned && owned->fd != p->process_fd) {
    owned = owned->next;
  }

  if (owned) {
    owned->close_fd = p->process_fd;
  }
  else if (p->process_fd >= 0) {
    close(p->process_fd);
  }

  p->process_fd = -1;

  while (p->subscriptions) {
    int status = disarm(&p->subscriptions);

    if (status) {
      return status;
    }
  }

  nupp_process_forget_poller(token);
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
}

uint64_t nuppiosubmit (uint64_t kind, uint64_t word, uint64_t base,
                       uint64_t bytes) {
  if (kind < NUPP_IO_OPEN || kind > NUPP_IO_WRITE || bytes > UINT_MAX ||
      bytes == SIZE_MAX) {
    return failed(EINVAL);
  }

  if (kind != NUPP_IO_OPEN && word > INT_MAX) {
    return failed(EBADF);
  }

  if (!base && bytes && kind != NUPP_IO_READ) {
    return failed(EFAULT);
  }

  if (!service || service->wake[0] < 0) {
    return failed(EINVAL);
  }

  if (service->shutting_down) {
    return failed(ECANCELED);
  }

  if (service->jobs_count >= MAX_JOBS || bytes > MAX_BYTES - service->bytes) {
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

  size_t capacity = (size_t)bytes + (kind == NUPP_IO_OPEN);
  job->bytes = capacity ? malloc(capacity) : NULL;

  if (capacity && !job->bytes) {
    free(job);

    return failed(ENOMEM);
  }

  if (kind != NUPP_IO_READ && bytes) {
    memcpy(job->bytes, (void *)(uintptr_t)base, (size_t)bytes);
  }

  if (kind == NUPP_IO_OPEN) {
    job->bytes[bytes] = 0;
  }

  job->kind = kind;
  job->word = word;
  job->count = (size_t)bytes;
  job->descriptor = -1;
  job->buffer = uv_buf_init((char *)job->bytes, (unsigned)bytes);
  job->ticket = ticket;
  *find(0) = job; /* Ticket zero finds the FIFO append position. */
  service->jobs_count++;
  service->bytes += bytes;

  return job->ticket;
}

uint64_t nuppiotake (void) {
  if (!service) {
    return 0;
  }

  int status = pump(UV_RUN_NOWAIT, 0, NULL);

  if (status) {
    return (uint64_t)(int64_t)status;
  }

  Job *job = service->finished;

  if (!job) {
    return 0;
  }

  service->finished = job->finished;
  job->finished = NULL;

  if (!service->finished) {
    service->finished_tail = &service->finished;
  }

  job->taken = 1;

  return job->ticket;
}

uint64_t nuppiofinish (uint64_t ticket, uint64_t out, uint64_t room) {
  if (!service) {
    return failed(EINVAL);
  }

  Job **at = find(ticket), *job = *at;

  if (!job || !job->done || !job->taken) {
    return failed(EINVAL);
  }

  uint64_t result = (uint64_t)job->result;

  if (out && job->kind == NUPP_IO_READ && job->result > 0) {
    memcpy((void *)(uintptr_t)out, job->bytes,
           result < room ? (size_t)result : (size_t)room);
  }

  dispose(at);

  return result;
}

uint64_t nuppiocancel (uint64_t ticket) {
  if (!service) {
    return 0;
  }

  Job **at = find(ticket), *job = *at;

  if (!job) {
    return 0;
  }

  if (!job->submitted) {
    dispose(at);

    return 1;
  }

  /* Successful uv_cancel still owes a callback: take/finish must drain it. */
  if (!job->done) {
    (void)uv_cancel((uv_req_t *)&job->request);
  }

  return 0;
}

uint64_t nuppiosettle (uint64_t ticket) {
  if (!service) {
    return failed(EINVAL);
  }

  Job **at = find(ticket), *job = *at;

  if (!job) {
    return failed(EINVAL);
  }

  while (!job->done) {
    int status = pump(UV_RUN_ONCE, UINT64_MAX, NULL);

    if (status) {
      return (uint64_t)(int64_t)status;
    }
  }

  if (!job->taken) {
    Job **queued = &service->finished;

    while (*queued != job) {
      queued = &(*queued)->finished;
    }

    *queued = job->finished;

    if (!*queued) {
      service->finished_tail = queued;
    }
  }

  uint64_t result = (uint64_t)job->result;
  dispose(at);

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
  Job *queued = service->jobs;

  while (queued) {
    Job *next = queued->next;

    if (!queued->submitted) {
      nuppiocancel(queued->ticket);
    }

    queued = next;
  }

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

  while (service->pollers) {
    status = (int)nupp_uv_close(service->pollers->token);

    if (status) {
      return status;
    }
  }

  while (service->jobs) {
    uint64_t ticket = service->jobs->ticket, kind = service->jobs->kind;

    if (nuppiocancel(ticket)) {
      continue;
    }

    int64_t result = (int64_t)nuppiosettle(ticket);

    if (service->jobs && service->jobs->ticket == ticket) {
      return result;
    }

    if (kind == NUPP_IO_OPEN && result >= 0) {
      close((int)result);
    }
  }

  uv_handle_t *timer = (uv_handle_t *)&service->timer;

  if (!uv_is_closing(timer)) {
    uv_close(timer, NULL);
  }

  status = pump(UV_RUN_NOWAIT, 0, NULL);

  if (status) {
    return status;
  }

  /* An attached adapter still owns any remaining handle or request. */
  status = uv_loop_close(&service->loop);

  if (status) {
    return status;
  }

  if (service->wake[0] >= 0) {
    close(service->wake[0]);
    close(service->wake[1]);
  }

  free(service);
  service = NULL;

  return 0;
}
