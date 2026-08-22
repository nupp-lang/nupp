/* Child processes: spawning them, moving bytes to and from them, and reaping
 * them.
 *
 * Everything here is bookkeeping around the platform primitives in
 * `platform_posix.c` and `platform_windows.c`. What it owns is the shape of the
 * ABI: a spawn is described field by field because the caller is across a C
 * boundary and cannot hand over a struct, a stream's descriptor and its handle
 * have separate lifetimes, and a child's exit is remembered because the platform
 * gives a status up when it is collected.
 */

#include "platform.h"

#include <stdlib.h>
#include <string.h>

/* How a release went, in the seam's own terms. */
#define RELEASED 0
/* Released, and the platform had something to say about it. */
#define RELEASED_WITH_REASON 1
/* Still the caller's, and worth another attempt. */
#define NOT_RELEASED 2

/* --- growable string vectors -------------------------------------------- */

/* A NULL-terminated array of owned strings, which is what both platforms want a
 * command line and an environment as. */
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

/* --- the handles -------------------------------------------------------- */

/* One end of a pipe to a child, and whether this process has given it up.
 *
 * Two lifetimes here, and they are not the same one. The descriptor is released
 * by `nuppProcessCloseStream`, after which this handle is still perfectly alive:
 * it may be named to a readiness wait, asked its state, or closed again. The
 * handle ends only at `nuppProcessStreamDestroy`, and naming it after that reads
 * freed memory.
 */
struct NuppStream {
    NuppPipeEnd *end;
    bool readable;
    bool writable;
};

typedef struct NuppStream NuppStream;

/* A child, and the exit it has been seen to reach.
 *
 * The exit is remembered because the platform gives a status up when it is
 * collected, and a second ask reports no such child. */
struct NuppChild {
    NuppSpawnResult spawned;
    bool hasExit;
    int32_t code;
    bool killed;
    bool released;
};

typedef struct NuppChild NuppChild;

/* A spawn being described. Built up field by field because the caller is on the
 * other side of a C boundary and cannot hand over a struct. */
struct NuppSpawn {
    Strings args;
    Strings env;
    char *cwd;
    bool clearEnv;
    uint8_t modes[3];
    bool failed;
};

typedef struct NuppSpawn NuppSpawn;

/* --- the clock ---------------------------------------------------------- */

/* Milliseconds on a process-local monotonic clock. The zero is arbitrary:
 * deadlines only subtract readings, so an epoch with no wall-clock meaning is
 * exactly what they need. */
NUPP_EXPORT double nuppProcessMonotonicMs(void) {
    return nupp_monotonic_ms();
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

/* Adds one argument. The first is the program, resolved through `PATH`. */
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

/* Adds one `KEY=VALUE`. The whole environment is built this way, including the
 * inherited one: there is no spelling for "inherit" once a child is being
 * described entry by entry, so every case is the same case. */
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

/* Starts the child's environment from nothing rather than from this process's.
 *
 * Separate from adding entries, because otherwise the two questions collapse:
 * "cleared, with nothing in it" and "inherit" would be the same request, and one
 * of them would be unaskable. */
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

/* How one of the child's three standard streams is connected. `which` is 0, 1 or
 * 2; joining to stdout is stderr's alone. */
NUPP_EXPORT bool nuppProcessSpawnStdio(NuppSpawn *request, uint8_t which, uint8_t mode) {
    if (request == NULL) {
        return false;
    }
    if (which > 2 || mode > NUPP_MODE_STDOUT
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

/* Abandons a request that will not be run. */
NUPP_EXPORT void nuppProcessSpawnCancel(NuppSpawn *request) {
    if (request != NULL) {
        spawn_free(request);
    }
}

/* Runs a request, consuming it. Answers the child, or NULL with the reason in
 * the error slot. */
NUPP_EXPORT NuppChild *nuppProcessSpawnRun(NuppSpawn *request) {
    NuppSpawnRequest platform;
    NuppChild *child;

    if (request == NULL) {
        nupp_fail("no spawn request");
        return NULL;
    }
    if (request->failed) {
        spawn_free(request);
        return NULL;
    }
    if (request->args.count == 0) {
        spawn_free(request);
        nupp_fail("a spawn needs a program to run");
        return NULL;
    }

    memset(&platform, 0, sizeof platform);
    platform.argv = request->args.items;
    /* An environment described entry by entry replaces this process's; one that
     * was not described at all is inherited, and `clearEnv` is what separates
     * "inherit" from "cleared and left empty". */
    platform.envp = (request->env.count != 0 || request->clearEnv)
        ? request->env.items : NULL;
    platform.clearEnv = request->clearEnv;
    platform.cwd = request->cwd;
    memcpy(platform.modes, request->modes, sizeof platform.modes);

    child = calloc(1, sizeof *child);
    if (child == NULL) {
        spawn_free(request);
        nupp_fail("out of memory");
        return NULL;
    }
    if (!nupp_spawn(&platform, &child->spawned)) {
        free(child);
        spawn_free(request);
        return NULL;
    }
    spawn_free(request);
    return child;
}

/* --- streams ------------------------------------------------------------ */

static NuppStream *wrap_end(NuppPipeEnd *end, bool readable) {
    NuppStream *stream = calloc(1, sizeof *stream);
    if (stream == NULL) {
        nupp_pipe_destroy(end);
        nupp_fail("out of memory");
        return NULL;
    }
    stream->end = end;
    stream->readable = readable;
    stream->writable = !readable;
    return stream;
}

/* Takes one of the child's piped streams, handing over the obligation to close
 * it. Answers NULL for a stream that was not piped, or one already taken.
 *
 * `which` is 0 for stdin, 1 for stdout, 2 for stderr. */
NUPP_EXPORT NuppStream *nuppProcessTakeStream(NuppChild *child, uint8_t which) {
    NuppPipeEnd *end;
    if (child == NULL || which > 2) {
        return NULL;
    }
    /* Where stderr was joined onto stdout there is one pipe with one reader, and
     * stdout is who answers for it. Stderr answering nothing is the honest
     * report that it has no stream of its own -- handing the same end back under
     * two names would be two owners of one descriptor. */
    if (child->spawned.merged && which == 2) {
        return NULL;
    }
    end = child->spawned.ends[which];
    if (end == NULL) {
        return NULL;
    }
    child->spawned.ends[which] = NULL;
    return wrap_end(end, which != 0);
}

/* Reads up to `limit` bytes without waiting.
 *
 * Answers how many landed, or would-block, gone at end of stream, or failed. */
NUPP_EXPORT intptr_t nuppProcessTryRead(NuppStream *stream, uint8_t *buffer, size_t limit) {
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
    if (nupp_pipe_is_closed(stream->end)) {
        nupp_fail("this stream has been closed");
        return NUPP_FAILED;
    }
    return nupp_pipe_read(stream->end, buffer, limit);
}

/* Writes what the pipe will take without waiting.
 *
 * Answers how many bytes went, or would-block, gone when nobody is reading and
 * nobody will, or failed. The two zeroes a naive interface conflates -- no room
 * yet, no reader ever -- are the whole reason gone is answered separately. */
NUPP_EXPORT intptr_t nuppProcessTryWrite(
    NuppStream *stream, const uint8_t *buffer, size_t length
) {
    if (stream == NULL) {
        nupp_fail("no stream");
        return NUPP_FAILED;
    }
    if (buffer == NULL && length != 0) {
        nupp_fail("a write needs bytes to send");
        return NUPP_FAILED;
    }
    /* Failed rather than gone, and that is the whole point of the check. Gone is
     * a claim about the far end -- nobody is reading this and nobody will --
     * which a stream this caller closed says nothing about. */
    if (nupp_pipe_is_closed(stream->end)) {
        nupp_fail("this stream has been closed");
        return NUPP_FAILED;
    }
    if (!stream->writable) {
        nupp_fail("this stream is not writable");
        return NUPP_FAILED;
    }
    if (length == 0) {
        return 0;
    }
    return nupp_pipe_write(stream->end, buffer, length);
}

/* Closes one end.
 *
 * What is released is the descriptor, and only that. The handle stays valid
 * afterwards -- a readiness wait may still name it, and calling this again
 * answers released without troubling the platform -- but it carries no more
 * bytes. Neither answers gone, and that matters: gone is a fact about the far
 * end, and a stream this caller closed says nothing whatever about the child's
 * end of it. */
NUPP_EXPORT uint8_t nuppProcessCloseStream(NuppStream *stream) {
    if (stream == NULL) {
        nupp_fail("no stream");
        return NOT_RELEASED;
    }
    nupp_pipe_close(stream->end);
    return RELEASED;
}

/* Ends the handle itself. The descriptor is closed first if it still holds one.
 *
 * The two are not degrees of the same act. Closing ends the descriptor, and what
 * survives it is the allocation, so the handle can still be spoken to and the
 * answers stay sensible. Destroying ends the allocation, and there is nothing
 * left to speak to. */
NUPP_EXPORT void nuppProcessStreamDestroy(NuppStream *stream) {
    if (stream != NULL) {
        nupp_pipe_destroy(stream->end);
        free(stream);
    }
}

/* --- the child ---------------------------------------------------------- */

/* How many children were still unaccounted for when their handles were let go.
 *
 * Total in the name because that is what it is: an event count that only ever
 * rises, not a gauge of anything current. A host watching this climb is watching
 * its own callers leak handles. */
static size_t uncollected;

NUPP_EXPORT size_t nuppProcessUncollectedTotal(void) {
    return uncollected;
}

/* Asks after the child without waiting.
 *
 * Answers 1 when it has ended, filling in the status and whether a signal ended
 * it; 0 while it still runs; -1 on failure. */
NUPP_EXPORT int32_t nuppProcessPollExit(NuppChild *child, int32_t *code, bool *killed) {
    if (child == NULL) {
        nupp_fail("no child");
        return -1;
    }
    if (!child->hasExit) {
        int32_t answeredCode = 0;
        bool answeredKilled = false;
        int step = nupp_child_poll(&child->spawned, &answeredCode, &answeredKilled);
        if (step < 0) {
            return -1;
        }
        if (step == 0) {
            return 0;
        }
        child->hasExit = true;
        child->code = answeredCode;
        child->killed = answeredKilled;
    }
    if (code != NULL) {
        *code = child->code;
    }
    if (killed != NULL) {
        *killed = child->killed;
    }
    return 1;
}

/* The child's process id, for a caller that has to name it to something else. */
NUPP_EXPORT uint32_t nuppProcessId(NuppChild *child) {
    return child != NULL ? (uint32_t)child->spawned.id : 0;
}

/* Asks the child to end, or insists. */
NUPP_EXPORT bool nuppProcessKill(NuppChild *child, bool force) {
    if (child == NULL) {
        nupp_fail("no child");
        return false;
    }
    if (child->hasExit) {
        /* Already ended, so there is nothing to signal and nothing wrong.
         * Signalling anyway would reach whatever now holds that id. */
        return true;
    }
    return nupp_child_kill(&child->spawned, force);
}

/* Releases the child once it has ended.
 *
 * An id is reused as readily as a descriptor, so the caller has to be told
 * whether this one is still theirs to ask about. */
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
    nupp_child_release(&child->spawned);
    child->released = true;
    return RELEASED;
}

/* Releases a child handle.
 *
 * A handle let go without being reaped is the last resort, and its job is to
 * make that failure cheap and visible rather than to repair it: signal once,
 * look once, and count what is still unresolved. Nothing more, because this runs
 * during whatever the host was doing and none of it may be made to wait on
 * another process.
 *
 * Insisting rather than asking, because there is nobody left to wait politely:
 * the handle is going away this instant, and a child given the chance to clean
 * up would simply be unowned instead. */
NUPP_EXPORT void nuppProcessDestroy(NuppChild *child) {
    size_t at;
    if (child == NULL) {
        return;
    }
    if (!child->released) {
        bool unsignalled = false;
        if (!child->hasExit) {
            unsignalled = !nupp_child_kill(&child->spawned, true);
        }
        {
            int32_t code = 0;
            bool killed = false;
            if (nupp_child_poll(&child->spawned, &code, &killed) != 1) {
                uncollected++;
                nupp_fail(unsignalled
                    ? "an abandoned child could not be signalled, so it is still running"
                    : "an abandoned child was signalled but had not ended, so it was left");
            }
        }
        nupp_child_release(&child->spawned);
    }
    /* Any end the caller never took is this handle's to close. */
    for (at = 0; at < 3; at++) {
        nupp_pipe_destroy(child->spawned.ends[at]);
    }
    free(child);
}

/* Waits until one of the named streams is ready, for at most `timeoutMs`.
 *
 * The streams are named by their own handles rather than by descriptors,
 * because a descriptor is a POSIX idea: a Win32 handle is pointer-sized and
 * would not fit the array a descriptor implies, and readiness there may be an
 * event object rather than the pipe at all.
 *
 * A stream already closed is skipped rather than refused: a drain loop naturally
 * still names one it has finished with. A null entry inside the count is
 * refused, because skipping would turn a binding that built its array wrongly
 * into a wait that quietly watched fewer things than asked. */
NUPP_EXPORT int32_t nuppProcessWaitReady(
    NuppStream *const *readable, size_t readableCount,
    NuppStream *const *writable, size_t writableCount,
    int32_t timeoutMs
) {
    NuppPipeEnd **readEnds = NULL;
    NuppPipeEnd **writeEnds = NULL;
    size_t at;
    int answered;

    if ((readableCount != 0 && readable == NULL)
        || (writableCount != 0 && writable == NULL)) {
        nupp_fail("a readiness wait was given a count without streams");
        return -1;
    }
    if (readableCount != 0) {
        readEnds = malloc(readableCount * sizeof *readEnds);
        if (readEnds == NULL) {
            nupp_fail("out of memory");
            return -1;
        }
    }
    if (writableCount != 0) {
        writeEnds = malloc(writableCount * sizeof *writeEnds);
        if (writeEnds == NULL) {
            free(readEnds);
            nupp_fail("out of memory");
            return -1;
        }
    }
    for (at = 0; at < readableCount; at++) {
        if (readable[at] == NULL) {
            free(readEnds);
            free(writeEnds);
            nupp_fail("a readiness wait was given a null stream inside its count");
            return -1;
        }
        readEnds[at] = readable[at]->end;
    }
    for (at = 0; at < writableCount; at++) {
        if (writable[at] == NULL) {
            free(readEnds);
            free(writeEnds);
            nupp_fail("a readiness wait was given a null stream inside its count");
            return -1;
        }
        writeEnds[at] = writable[at]->end;
    }
    answered = nupp_pipe_wait(
        readEnds, readableCount, writeEnds, writableCount, timeoutMs);
    free(readEnds);
    free(writeEnds);
    return (int32_t)answered;
}
