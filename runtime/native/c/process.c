/* Child processes, on libuv.
 *
 * Spawning, the pipes to and from a child, readiness and reaping are libuv's.
 * What is left here is the ABI: a spawn described field by field because the
 * caller is across a C boundary and cannot hand over a struct, streams whose
 * descriptor and handle have separate lifetimes, and reads and writes that
 * answer rather than block.
 *
 * The loop is pumped by the caller rather than run on a thread of its own.
 * `nuppProcessWaitReady` is `uv_run` with a deadline, which is exactly what a
 * scheduler wants: it decides when to look, and nothing here decides for it.
 */

#include "nupp_native.h"

#include <uv.h>

#include <stdlib.h>
#include <string.h>

/* How a release went, in the seam's own terms. */
#define RELEASED 0
#define RELEASED_WITH_REASON 1
#define NOT_RELEASED 2

/* --- the loop ----------------------------------------------------------- */

/* One loop for every child this process starts. It is only ever entered from
 * the thread that owns the Lua state, which is the same thread every call here
 * arrives on, so nothing in it needs a lock. */
static uv_loop_t childLoop;
static uv_timer_t childDeadline;
static bool loopReady;

/* The deadline below is armed and stopped rather than created and closed each
 * time. libuv keeps a pointer to a handle until its close callback has run, and
 * a turn of the loop is not enough to guarantee that -- a timer living on the
 * caller's stack would be freed while the loop still held it. */
static uv_loop_t *loop(void) {
    if (!loopReady) {
        if (uv_loop_init(&childLoop) != 0) {
            return NULL;
        }
        if (uv_timer_init(&childLoop, &childDeadline) != 0) {
            uv_loop_close(&childLoop);
            return NULL;
        }
        /* Stopped, so it is not one of the handles keeping the loop alive. */
        uv_unref((uv_handle_t *)&childDeadline);
        loopReady = true;
    }
    return &childLoop;
}

/* macOS has no SOCK_CLOEXEC, so libuv creates a child's socketpair and marks it
 * close-on-exec in two steps. Any fork landing between those two inherits the
 * descriptors, and a pipe held open by a process nobody is waiting for never
 * reports end of file. Serializing this library's spawns closes the window for
 * the pipes this library makes. */
static uv_mutex_t spawnGuard;
static uv_once_t spawnGuardOnce = UV_ONCE_INIT;

static void make_spawn_guard(void) {
    uv_mutex_init(&spawnGuard);
}

static void fail_uv(const char *what, int code) {
    nupp_fail_format("%s: %s", what, uv_strerror(code));
}

/* --- growable string vectors -------------------------------------------- */

/* A NULL-terminated array of owned strings, which is what libuv wants a command
 * line and an environment as. */
typedef struct {
    char **items;
    size_t count;
    size_t capacity;
} Strings;

static bool strings_push(Strings *list, const uint8_t *data, size_t length) {
    char *copy;
    if (list->count + 2 > list->capacity) {
        size_t next = list->capacity < 8 ? 8 : list->capacity * 2;
        char **grown = realloc(list->items, next * sizeof *grown);
        if (grown == NULL) {
            return false;
        }
        list->items = grown;
        list->capacity = next;
    }
    copy = malloc(length + 1);
    if (copy == NULL) {
        return false;
    }
    if (length != 0) {
        memcpy(copy, data, length);
    }
    copy[length] = '\0';
    list->items[list->count++] = copy;
    list->items[list->count] = NULL;
    return true;
}

static void strings_free(Strings *list) {
    size_t at;
    for (at = 0; at < list->count; at++) {
        free(list->items[at]);
    }
    free(list->items);
    memset(list, 0, sizeof *list);
}

/* --- streams ------------------------------------------------------------ */

/* One end of a pipe to a child, and whether this process has given it up.
 *
 * Two lifetimes here, and they are not the same one. The pipe is released by
 * `nuppProcessCloseStream`, after which this handle is still perfectly alive: it
 * may be named to a readiness wait, asked its state, or closed again. The handle
 * ends only at `nuppProcessStreamDestroy`.
 *
 * libuv pushes bytes at a callback where the ABI answers a count, so what
 * arrives is buffered here and drained by `tryRead`. That buffer is the whole
 * of the adaptation between the two shapes. */
struct NuppStream {
    uv_pipe_t pipe;
    bool readable;
    bool started;
    bool closed;
    bool destroyed;
    bool ended;
    int failure;

    uint8_t *buffer;
    size_t length;
    size_t offset;
    size_t capacity;

    /* A write in flight owns its bytes until libuv says it is done with them. */
    size_t writing;
};

typedef struct NuppStream NuppStream;

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
    NuppStream *stream = handle->data;
    size_t wanted = stream->length + suggested;
    if (wanted > stream->capacity) {
        size_t next = stream->capacity < 65536 ? 65536 : stream->capacity;
        uint8_t *grown;
        while (next < wanted) {
            next *= 2;
        }
        grown = realloc(stream->buffer, next);
        if (grown == NULL) {
            *buffer = uv_buf_init(NULL, 0);
            return;
        }
        stream->buffer = grown;
        stream->capacity = next;
    }
    *buffer = uv_buf_init((char *)stream->buffer + stream->length,
        (unsigned)(stream->capacity - stream->length));
}

static void on_read(uv_stream_t *handle, ssize_t got, const uv_buf_t *buffer) {
    NuppStream *stream = ((uv_handle_t *)handle)->data;
    (void)buffer;
    if (got > 0) {
        stream->length += (size_t)got;
        return;
    }
    if (got == UV_EOF) {
        stream->ended = true;
    } else if (got < 0) {
        stream->failure = (int)got;
    }
    uv_read_stop(handle);
    stream->started = false;
}

/* The deadline only has to end the turn, so it has nothing to do when it
 * fires. It still needs a callback: uv_timer_start refuses a null one, and a
 * timer that was refused leaves the wait below unbounded. */
static void expired(uv_timer_t *timer) {
    (void)timer;
}

static void on_closed(uv_handle_t *handle) {
    NuppStream *stream = handle->data;
    stream->closed = true;
    if (stream->destroyed) {
        free(stream->buffer);
        free(stream);
    }
}

static void on_written(uv_write_t *request, int status) {
    NuppStream *stream = request->data;
    if (status < 0 && stream->failure == 0) {
        stream->failure = status;
    }
    stream->writing = 0;
    free(request);
}

/* --- the child ---------------------------------------------------------- */

struct NuppChild {
    uv_process_t process;
    NuppStream *ends[3];
    bool merged;
    bool hasExit;
    int32_t code;
    bool killed;
    bool released;
    bool reaped;
    bool destroyed;
    bool closed;
    bool spawnFailed;
};

typedef struct NuppChild NuppChild;

struct NuppSpawn {
    Strings args;
    Strings env;
    char *cwd;
    bool clearEnv;
    uint8_t modes[3];
    bool failed;
};

typedef struct NuppSpawn NuppSpawn;

static size_t uncollected;

NUPP_EXPORT size_t nuppProcessUncollectedTotal(void) {
    return uncollected;
}

/* The bootstrap snapshot still binds this name. Current sources read the one
 * clock through `nupp.time`, and this goes when that snapshot is next made.
 */
NUPP_EXPORT double nuppProcessMonotonicMs(void) {
    return (double)uv_hrtime() / 1.0e6;
}

/* --- describing a spawn ------------------------------------------------- */

NUPP_EXPORT NuppSpawn *nuppProcessSpawnBegin(void) {
    NuppSpawn *request = calloc(1, sizeof *request);
    if (request == NULL) {
        nupp_fail("out of memory");
        return NULL;
    }
    request->modes[0] = NUPP_MODE_PIPE;
    request->modes[1] = NUPP_MODE_PIPE;
    request->modes[2] = NUPP_MODE_PIPE;
    return request;
}

NUPP_EXPORT bool nuppProcessSpawnArg(
    NuppSpawn *request, const uint8_t *text, size_t length
) {
    if (request == NULL || (text == NULL && length != 0)) {
        return false;
    }
    if (!strings_push(&request->args, text, length)) {
        request->failed = true;
        nupp_fail("out of memory");
        return false;
    }
    return true;
}

/* One `KEY=VALUE`. The whole environment is built this way, including the
 * inherited one: there is no spelling for "inherit" once a child is described
 * entry by entry, so every case is the same case. */
NUPP_EXPORT bool nuppProcessSpawnEnv(
    NuppSpawn *request, const uint8_t *text, size_t length
) {
    if (request == NULL || (text == NULL && length != 0)) {
        return false;
    }
    if (memchr(text, '=', length) == NULL) {
        nupp_fail("environment entry has no '='");
        return false;
    }
    if (!strings_push(&request->env, text, length)) {
        request->failed = true;
        nupp_fail("out of memory");
        return false;
    }
    return true;
}

NUPP_EXPORT bool nuppProcessSpawnClearEnv(NuppSpawn *request, bool clear) {
    if (request == NULL) {
        return false;
    }
    request->clearEnv = clear;
    return true;
}

NUPP_EXPORT bool nuppProcessSpawnCwd(
    NuppSpawn *request, const uint8_t *text, size_t length
) {
    char *copy;
    if (request == NULL || (text == NULL && length != 0)) {
        return false;
    }
    copy = malloc(length + 1);
    if (copy == NULL) {
        request->failed = true;
        nupp_fail("out of memory");
        return false;
    }
    if (length != 0) {
        memcpy(copy, text, length);
    }
    copy[length] = '\0';
    free(request->cwd);
    request->cwd = copy;
    return true;
}

NUPP_EXPORT bool nuppProcessSpawnStdio(NuppSpawn *request, uint8_t which, uint8_t mode) {
    if (request == NULL || which > 2 || mode > NUPP_MODE_STDOUT
        || (mode == NUPP_MODE_STDOUT && which != 2)) {
        return false;
    }
    request->modes[which] = mode;
    return true;
}

static void spawn_free(NuppSpawn *request) {
    strings_free(&request->args);
    strings_free(&request->env);
    free(request->cwd);
    free(request);
}

NUPP_EXPORT void nuppProcessSpawnCancel(NuppSpawn *request) {
    if (request != NULL) {
        spawn_free(request);
    }
}

/* --- running ------------------------------------------------------------ */

/* libuv keeps the handle until the loop has finished closing it, which is not
 * the same turn uv_close was called on. The allocation is therefore released
 * here rather than by whoever asked for it, exactly as a stream's is. */
static void on_child_closed(uv_handle_t *handle) {
    NuppChild *child = handle->data;
    child->closed = true;
    if (child->destroyed) {
        free(child);
    }
}

static void on_process_exit(uv_process_t *process, int64_t status, int signal) {
    NuppChild *child = process->data;
    child->hasExit = true;
    /* A signal leaves no exit code of its own. 128 plus the signal is what a
     * shell reports, and what this ABI's callers already read. */
    child->killed = signal != 0;
    child->code = signal != 0 ? (int32_t)(128 + signal) : (int32_t)status;
    if (child->spawnFailed) {
        child->reaped = true;
        uv_close((uv_handle_t *)&child->process, on_child_closed);
    }
}

static NuppStream *new_stream(uv_loop_t *where, bool readable) {
    NuppStream *stream = calloc(1, sizeof *stream);
    if (stream == NULL) {
        return NULL;
    }
    if (uv_pipe_init(where, &stream->pipe, 0) != 0) {
        free(stream);
        return NULL;
    }
    stream->pipe.data = stream;
    stream->readable = readable;
    return stream;
}

/* The environment the child receives. Entries modify rather than replace unless
 * the request cleared first, which is what makes "run this with one variable
 * set" a one-line request rather than a copy of everything the host holds. */
static char **build_environment(NuppSpawn *request, Strings *out) {
    uv_env_item_t *inherited = NULL;
    int count = 0;
    int at;
    size_t which;

    if (!request->clearEnv && uv_os_environ(&inherited, &count) == 0) {
        for (at = 0; at < count; at++) {
            bool replaced = false;
            size_t nameLength = strlen(inherited[at].name);
            for (which = 0; which < request->env.count; which++) {
                if (strncmp(request->env.items[which], inherited[at].name, nameLength) == 0
                    && request->env.items[which][nameLength] == '=') {
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                NuppBuffer entry;
                nupp_buffer_init(&entry);
                nupp_buffer_append(&entry, inherited[at].name, nameLength);
                nupp_buffer_push(&entry, '=');
                nupp_buffer_append(&entry, inherited[at].value,
                    strlen(inherited[at].value));
                if (!entry.failed) {
                    strings_push(out, entry.data, entry.length);
                }
                nupp_buffer_free(&entry);
            }
        }
        uv_os_free_environ(inherited, count);
    }
    for (which = 0; which < request->env.count; which++) {
        strings_push(out, (const uint8_t *)request->env.items[which],
            strlen(request->env.items[which]));
    }
    /* No entries and no clearing means inherit, which libuv spells as NULL. */
    if (out->count == 0 && !request->clearEnv) {
        return NULL;
    }
    return out->items;
}

NUPP_EXPORT NuppChild *nuppProcessSpawnRun(NuppSpawn *request) {
    uv_process_options_t options;
    uv_stdio_container_t stdio[3];
    Strings environment;
    NuppChild *child;
    uv_loop_t *where = loop();
    uv_file childWriteEnd = -1;
    size_t which;
    int started;
    bool processInitialized = false;

    if (request == NULL) {
        nupp_fail("no spawn request");
        return NULL;
    }
    if (request->failed || where == NULL) {
        spawn_free(request);
        return NULL;
    }
    if (request->args.count == 0) {
        spawn_free(request);
        nupp_fail("a spawn needs a program to run");
        return NULL;
    }

    child = calloc(1, sizeof *child);
    if (child == NULL) {
        spawn_free(request);
        nupp_fail("out of memory");
        return NULL;
    }
    memset(&options, 0, sizeof options);
    memset(stdio, 0, sizeof stdio);
    memset(&environment, 0, sizeof environment);

    /* Joining the child's stderr onto a stdout pipe cannot be asked of
     * uv_spawn: it makes one pipe per slot, and naming the same handle twice
     * would have it make two. The pipe is made here instead and inherited into
     * both descriptors, which is the one arrangement that gives the child a
     * single destination and this process a single end to read. */
    if (request->modes[2] == NUPP_MODE_STDOUT
        && request->modes[1] == NUPP_MODE_PIPE) {
        uv_file pair[2];
        int made = uv_pipe(pair, UV_NONBLOCK_PIPE, 0);
        if (made != 0) {
            fail_uv("cannot create a pipe for the child", made);
            free(child);
            spawn_free(request);
            return NULL;
        }
        child->ends[1] = new_stream(where, true);
        if (child->ends[1] == NULL || uv_pipe_open(&child->ends[1]->pipe, pair[0]) != 0) {
            uv_fs_t closing;
            uv_fs_close(NULL, &closing, pair[0], NULL);
            uv_fs_req_cleanup(&closing);
            uv_fs_close(NULL, &closing, pair[1], NULL);
            uv_fs_req_cleanup(&closing);
            nupp_fail("cannot create a pipe for the child");
            goto refuse;
        }
        childWriteEnd = pair[1];
        child->merged = true;
    }

    for (which = 0; which < 3; which++) {
        /* Both of the child's output descriptors are the inherited write end. */
        if (child->merged && (which == 1 || which == 2)) {
            stdio[which].flags = UV_INHERIT_FD;
            stdio[which].data.fd = childWriteEnd;
            continue;
        }
        switch (request->modes[which]) {
            case NUPP_MODE_PIPE:
                child->ends[which] = new_stream(where, which != 0);
                if (child->ends[which] == NULL) {
                    nupp_fail("out of memory");
                    goto refuse;
                }
                stdio[which].flags = UV_CREATE_PIPE
                    | (which == 0 ? UV_READABLE_PIPE : UV_WRITABLE_PIPE);
                stdio[which].data.stream = (uv_stream_t *)&child->ends[which]->pipe;
                break;
            case NUPP_MODE_INHERIT:
                stdio[which].flags = UV_INHERIT_FD;
                stdio[which].data.fd = (int)which;
                break;
            case NUPP_MODE_STDOUT:
                /* The pipe case was arranged above. What is left is stdout
                 * going somewhere this process did not make. */
                if (request->modes[1] == NUPP_MODE_INHERIT) {
                    /* Inheriting is per descriptor, and the child's stderr
                     * should reach stdout's destination rather than the slot of
                     * the same number. */
                    stdio[2].flags = UV_INHERIT_FD;
                    stdio[2].data.fd = 1;
                } else {
                    stdio[2].flags = UV_IGNORE;
                }
                break;
            default:
                stdio[which].flags = UV_IGNORE;
                break;
        }
    }

    options.exit_cb = on_process_exit;
    options.file = request->args.items[0];
    options.args = request->args.items;
    options.env = build_environment(request, &environment);
    options.cwd = request->cwd;
    options.stdio_count = 3;
    options.stdio = stdio;

    child->process.data = child;
    uv_once(&spawnGuardOnce, make_spawn_guard);
    uv_mutex_lock(&spawnGuard);
    started = uv_spawn(where, &child->process, &options);
    processInitialized = true;
    uv_mutex_unlock(&spawnGuard);
    strings_free(&environment);
    if (childWriteEnd >= 0) {
        uv_fs_t closing;
        uv_fs_close(NULL, &closing, childWriteEnd, NULL);
        uv_fs_req_cleanup(&closing);
    }
    if (started != 0) {
        fail_uv(request->args.items[0], started);
        goto refuse;
    }
    spawn_free(request);
    return child;

refuse:
    for (which = 0; which < 3; which++) {
        if (child->ends[which] != NULL) {
            child->ends[which]->destroyed = true;
            uv_close((uv_handle_t *)&child->ends[which]->pipe, on_closed);
        }
    }
    if (!processInitialized) {
        free(child);
    } else {
        /* uv_spawn initializes the process handle before it can report an
         * exec or stdio failure. That handle belongs to the loop even when it
         * is inactive, so freeing its enclosing allocation here leaves a
         * dangling handle in libuv's handle queue. A later child can reuse the
         * same memory and make the reaper wait on one pid through two handles.
         *
         * An inactive handle represents a child that never exec'd and can
         * close now. The rarer active case started the child before stdio
         * setup failed; end it, let the exit callback reap it, and close there.
         */
        child->destroyed = true;
        if (uv_is_active((uv_handle_t *)&child->process)) {
            child->spawnFailed = true;
            uv_process_kill(&child->process, SIGKILL);
        } else {
            child->reaped = true;
            uv_close((uv_handle_t *)&child->process, on_child_closed);
        }
        uv_run(where, UV_RUN_NOWAIT);
    }
    spawn_free(request);
    return NULL;
}

/* --- streams the caller takes ------------------------------------------- */

NUPP_EXPORT NuppStream *nuppProcessTakeStream(NuppChild *child, uint8_t which) {
    NuppStream *stream;
    if (child == NULL || which > 2) {
        return NULL;
    }
    /* Stderr joined to stdout has no stream of its own, and saying so is the
     * honest answer. */
    if (child->merged && which == 2) {
        return NULL;
    }
    stream = child->ends[which];
    if (stream == NULL) {
        return NULL;
    }
    child->ends[which] = NULL;
    if (stream->readable && !stream->started) {
        int begun = uv_read_start((uv_stream_t *)&stream->pipe, on_alloc, on_read);
        if (begun == 0) {
            stream->started = true;
        }
    }
    return stream;
}

/* Reads what has already arrived. Answers how many bytes landed, or would-block,
 * gone at end of stream, or failed. */
NUPP_EXPORT intptr_t nuppProcessTryRead(NuppStream *stream, uint8_t *buffer, size_t limit) {
    size_t ready;
    if (stream == NULL) {
        nupp_fail("no stream");
        return NUPP_FAILED;
    }
    if (buffer == NULL || limit == 0) {
        nupp_fail("a read needs room for at least one byte");
        return NUPP_FAILED;
    }
    if (!stream->readable) {
        nupp_fail("this stream is not readable");
        return NUPP_FAILED;
    }
    if (stream->closed || stream->destroyed) {
        nupp_fail("this stream has been closed");
        return NUPP_FAILED;
    }
    /* Whatever the loop has already delivered, without waiting for more. */
    uv_run(loop(), UV_RUN_NOWAIT);
    ready = stream->length - stream->offset;
    if (ready == 0) {
        if (stream->failure != 0) {
            fail_uv("cannot read from the child", stream->failure);
            return NUPP_FAILED;
        }
        return stream->ended ? NUPP_GONE : NUPP_WOULD_BLOCK;
    }
    if (ready > limit) {
        ready = limit;
    }
    memcpy(buffer, stream->buffer + stream->offset, ready);
    stream->offset += ready;
    if (stream->offset == stream->length) {
        stream->offset = 0;
        stream->length = 0;
    }
    return (intptr_t)ready;
}

/* Writes what the pipe will take. libuv's write completes asynchronously, so
 * the bytes are copied and reported accepted: from the caller's side they are
 * queued and will be delivered, which is what a pipe buffer would have done. */
NUPP_EXPORT intptr_t nuppProcessTryWrite(
    NuppStream *stream, const uint8_t *buffer, size_t length
) {
    uv_write_t *request;
    uv_buf_t payload;
    int queued;
    if (stream == NULL) {
        nupp_fail("no stream");
        return NUPP_FAILED;
    }
    if (buffer == NULL && length != 0) {
        nupp_fail("a write needs bytes to send");
        return NUPP_FAILED;
    }
    /* Failed rather than gone: gone is a claim about the far end, which a stream
     * this caller closed says nothing about. */
    if (stream->closed || stream->destroyed) {
        nupp_fail("this stream has been closed");
        return NUPP_FAILED;
    }
    if (stream->readable) {
        nupp_fail("this stream is not writable");
        return NUPP_FAILED;
    }
    if (length == 0) {
        return 0;
    }
    uv_run(loop(), UV_RUN_NOWAIT);
    if (stream->failure == UV_EPIPE || stream->failure == UV_ECONNRESET) {
        return NUPP_GONE;
    }
    if (stream->failure != 0) {
        fail_uv("cannot write to the child", stream->failure);
        return NUPP_FAILED;
    }
    if (stream->writing != 0) {
        return NUPP_WOULD_BLOCK;
    }
    if (length > 65536) {
        length = 65536;
    }
    if (length > stream->capacity) {
        uint8_t *grown = realloc(stream->buffer, length);
        if (grown == NULL) {
            nupp_fail("out of memory");
            return NUPP_FAILED;
        }
        stream->buffer = grown;
        stream->capacity = length;
    }
    memcpy(stream->buffer, buffer, length);
    request = calloc(1, sizeof *request);
    if (request == NULL) {
        nupp_fail("out of memory");
        return NUPP_FAILED;
    }
    request->data = stream;
    payload = uv_buf_init((char *)stream->buffer, (unsigned)length);
    stream->writing = length;
    queued = uv_write(request, (uv_stream_t *)&stream->pipe, &payload, 1, on_written);
    if (queued != 0) {
        stream->writing = 0;
        free(request);
        if (queued == UV_EPIPE) {
            return NUPP_GONE;
        }
        fail_uv("cannot write to the child", queued);
        return NUPP_FAILED;
    }
    return (intptr_t)length;
}

/* Closes one end. What is released is the pipe, and only that: the handle stays
 * valid, may still be named to a readiness wait, and answers released if closed
 * again. */
NUPP_EXPORT uint8_t nuppProcessCloseStream(NuppStream *stream) {
    if (stream == NULL) {
        nupp_fail("no stream");
        return NOT_RELEASED;
    }
    if (!stream->closed && !uv_is_closing((uv_handle_t *)&stream->pipe)) {
        if (stream->started) {
            uv_read_stop((uv_stream_t *)&stream->pipe);
            stream->started = false;
        }
        uv_close((uv_handle_t *)&stream->pipe, on_closed);
        uv_run(loop(), UV_RUN_NOWAIT);
    }
    return RELEASED;
}

/* Ends the handle itself. Closing ends the pipe and the allocation survives it;
 * destroying ends the allocation, and there is nothing left to speak to. */
NUPP_EXPORT void nuppProcessStreamDestroy(NuppStream *stream) {
    if (stream == NULL) {
        return;
    }
    /* Whoever finishes last frees, and only one of the two ever does.
     *
     * If the pipe has already finished closing there is no callback still to
     * come and this call owns the allocation. Otherwise the close callback owns
     * it, and it may run inside the turn below -- so nothing here may read the
     * stream again afterwards, not even to ask whether it was freed. */
    if (stream->closed) {
        free(stream->buffer);
        free(stream);
        return;
    }
    stream->destroyed = true;
    if (!uv_is_closing((uv_handle_t *)&stream->pipe)) {
        uv_close((uv_handle_t *)&stream->pipe, on_closed);
    }
    uv_run(loop(), UV_RUN_NOWAIT);
}

/* --- the child's end ---------------------------------------------------- */

NUPP_EXPORT int32_t nuppProcessPollExit(NuppChild *child, int32_t *code, bool *killed) {
    if (child == NULL) {
        nupp_fail("no child");
        return -1;
    }
    uv_run(loop(), UV_RUN_NOWAIT);
    if (!child->hasExit) {
        return 0;
    }
    if (code != NULL) {
        *code = child->code;
    }
    if (killed != NULL) {
        *killed = child->killed;
    }
    return 1;
}

NUPP_EXPORT uint32_t nuppProcessId(NuppChild *child) {
    return child != NULL ? (uint32_t)child->process.pid : 0;
}

NUPP_EXPORT bool nuppProcessKill(NuppChild *child, bool force) {
    int signalled;
    if (child == NULL) {
        nupp_fail("no child");
        return false;
    }
    /* Already ended, so there is nothing to signal and nothing wrong.
     * Signalling anyway would reach whatever now holds that id. */
    if (child->hasExit) {
        return true;
    }
    signalled = uv_process_kill(&child->process, force ? SIGKILL : SIGTERM);
    if (signalled == 0 || signalled == UV_ESRCH) {
        return true;
    }
    fail_uv("cannot signal the child", signalled);
    return false;
}

NUPP_EXPORT uint8_t nuppProcessReap(NuppChild *child) {
    if (child == NULL) {
        nupp_fail("no child");
        return NOT_RELEASED;
    }
    if (child->released) {
        return RELEASED;
    }
    if (!child->hasExit) {
        nupp_fail("the child has not ended, so there is nothing to reap");
        return NOT_RELEASED;
    }
    if (!child->reaped) {
        uv_close((uv_handle_t *)&child->process, on_child_closed);
        child->reaped = true;
        uv_run(loop(), UV_RUN_NOWAIT);
    }
    child->released = true;
    return RELEASED;
}

/* Releases a child handle. One let go without being reaped is the last resort:
 * signal once, look once, and count what is still unresolved. */
NUPP_EXPORT void nuppProcessDestroy(NuppChild *child) {
    size_t at;
    if (child == NULL) {
        return;
    }
    if (!child->released) {
        bool unsignalled = false;
        if (!child->hasExit) {
            unsignalled = uv_process_kill(&child->process, SIGKILL) != 0;
            uv_run(loop(), UV_RUN_NOWAIT);
        }
        if (!child->hasExit) {
            uncollected++;
            nupp_fail(unsignalled
                ? "an abandoned child could not be signalled, so it is still running"
                : "an abandoned child was signalled but had not ended, so it was left");
        }
    }
    /* The ends go first, while this handle is still not marked destroyed: each
     * of those turns the loop, and a turn taken after the mark could free the
     * child out from under this loop. */
    for (at = 0; at < 3; at++) {
        if (child->ends[at] != NULL) {
            nuppProcessStreamDestroy(child->ends[at]);
            child->ends[at] = NULL;
        }
    }
    /* Same division as a stream's: already closed means the callback has been
     * and gone, so this call frees; otherwise the callback will, possibly
     * inside the turn below. */
    if (child->closed) {
        free(child);
        return;
    }
    child->destroyed = true;
    if (!child->reaped) {
        uv_close((uv_handle_t *)&child->process, on_child_closed);
        child->reaped = true;
    }
    uv_run(loop(), UV_RUN_NOWAIT);
}

/* Waits until one of the named streams is ready, for at most `timeoutMs`.
 *
 * This is the loop's only bounded turn, and the caller decides when it happens:
 * a scheduler pumps it from its own frame, and a program with no scheduler uses
 * it as a sleep that ends early when something arrives. */
NUPP_EXPORT int32_t nuppProcessWaitReady(
    NuppStream *const *readable, size_t readableCount,
    NuppStream *const *writable, size_t writableCount,
    int32_t timeoutMs
) {
    uv_loop_t *where = loop();
    size_t at;
    int ready = 0;

    if ((readableCount != 0 && readable == NULL)
        || (writableCount != 0 && writable == NULL)) {
        nupp_fail("a readiness wait was given a count without streams");
        return -1;
    }
    for (at = 0; at < readableCount; at++) {
        if (readable[at] == NULL) {
            nupp_fail("a readiness wait was given a null stream inside its count");
            return -1;
        }
    }
    for (at = 0; at < writableCount; at++) {
        if (writable[at] == NULL) {
            nupp_fail("a readiness wait was given a null stream inside its count");
            return -1;
        }
    }
    if (where == NULL) {
        return 0;
    }

    /* Anything already in hand is ready now, and the loop need not be entered
     * at all. */
    for (at = 0; at < readableCount; at++) {
        NuppStream *stream = readable[at];
        if (stream->closed || stream->length > stream->offset || stream->ended
            || stream->failure != 0) {
            ready++;
        }
    }
    for (at = 0; at < writableCount; at++) {
        NuppStream *stream = writable[at];
        if (stream->closed || stream->writing == 0 || stream->failure != 0) {
            ready++;
        }
    }
    if (ready > 0) {
        uv_run(where, UV_RUN_NOWAIT);
        return ready;
    }

    /* A negative timeout is a deadline that has already passed, which asks for
     * no wait rather than an endless one. */
    uv_ref((uv_handle_t *)&childDeadline);
    uv_timer_start(&childDeadline, expired,
        timeoutMs < 0 ? 0 : (uint64_t)timeoutMs, 0);
    uv_run(where, UV_RUN_ONCE);
    uv_timer_stop(&childDeadline);
    uv_unref((uv_handle_t *)&childDeadline);

    for (at = 0; at < readableCount; at++) {
        NuppStream *stream = readable[at];
        if (stream->length > stream->offset || stream->ended || stream->failure != 0) {
            ready++;
        }
    }
    for (at = 0; at < writableCount; at++) {
        if (writable[at]->writing == 0 || writable[at]->failure != 0) {
            ready++;
        }
    }
    return (int32_t)ready;
}
