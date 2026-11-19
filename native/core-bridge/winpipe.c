/**
 * @file
 * @brief Copied, overlapped child pipe I/O and owner-thread readiness.
 */

#include "winpipe.h"
#include "reactor.h"
#include "streamio.h"
#include <errno.h>
#include <io.h>
#include <limits.h>
#include <stdlib.h>

enum {
  FIRST_PIPE_KEY = 0x40000000,
  MAX_PIPES = 1024,
  MAX_PIPE_WATCHES = 8192,
  READABLE = 1,
  WRITABLE = 2
};

typedef struct PipeWatch {
  struct PipeWatch *next;
  uint64_t poller;
} PipeWatch;

typedef struct Pipe {
  NuppStreamIO io;
  uv_pipe_t handle;
  struct Pipe *next;
  PipeWatch *watches;
  int descriptor, writing, retiring;
} Pipe;

static _Thread_local Pipe *pipes;
static _Thread_local int issued = FIRST_PIPE_KEY - 1;
static _Thread_local size_t pipecount, watchcount;

int nuppwinpipekey (int64_t descriptor) {
  return descriptor >= FIRST_PIPE_KEY && descriptor <= INT_MAX;
}

static Pipe *findpipe (int64_t descriptor) {
  for (Pipe *pipe = pipes; pipe; pipe = pipe->next) {
    if (pipe->descriptor == descriptor && !pipe->retiring) {
      return pipe;
    }
  }

  return NULL;
}

static int errorcode (int status) {
  switch (status) {
    case UV_EAGAIN:
      return EAGAIN;
    case UV_ENOMEM:
      return ENOMEM;
    case UV_EBADF:
      return EBADF;
    case UV_EINVAL:
      return EINVAL;
    case UV_EPIPE:
    case UV_EOF:
    case UV_ECONNRESET:
      return EPIPE;
    case UV_ECANCELED:
      return ECANCELED;
    default:
      return EIO;
  }
}

static void removewatch (PipeWatch **at) {
  PipeWatch *watch = *at;
  *at = watch->next;
  free(watch);
  watchcount--;
}

static void closed (uv_handle_t *handle) {
  Pipe *pipe = handle->data;
  Pipe **at = &pipes;

  while (*at != pipe) {
    at = &(*at)->next;
  }

  *at = pipe->next;
  pipecount--;
  free(pipe);
}

int nuppwinpipeopen (int fd, int writing) {
  if (pipecount == MAX_PIPES || issued == INT_MAX) {
    return -EMFILE;
  }

  uv_loop_t *loop = nupp_uv_loop();
  Pipe *pipe = loop ? calloc(1, sizeof(*pipe)) : NULL;

  if (!pipe) {
    return -ENOMEM;
  }

  int status = uv_pipe_init(loop, &pipe->handle, 0);

  if (status < 0) {
    free(pipe);

    return -errorcode(status);
  }

  pipe->handle.data = &pipe->io;
  pipe->next = pipes;
  pipes = pipe;
  pipecount++;
  status = uv_pipe_open(&pipe->handle, fd);

  if (status < 0) {
    pipe->retiring = 1;
    uv_close((uv_handle_t *)&pipe->handle, closed);

    return -errorcode(status);
  }

  pipe->descriptor = ++issued;
  pipe->writing = writing;

  /* libuv retains a duplicate for CRT stdio indices. */
  if (fd <= 2) {
    _close(fd);
  }

  return pipe->descriptor;
}

static int64_t result (int count) {
  if (count < 0) {
    errno = errorcode(count);

    return -1;
  }

  return count;
}

int64_t nuppwinpiperead (int64_t descriptor, void *bytes, uint64_t size) {
  Pipe *pipe = findpipe(descriptor);

  if (!pipe || pipe->writing) {
    return result(UV_EBADF);
  }

  return result(nuppstreamread((uv_stream_t *)&pipe->handle, bytes, size));
}

int64_t nuppwinpipewrite (int64_t descriptor, const void *bytes,
                          uint64_t size) {
  Pipe *pipe = findpipe(descriptor);

  if (!pipe || !pipe->writing) {
    return result(UV_EBADF);
  }

  return result(nuppstreamwrite((uv_stream_t *)&pipe->handle, bytes, size));
}

static void retire (Pipe *pipe) {
  pipe->retiring = 1;

  while (pipe->watches) {
    removewatch(&pipe->watches);
  }
}

int nuppwinpipeclose (int64_t descriptor) {
  Pipe *pipe = findpipe(descriptor);

  if (!pipe) {
    return (int)result(UV_EBADF);
  }

  retire(pipe);
  nuppwinpipesweep();

  return 0;
}

int nuppwinpipearm (uint64_t poller, int64_t descriptor, int interest) {
  Pipe *pipe = findpipe(descriptor);

  if (!pipe) {
    return interest ? -EBADF : 0;
  }

  PipeWatch **at = &pipe->watches;

  while (*at && (*at)->poller != poller) {
    at = &(*at)->next;
  }

  if (!interest) {
    if (*at) {
      removewatch(at);
    }

    return 0;
  }

  if (interest != (pipe->writing ? WRITABLE : READABLE)) {
    return -EINVAL;
  }

  if (!pipe->writing) {
    int status = nuppstreamstartread((uv_stream_t *)&pipe->handle);

    if (status < 0) {
      return -errorcode(status);
    }
  }

  if (!*at) {
    if (watchcount == MAX_PIPE_WATCHES) {
      return -EAGAIN;
    }

    PipeWatch *watch = malloc(sizeof(*watch));

    if (!watch) {
      return -ENOMEM;
    }

    *watch = (PipeWatch){.poller = poller};
    *at = watch;
    watchcount++;
  }

  return 0;
}

int64_t nuppwinpipeevent (uint64_t poller, int take) {
  for (Pipe *pipe = pipes; pipe; pipe = pipe->next) {
    if (pipe->retiring || (pipe->writing ? nuppstreampending(&pipe->io) > 0
                                         : !nuppstreamreadable(&pipe->io))) {
      continue;
    }

    for (PipeWatch **at = &pipe->watches; *at; at = &(*at)->next) {
      if ((*at)->poller != poller) {
        continue;
      }

      if (take) {
        removewatch(at);
      }

      return ((int64_t)pipe->descriptor << 5) |
             (pipe->writing ? WRITABLE : READABLE);
    }
  }

  return 0;
}

void nuppwinpipeforget (uint64_t poller) {
  for (Pipe *pipe = pipes; pipe; pipe = pipe->next) {
    nuppwinpipearm(poller, pipe->descriptor, 0);
  }
}

void nuppwinpipesweep (void) {
  for (Pipe *pipe = pipes; pipe; pipe = pipe->next) {
    uv_handle_t *handle = (uv_handle_t *)&pipe->handle;

    if (pipe->retiring && nuppstreampending(&pipe->io) <= 0 &&
        !uv_is_closing(handle)) {
      uv_close(handle, closed);
    }
  }
}

void nuppwinpipeshutdown (void) {
  for (Pipe *pipe = pipes; pipe; pipe = pipe->next) {
    retire(pipe);
    uv_handle_t *handle = (uv_handle_t *)&pipe->handle;

    if (!uv_is_closing(handle)) {
      uv_close(handle, closed);
    }
  }
}

int nuppwinpipepending (void) {
  return pipes != NULL;
}
