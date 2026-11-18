/* The I/O pool behind transport.h: worker threads that do blocking OS work
 * for the Nupp reactor. It is raw OS work only, with no Nupp pointers,
 * callbacks, tasks or collector; Nupp owns admission, resource journals,
 * cancellation and draining. It is C because the workers are OS threads, and
 * foreign threads cannot yet enter Nupp.
 *
 * A job moves from the waiting queue, to a worker, to the finished queue,
 * where Nupp takes it; it stays on the list of all jobs until Nupp finishes,
 * settles or cancels it. One lock guards all of it. */
#include "transport.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { MAX_THREADS = 64 };

struct job {
  uint64_t ticket;
  uint64_t kind; /* enum nupp_io_kind */
  uint64_t word;
  uint64_t result; /* what the call answered, or a negative errno */
  size_t count;
  /* The job's own copy of its bytes. An open's path is NUL-terminated. */
  unsigned char *bytes;
  int running, done, taken;
  struct job *next; /* in the list of all jobs */
  struct job *queue_next; /* in the waiting or the finished queue */
};

/* A job is on at most one queue at a time, so the two share a link. */
struct queue {
  struct job *head, **tail;
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t work_waiting = PTHREAD_COND_INITIALIZER;
static pthread_cond_t job_done = PTHREAD_COND_INITIALIZER;
static struct job *jobs;
static struct queue waiting = {NULL, &waiting.head};
static struct queue finished = {NULL, &finished.head};
static uint64_t last_ticket;
/* A worker writes a byte to the pipe each time it finishes a job; Nupp waits
 * for the read end to become readable. */
static int wake_pipe[2] = {-1, -1};
/* Why starting the pool failed. A failed start is never retried. */
static int start_error;

static uint64_t failed (int error) {
  return (uint64_t)-(int64_t)error;
}

static void enqueue (struct queue *queue, struct job *job) {
  job->queue_next = NULL;
  *queue->tail = job;
  queue->tail = &job->queue_next;
}

static struct job *dequeue (struct queue *queue) {
  struct job *job = queue->head;

  if (job) {
    queue->head = job->queue_next;

    if (!queue->head)
      queue->tail = &queue->head;
  }

  return job;
}

/* Removes a job the queue is known to hold. */
static void unlink_queued (struct queue *queue, struct job *job) {
  struct job **at = &queue->head;

  while (*at != job)
    at = &(*at)->queue_next;

  *at = job->queue_next;

  if (!*at)
    queue->tail = at;
}

/* Answers where the list of all jobs holds the ticket's job, which is NULL
 * when no job has it. */
static struct job **find (uint64_t ticket) {
  struct job **at = &jobs;

  while (*at && (*at)->ticket != ticket)
    at = &(*at)->next;

  return at;
}

static void dispose (struct job **at) {
  struct job *job = *at;
  *at = job->next;
  free(job->bytes);
  free(job);
}

static uint64_t perform (struct job *job) {
  ssize_t result;

  do {
    switch (job->kind) {
      case NUPP_IO_OPEN:
        result = open((char *)job->bytes, (int)(uint32_t)job->word,
                      (mode_t)(job->word >> 32));
        break;
      case NUPP_IO_READ:
        result = read((int)job->word, job->bytes, job->count);
        break;
      default:
        result = write((int)job->word, job->bytes, job->count);
        break;
    }
  } while (result < 0 && errno == EINTR);

  return result < 0 ? failed(errno) : (uint64_t)result;
}

static void announce_finished (void) {
  const unsigned char byte = 1;

  /* EAGAIN means the pipe is full, and so readable already. */
  while (write(wake_pipe[1], &byte, 1) < 0 && errno == EINTR) {
  }
}

static void *worker (void *unused) {
  (void)unused;

  for (;;) {
    pthread_mutex_lock(&lock);

    while (!waiting.head)
      pthread_cond_wait(&work_waiting, &lock);

    struct job *job = dequeue(&waiting);
    job->running = 1;
    pthread_mutex_unlock(&lock);

    uint64_t result = perform(job);

    pthread_mutex_lock(&lock);
    job->result = result;
    job->done = 1;
    enqueue(&finished, job);
    pthread_cond_broadcast(&job_done);
    pthread_mutex_unlock(&lock);
    announce_finished();
  }

  return NULL;
}

/* Makes both ends of the wake pipe nonblocking and closed on exec. */
static int configure_wake_pipe (void) {
  for (int i = 0; i < 2; ++i) {
    int flags = fcntl(wake_pipe[i], F_GETFL);

    if (flags < 0 || fcntl(wake_pipe[i], F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(wake_pipe[i], F_SETFD, FD_CLOEXEC) < 0)
      return errno;
  }

  return 0;
}

static int start_workers (uint64_t threads) {
  if (threads < 1)
    threads = 1;

  if (threads > MAX_THREADS)
    threads = MAX_THREADS;

  for (uint64_t i = 0; i < threads; ++i) {
    pthread_t thread;
    int error = pthread_create(&thread, NULL, worker, NULL);

    if (error)
      return error;

    pthread_detach(thread);
  }

  return 0;
}

/* Answers the wake pipe's read end, or why the pool could not start. */
static uint64_t start_result (void) {
  return start_error ? failed(start_error) : (uint64_t)wake_pipe[0];
}

uint64_t nupp_io_start (uint64_t threads) {
  pthread_mutex_lock(&lock);
  int started = wake_pipe[0] >= 0 || start_error;

  if (!started) {
    if (pipe(wake_pipe) < 0)
      start_error = errno;
    else
      start_error = configure_wake_pipe();

    if (!start_error)
      start_error = start_workers(threads);
  }

  uint64_t result = start_result();
  pthread_mutex_unlock(&lock);

  return result;
}

/* Allocates a job with its own copy of the bytes it writes or opens, or
 * room for the bytes it reads. */
static struct job *new_job (uint64_t kind, uint64_t word, uint64_t base,
                            uint64_t bytes) {
  struct job *job = calloc(1, sizeof(*job));

  if (!job)
    return NULL;

  size_t terminator = kind == NUPP_IO_OPEN ? 1 : 0;
  size_t capacity = (size_t)bytes + terminator;
  job->bytes = capacity ? malloc(capacity) : NULL;

  if (capacity && !job->bytes) {
    free(job);

    return NULL;
  }

  if (kind != NUPP_IO_READ && bytes)
    memcpy(job->bytes, (void *)(uintptr_t)base, (size_t)bytes);

  if (kind == NUPP_IO_OPEN)
    job->bytes[bytes] = 0;

  job->kind = kind;
  job->word = word;
  job->count = (size_t)bytes;

  return job;
}

uint64_t nupp_io_submit (uint64_t kind, uint64_t word, uint64_t base,
                         uint64_t bytes) {
  /* bytes == SIZE_MAX would leave no room for an open's terminator. */
  if (kind < NUPP_IO_OPEN || kind > NUPP_IO_WRITE ||
      bytes > (uint64_t)SSIZE_MAX || bytes == SIZE_MAX)
    return failed(EINVAL);

  if (!base && bytes && kind != NUPP_IO_READ)
    return failed(EFAULT);

  struct job *job = new_job(kind, word, base, bytes);

  if (!job)
    return failed(ENOMEM);

  pthread_mutex_lock(&lock);

  /* Tickets stay positive as int64, so they never read as an errno. */
  if (wake_pipe[0] < 0 || start_error || last_ticket == INT64_MAX) {
    pthread_mutex_unlock(&lock);
    free(job->bytes);
    free(job);

    return failed(EINVAL);
  }

  job->ticket = ++last_ticket;
  job->next = jobs;
  jobs = job;
  enqueue(&waiting, job);
  uint64_t ticket = job->ticket;
  pthread_cond_signal(&work_waiting);
  pthread_mutex_unlock(&lock);

  return ticket;
}

uint64_t nupp_io_take (void) {
  pthread_mutex_lock(&lock);
  struct job *job = dequeue(&finished);

  if (job)
    job->taken = 1;

  uint64_t ticket = job ? job->ticket : 0;
  pthread_mutex_unlock(&lock);

  return ticket;
}

uint64_t nupp_io_finish (uint64_t ticket, uint64_t out, uint64_t room) {
  pthread_mutex_lock(&lock);
  struct job **at = find(ticket), *job = *at;
  uint64_t result = failed(EINVAL);

  if (job && job->done && job->taken) {
    result = job->result;

    if (out && job->kind == NUPP_IO_READ && (int64_t)result > 0) {
      uint64_t count = result < room ? result : room;
      memcpy((void *)(uintptr_t)out, job->bytes, (size_t)count);
    }

    dispose(at);
  }

  pthread_mutex_unlock(&lock);

  return result;
}

uint64_t nupp_io_cancel (uint64_t ticket) {
  pthread_mutex_lock(&lock);
  struct job **at = find(ticket), *job = *at;
  uint64_t cancelled = 0;

  if (job && !job->running) {
    unlink_queued(&waiting, job);
    dispose(at);
    cancelled = 1;
  }

  pthread_mutex_unlock(&lock);

  return cancelled;
}

uint64_t nupp_io_settle (uint64_t ticket) {
  pthread_mutex_lock(&lock);
  struct job **at;

  while (*(at = find(ticket)) && !(*at)->done)
    pthread_cond_wait(&job_done, &lock);

  struct job *job = *at;
  uint64_t result = failed(EINVAL);

  if (job) {
    if (!job->taken)
      unlink_queued(&finished, job);

    result = job->result;
    dispose(at);
  }

  pthread_mutex_unlock(&lock);

  return result;
}
