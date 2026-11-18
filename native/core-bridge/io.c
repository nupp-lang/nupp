/* Raw blocking OS work only. No Nupp pointers, callbacks, tasks or collector.
 * Nupp owns admission, resource journals and cancellation/drain policy. C is
 * needed for the OS-thread entry while foreign threads cannot enter Nupp. */
#include "transport.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct Job Job;

struct Job {
  uint64_t ticket, kind, word, result;
  size_t count;
  unsigned char *bytes;
  int running, done, taken;
  Job *next, *queued, *finished;
};

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t work = PTHREAD_COND_INITIALIZER;
static pthread_cond_t settled = PTHREAD_COND_INITIALIZER;
static Job *jobs, *waiting, **waiting_tail = &waiting;
static Job *finished, **finished_tail = &finished;
static uint64_t issued;
static int wake_pipe[2] = {-1, -1}, start_error;

static uint64_t failed(int error)
{
  return (uint64_t)-(int64_t)error;
}

static Job **find(uint64_t ticket)
{
  Job **at = &jobs;
  while (*at && (*at)->ticket != ticket)
    at = &(*at)->next;
  return at;
}

static void dispose(Job **at)
{
  Job *job = *at;
  *at = job->next;
  free(job->bytes);
  free(job);
}

static uint64_t perform(Job *job)
{
  ssize_t result;
  do {
    if (job->kind == 1)
      result = open((char *)job->bytes, (int)(uint32_t)job->word,
                    (mode_t)(job->word >> 32));
    else if (job->kind == 2)
      result = read((int)job->word, job->bytes, job->count);
    else
      result = write((int)job->word, job->bytes, job->count);
  } while (result < 0 && errno == EINTR);
  return result < 0 ? failed(errno) : (uint64_t)result;
}

static void *worker(void *unused)
{
  (void)unused;
  for (;;) {
    pthread_mutex_lock(&mutex);
    while (!waiting)
      pthread_cond_wait(&work, &mutex);
    Job *job = waiting;
    waiting = job->queued;
    if (!waiting)
      waiting_tail = &waiting;
    job->running = 1;
    pthread_mutex_unlock(&mutex);
    uint64_t result = perform(job);
    pthread_mutex_lock(&mutex);
    job->result = result;
    job->done = 1;
    job->finished = NULL;
    *finished_tail = job;
    finished_tail = &job->finished;
    pthread_cond_broadcast(&settled);
    pthread_mutex_unlock(&mutex);
    const unsigned char byte = 1;
    /* EAGAIN means the readable pipe already announces pending work. */
    while (write(wake_pipe[1], &byte, 1) < 0 && errno == EINTR) {
    }
  }
  return NULL;
}

uint64_t nupp_io_start(uint64_t threads)
{
  pthread_mutex_lock(&mutex);
  if (wake_pipe[0] >= 0 || start_error) {
    uint64_t result =
        start_error ? failed(start_error) : (uint64_t)wake_pipe[0];
    pthread_mutex_unlock(&mutex);
    return result;
  }
  if (pipe(wake_pipe) < 0) {
    start_error = errno;
    pthread_mutex_unlock(&mutex);
    return failed(start_error);
  }
  for (int i = 0; i < 2; ++i) {
    int flags = fcntl(wake_pipe[i], F_GETFL);
    if (flags < 0 || fcntl(wake_pipe[i], F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(wake_pipe[i], F_SETFD, FD_CLOEXEC) < 0) {
      start_error = errno;
      break;
    }
  }
  if (!start_error) {
    if (threads < 1)
      threads = 1;
    if (threads > 64)
      threads = 64;
    for (uint64_t i = 0; i < threads; ++i) {
      pthread_t thread;
      int error = pthread_create(&thread, NULL, worker, NULL);
      if (error) {
	start_error = error;
	break;
      }
      pthread_detach(thread);
    }
  }
  uint64_t result = start_error ? failed(start_error) : (uint64_t)wake_pipe[0];
  pthread_mutex_unlock(&mutex);
  return result;
}

uint64_t nupp_io_submit(uint64_t kind, uint64_t word, uint64_t base,
                        uint64_t bytes)
{
  if (kind < 1 || kind > 3 || bytes > (uint64_t)SSIZE_MAX || bytes == SIZE_MAX)
    return failed(EINVAL);
  if (!base && bytes && kind != 2)
    return failed(EFAULT);
  Job *job = calloc(1, sizeof(*job));
  if (!job)
    return failed(ENOMEM);
  size_t capacity = (size_t)bytes + (kind == 1 ? 1 : 0);
  job->bytes = capacity ? malloc(capacity) : NULL;
  if (capacity && !job->bytes) {
    free(job);
    return failed(ENOMEM);
  }
  if (kind != 2 && bytes)
    memcpy(job->bytes, (void *)(uintptr_t)base, (size_t)bytes);
  if (kind == 1)
    job->bytes[bytes] = 0;
  job->kind = kind;
  job->word = word;
  job->count = (size_t)bytes;
  pthread_mutex_lock(&mutex);
  if (wake_pipe[0] < 0 || start_error || issued == INT64_MAX) {
    pthread_mutex_unlock(&mutex);
    free(job->bytes);
    free(job);
    return failed(EINVAL);
  }
  job->ticket = ++issued;
  job->next = jobs;
  jobs = job;
  *waiting_tail = job;
  waiting_tail = &job->queued;
  uint64_t ticket = job->ticket;
  pthread_cond_signal(&work);
  pthread_mutex_unlock(&mutex);
  return ticket;
}

uint64_t nupp_io_take(void)
{
  pthread_mutex_lock(&mutex);
  Job *job = finished;
  if (job) {
    finished = job->finished;
    if (!finished)
      finished_tail = &finished;
    job->taken = 1;
  }
  uint64_t result = job ? job->ticket : 0;
  pthread_mutex_unlock(&mutex);
  return result;
}

uint64_t nupp_io_finish(uint64_t ticket, uint64_t out, uint64_t room)
{
  pthread_mutex_lock(&mutex);
  Job **at = find(ticket), *job = *at;
  uint64_t result = failed(EINVAL);
  if (job && job->done && job->taken) {
    result = job->result;
    if (out && job->kind == 2 && (int64_t)result > 0) {
      uint64_t count = result < room ? result : room;
      memcpy((void *)(uintptr_t)out, job->bytes, (size_t)count);
    }
    dispose(at);
  }
  pthread_mutex_unlock(&mutex);
  return result;
}

uint64_t nupp_io_cancel(uint64_t ticket)
{
  pthread_mutex_lock(&mutex);
  Job **at = find(ticket), *job = *at;
  uint64_t result = 0;
  if (job && !job->running) {
    Job **queued = &waiting;
    while (*queued != job)
      queued = &(*queued)->queued;
    *queued = job->queued;
    if (!*queued)
      waiting_tail = queued;
    dispose(at);
    result = 1;
  }
  pthread_mutex_unlock(&mutex);
  return result;
}

uint64_t nupp_io_settle(uint64_t ticket)
{
  pthread_mutex_lock(&mutex);
  Job **at;
  while (*(at = find(ticket)) && !(*at)->done)
    pthread_cond_wait(&settled, &mutex);
  Job *job = *at;
  uint64_t result = failed(EINVAL);
  if (job) {
    if (!job->taken) {
      Job **queued = &finished;
      while (*queued != job)
	queued = &(*queued)->finished;
      *queued = job->finished;
      if (!*queued)
	finished_tail = queued;
    }
    result = job->result;
    dispose(at);
  }
  pthread_mutex_unlock(&mutex);
  return result;
}
