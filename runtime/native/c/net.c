/* Network sockets, on libuv.
 *
 * Binding, listening, connecting, reading, writing and half-closing are
 * libuv's. What is left here is the shape adaptation: libuv pushes bytes at a
 * callback where this ABI answers a count, so what arrives is buffered and
 * drained by `tryRead`, exactly as a child's stream already is.
 *
 * A reactor per lane rather than one for the process. A loop is created by
 * whoever will drive it and never shared, because a libuv loop is not
 * thread-safe and worker lanes are threads. The Rust process provider has its
 * own shared executor and is deliberately not coupled to this loop. Every handle
 * belongs to the loop it was made on, which is also what `uv_accept` requires.
 *
 * Nothing here calls Lua. Progress lands in buffers and counters that the Lua
 * side reads when it chooses, which is what lets one caller wait by blocking
 * and another by parking a task and pumping this from its frame.
 */

#include "nupp_native.h"
#include "nupp_net.h"

#include <uv.h>

#include <stdlib.h>
#include <string.h>
#if defined(__linux__)
#include <unistd.h>
#endif

/* Ceilings, because a queue that grows with its peers eventually takes the
 * process with it. The accept backlog is what libuv is told; the pending queue
 * is what this file holds for a caller that has not accepted yet. */
#define NET_ACCEPT_QUEUE_MAX 1024
#define NET_READ_CHUNK 65536

/* How much may sit received-but-unread before this stops asking for more.
 *
 * Without it a peer that sends faster than the program reads grows this
 * process's memory for as long as anything drives the reactor, which is a
 * remote party choosing how much memory to spend. libuv stops delivering when
 * reads are stopped and the kernel's own window then closes behind it, so the
 * backpressure reaches the sender rather than stopping at this buffer. */
#define NET_RECEIVE_HIGH_WATER (1024 * 1024)

/* --- the loop ----------------------------------------------------------- */

/* One reactor. `deadline` is armed only to bound a blocking wait, so it has no
 * work of its own; `uv_timer_start` refuses a null callback and a refused timer
 * would leave that wait unbounded. */
struct NuppNetLoop {
    uv_loop_t loop;
    uv_timer_t deadline;
    bool deadlineOpen;
};

typedef struct NuppNetLoop NuppNetLoop;

static void net_expired(uv_timer_t *timer) {
    (void)timer;
}

NUPP_EXPORT NuppNetLoop *nuppNetLoopCreate(void) {
    NuppNetLoop *reactor = calloc(1, sizeof *reactor);
    if (reactor == NULL) {
        nupp_fail("net: out of memory");
        return NULL;
    }
    if (uv_loop_init(&reactor->loop) != 0) {
        free(reactor);
        nupp_fail("net: the event loop could not be created");
        return NULL;
    }
    if (uv_timer_init(&reactor->loop, &reactor->deadline) != 0) {
        uv_loop_close(&reactor->loop);
        free(reactor);
        nupp_fail("net: the event loop timer could not be created");
        return NULL;
    }
    reactor->deadline.data = reactor;
    reactor->deadlineOpen = true;
    return reactor;
}

/* Drives the loop once. A non-positive timeout polls and returns whatever is
 * ready now; a positive one blocks for at most that many milliseconds. The
 * answer is how many handles remain active, which is what tells a caller
 * whether anything in this reactor can still make progress. */
NUPP_EXPORT int32_t nuppNetLoopRun(NuppNetLoop *reactor, int32_t timeoutMs) {
    if (reactor == NULL) {
        return 0;
    }
    if (timeoutMs > 0) {
        /* Timer deadlines are relative to libuv's cached clock. Refresh it
         * after caller work that may have run without pumping this loop, or a
         * newly armed timeout can already be in the past on the first run. */
        uv_update_time(&reactor->loop);
        uv_timer_start(&reactor->deadline, net_expired, (uint64_t)timeoutMs, 0);
        uv_run(&reactor->loop, UV_RUN_ONCE);
        uv_timer_stop(&reactor->deadline);
    } else {
        uv_run(&reactor->loop, UV_RUN_NOWAIT);
    }
    return (int32_t)uv_loop_alive(&reactor->loop);
}

static void net_loop_closed(uv_handle_t *handle) {
    NuppNetLoop *reactor = handle->data;
    reactor->deadlineOpen = false;
}

/* Every handle this loop owns must have finished closing before the loop can
 * be. A caller that still holds a listener or a stream destroys those first;
 * what is left here is this file's own timer, and the run below is what lets
 * libuv finish with it. */
NUPP_EXPORT void nuppNetLoopDestroy(NuppNetLoop *reactor) {
    if (reactor == NULL) {
        return;
    }
    if (reactor->deadlineOpen) {
        uv_timer_stop(&reactor->deadline);
        uv_close((uv_handle_t *)&reactor->deadline, net_loop_closed);
    }
    while (reactor->deadlineOpen) {
        uv_run(&reactor->loop, UV_RUN_ONCE);
    }
    uv_run(&reactor->loop, UV_RUN_NOWAIT);
    uv_loop_close(&reactor->loop);
    free(reactor);
}

/* Either kind of stream this file serves. A Unix socket is `uv_pipe_t` and a
 * TCP one is `uv_tcp_t`; both are a `uv_stream_t` where it matters, which is
 * reading, writing, half-closing, accepting and closing -- everything except
 * how they are bound. Keeping them in one union is what lets the rest of this
 * file be written once. */
typedef union {
    uv_tcp_t tcp;
    uv_pipe_t pipe;
} NetHandle;

/* An address as text and a port, for whichever side is being asked about.
 * Answers false for an address there is none of, which is what a Unix socket
 * has: a filesystem name is not a peer address, and inventing one for it would
 * be a plausible-looking wrong answer. */
static bool net_address_text(
    const struct sockaddr *from,
    char *host,
    size_t capacity,
    int32_t *port
) {
    if (host != NULL && capacity > 0) {
        host[0] = '\0';
    }
    if (from == NULL) {
        return false;
    }
    if (from->sa_family == AF_INET6) {
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)from;
        uv_ip6_name(in6, host, capacity);
        if (port != NULL) {
            *port = (int32_t)ntohs(in6->sin6_port);
        }
        return true;
    }
    if (from->sa_family == AF_INET) {
        const struct sockaddr_in *in4 = (const struct sockaddr_in *)from;
        uv_ip4_name(in4, host, capacity);
        if (port != NULL) {
            *port = (int32_t)ntohs(in4->sin_port);
        }
        return true;
    }
    return false;
}

/* --- streams ------------------------------------------------------------ */

/* One connected socket, and whether this process has given it up.
 *
 * Two lifetimes, and they are not the same one. `closeStream` releases the
 * socket, after which this handle is still alive: it may be asked its state or
 * closed again. The handle ends at `streamDestroy`, and the allocation is freed
 * by whichever of the two happens last, because libuv keeps a pointer to a
 * handle until its close callback has run.
 */
struct NuppNetStream {
    NetHandle socket;
    bool isPipe;
    bool started;
    bool paused;
    bool closing;
    bool closed;
    bool destroyed;
    bool ended;
    bool wrote;
    bool layered;

    /* A shutdown in libuv's hands. Not counted in `pending`, which is bytes:
     * the request carries none, so a caller waiting for the queue to empty
     * would be told the direction had ended while the alert was still
     * unsubmitted, and closing the connection would cancel it. */
    bool shuttingDown;

    int failure;

    /* Holders beyond the owner. A module layering over a connection -- TLS --
     * keeps this pointer and asks whether the connection is still open, which
     * it may do after the owner has released it. Without a count that question
     * reads freed memory: the guard meant to catch a session outliving its
     * connection would be the very fault it was watching for. */
    unsigned holders;

    uint8_t *buffer;
    size_t length;
    size_t offset;
    size_t capacity;

    /* Bytes handed to libuv and not yet reported written. This is what
     * `pending` answers, and it is a local fact: the kernel has taken them,
     * which says nothing about the peer having read them. */
    size_t pending;
};

typedef struct NuppNetStream NuppNetStream;

/* Freed once libuv has finished with the handle, the owner has let go, and no
 * layered holder is left. Any of the three may be last. */
static void net_stream_reap(NuppNetStream *stream) {
    if (!stream->closed || !stream->destroyed || stream->holders > 0) {
        return;
    }
    free(stream->buffer);
    free(stream);
}

static void net_stream_closed(uv_handle_t *handle) {
    NuppNetStream *stream = handle->data;
    stream->closed = true;
    net_stream_reap(stream);
}

/* Taken by a module that layers over this connection, so that asking about it
 * stays safe after the owner has released it. */
NUPP_EXPORT void nuppNetStreamRetain(NuppNetStream *stream) {
    if (stream != NULL) {
        stream->holders++;
    }
}

NUPP_EXPORT void nuppNetStreamRelease(NuppNetStream *stream) {
    if (stream == NULL || stream->holders == 0) {
        return;
    }
    stream->holders--;
    net_stream_reap(stream);
}

static void net_on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
    NuppNetStream *stream = handle->data;
    size_t wanted;
    /* Consumed bytes are moved out of the way before deciding to grow.
     * Otherwise the buffer only shrinks when it happens to be drained to
     * exactly empty, and a parser that always leaves a partial record behind
     * grows it with the total traffic of the connection rather than with what
     * is unread. */
    if (stream->offset > 0) {
        size_t held = stream->length - stream->offset;
        if (held > 0) {
            memmove(stream->buffer, stream->buffer + stream->offset, held);
        }
        stream->length = held;
        stream->offset = 0;
    }
    wanted = stream->length + (suggested > 0 ? suggested : NET_READ_CHUNK);
    if (wanted > stream->capacity) {
        size_t next = stream->capacity < NET_READ_CHUNK ? NET_READ_CHUNK : stream->capacity;
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

static void net_on_read(uv_stream_t *handle, ssize_t got, const uv_buf_t *buffer) {
    NuppNetStream *stream = ((uv_handle_t *)handle)->data;
    (void)buffer;
    if (got > 0) {
        stream->length += (size_t)got;
        if (stream->length - stream->offset >= NET_RECEIVE_HIGH_WATER) {
            uv_read_stop(handle);
            stream->started = false;
            stream->paused = true;
        }
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

static NuppNetStream *net_stream_new(uv_loop_t *where, bool isPipe) {
    NuppNetStream *stream = calloc(1, sizeof *stream);
    int started;
    if (stream == NULL) {
        return NULL;
    }
    stream->isPipe = isPipe;
    started = isPipe
        ? uv_pipe_init(where, &stream->socket.pipe, 0)
        : uv_tcp_init(where, &stream->socket.tcp);
    if (started != 0) {
        free(stream);
        return NULL;
    }
    ((uv_handle_t *)&stream->socket)->data = stream;
    return stream;
}

/* Reading starts when the first read is asked for rather than at accept, so a
 * caller that accepts many connections and services them in turn is not paying
 * for buffers on every one of them before it has looked at any. */
static void net_stream_reading(NuppNetStream *stream) {
    if (stream->started || stream->closing || stream->ended || stream->failure != 0) {
        return;
    }
    /* Held bytes are the reason reading stopped, so reading may not resume
     * until they have been taken. Checking here rather than at the resume site
     * is what makes every path back into reading obey the same bound. */
    if (stream->length - stream->offset >= NET_RECEIVE_HIGH_WATER) {
        stream->paused = true;
        return;
    }
    if (uv_read_start((uv_stream_t *)&stream->socket, net_on_alloc, net_on_read) == 0) {
        stream->started = true;
        stream->paused = false;
    }
}

/* Drains what has arrived. A zero answer means nothing has arrived yet, which
 * is not the same as the end: `nuppNetStreamEnded` is the fact that says the
 * peer closed its sending half, and the binding is what keeps the two apart. */
NUPP_EXPORT intptr_t nuppNetTryRead(NuppNetStream *stream, uint8_t *into, size_t wanted) {
    size_t have;
    size_t taking;
    if (stream == NULL || into == NULL) {
        nupp_fail("net: read needs a stream and a destination");
        return -1;
    }
    if (stream->closing) {
        nupp_fail("net: the stream is closed");
        return -1;
    }
    if (stream->layered) {
        nupp_fail("net: the stream is owned by kernel TLS");
        return -1;
    }
    net_stream_reading(stream);
    have = stream->length - stream->offset;
    if (have == 0) {
        if (stream->failure != 0) {
            nupp_fail_format("net: %s", uv_strerror(stream->failure));
            return -1;
        }
        return 0;
    }
    taking = wanted < have ? wanted : have;
    memcpy(into, stream->buffer + stream->offset, taking);
    stream->offset += taking;
    if (stream->offset == stream->length) {
        stream->offset = 0;
        stream->length = 0;
    }
    /* Room again, so ask for more. Done after the drain rather than before it,
     * because before it the bound is being read against the buffer as it was. */
    if (stream->paused) {
        net_stream_reading(stream);
    }
    return (intptr_t)taking;
}

/* Whether this side has released the connection.
 *
 * Asked by a module layering over one, which needs to know without holding the
 * owner: reaching for the owner to ask would mean casting it back from an
 * opaque value, and a cast from `any` to an affine record is an owned value the
 * affine layer will close at the end of the scope that made it. That is a
 * socket released underneath whoever actually owns it, and the question was
 * only ever "is this still open".
 */
NUPP_EXPORT bool nuppNetStreamClosed(NuppNetStream *stream) {
    return stream == NULL || stream->closing;
}

/* Whether a write this stream accepted later failed.
 *
 * A failed write leaves nothing pending, so a caller waiting for the queue to
 * empty would otherwise see success at the exact moment the bytes were lost. */
NUPP_EXPORT bool nuppNetStreamFailed(NuppNetStream *stream) {
    return stream != NULL && stream->failure != 0;
}

NUPP_EXPORT bool nuppNetStreamEnded(NuppNetStream *stream) {
    return stream != NULL
        && stream->ended
        && stream->length == stream->offset;
}

/* A write in flight owns its bytes until libuv says it is done with them, so
 * the request and the copy are one allocation and are freed together. */
typedef struct {
    uv_write_t request;
    NuppNetStream *stream;
    size_t length;
    uint8_t bytes[1];
} NetWrite;

static void net_on_written(uv_write_t *request, int status) {
    NetWrite *write = (NetWrite *)request;
    NuppNetStream *stream = write->stream;
    if (stream->pending >= write->length) {
        stream->pending -= write->length;
    } else {
        stream->pending = 0;
    }
    if (status < 0 && stream->failure == 0) {
        stream->failure = status;
    }
    free(write);
}

/* Hands bytes to libuv and answers how many it took, which is all of them or
 * none: partial acceptance is the caller's business to arrange by writing less,
 * and a half-taken value would make the count meaningless. */
NUPP_EXPORT intptr_t nuppNetTryWrite(NuppNetStream *stream, const uint8_t *from, size_t length) {
    NetWrite *write;
    uv_buf_t buffer;
    int started;
    if (stream == NULL || (from == NULL && length > 0)) {
        nupp_fail("net: write needs a stream and its bytes");
        return -1;
    }
    if (stream->closing) {
        nupp_fail("net: the stream is closed");
        return -1;
    }
    if (stream->layered) {
        nupp_fail("net: the stream is owned by kernel TLS");
        return -1;
    }
    if (stream->wrote && stream->failure != 0) {
        nupp_fail_format("net: %s", uv_strerror(stream->failure));
        return -1;
    }
    if (length == 0) {
        return 0;
    }
    write = calloc(1, sizeof *write + length - 1);
    if (write == NULL) {
        nupp_fail("net: out of memory");
        return -1;
    }
    memcpy(write->bytes, from, length);
    write->stream = stream;
    write->length = length;
    buffer = uv_buf_init((char *)write->bytes, (unsigned)length);
    stream->pending += length;
    started = uv_write(&write->request, (uv_stream_t *)&stream->socket, &buffer, 1, net_on_written);
    if (started != 0) {
        stream->pending -= length;
        free(write);
        nupp_fail_format("net: %s", uv_strerror(started));
        return -1;
    }
    stream->wrote = true;
    return (intptr_t)length;
}

/* Bytes this process still holds. Local, and not a delivery receipt. */
NUPP_EXPORT size_t nuppNetPending(NuppNetStream *stream) {
    return stream == NULL ? 0 : stream->pending;
}

/* Gives kernel TLS an independent descriptor for the same connected socket and
 * takes libuv out of its data path. The duplicate intentionally keeps the open
 * file description alive only until the TLS session is released; ordinary
 * connection ownership and the public closed guard remain on `stream`.
 *
 * A refusal hands the kernel nothing, so the TLS layer above treats it as the
 * handoff not beginning and stays on user-space records. Buffered bytes are
 * one such refusal: a peer that wrote application data on the heels of its
 * Finished has ciphertext sitting in this process, and records the kernel
 * never saw cannot be decrypted by it. Reads stopped here resume on demand,
 * so a stream refused or abandoned after this call keeps working. */
NUPP_EXPORT intptr_t nuppNetStreamTlsSocket(NuppNetStream *stream) {
#if defined(__linux__)
    uv_os_fd_t descriptor;
    int duplicated;
    if (stream == NULL || stream->closing || stream->isPipe) {
        nupp_fail("net: kernel TLS needs an open TCP stream");
        return -1;
    }
    if (stream->pending != 0 || stream->length != stream->offset) {
        nupp_fail("net: kernel TLS needs an empty socket queue");
        return -1;
    }
    if (stream->started) {
        uv_read_stop((uv_stream_t *)&stream->socket);
        stream->started = false;
        stream->paused = false;
    }
    if (uv_fileno((const uv_handle_t *)&stream->socket, &descriptor) != 0) {
        nupp_fail("net: the TCP descriptor is unavailable");
        return -1;
    }
    duplicated = dup((int)descriptor);
    if (duplicated < 0) {
        nupp_fail("net: the TCP descriptor could not be duplicated");
        return -1;
    }
    return (intptr_t)duplicated;
#else
    (void)stream;
    nupp_fail("net: kernel TLS is available only on Linux");
    return -1;
#endif
}

/* Marks the stream as owned by the kernel record layer. Separate from handing
 * out the descriptor, because between the two the TLS layer still has to
 * attach the ULP and install both directions' keys, any of which can fail: a
 * stream marked before then would go on refusing ordinary reads and writes
 * over a handoff that never happened -- one that fell back to user-space
 * records still runs its whole session through them. */
NUPP_EXPORT void nuppNetStreamTlsEngaged(NuppNetStream *stream) {
    if (stream != NULL) {
        stream->layered = true;
    }
}

NUPP_EXPORT void *nuppNetStreamLoop(NuppNetStream *stream) {
    if (stream == NULL) {
        return NULL;
    }
    return uv_handle_get_loop((const uv_handle_t *)&stream->socket);
}

static void net_on_shutdown(uv_shutdown_t *request, int status) {
    NuppNetStream *stream = request->data;
    if (status < 0 && stream->failure == 0) {
        stream->failure = status;
    }
    stream->shuttingDown = false;
    free(request);
}

/* Whether the end of the sending half is still in libuv's hands. */
NUPP_EXPORT bool nuppNetStreamShuttingDown(NuppNetStream *stream) {
    return stream != NULL && stream->shuttingDown;
}

/* How much this stream's receive buffer has grown to hold.
 *
 * Not part of the Lua surface: a program has no use for it, and the only reason
 * it is reachable at all is that the bound on it is the sort of property a test
 * has to observe rather than infer. */
NUPP_EXPORT size_t nuppNetStreamCapacity(NuppNetStream *stream) {
    return stream == NULL ? 0 : stream->capacity;
}

/* Ends the sending half and leaves the receiving half open, so the peer sees
 * end of stream while this side goes on reading. */
NUPP_EXPORT uint8_t nuppNetShutdownWrite(NuppNetStream *stream) {
    uv_shutdown_t *request;
    int started;
    if (stream == NULL || stream->closing) {
        return 0;
    }
    request = calloc(1, sizeof *request);
    if (request == NULL) {
        nupp_fail("net: out of memory");
        return 0;
    }
    request->data = stream;
    stream->shuttingDown = true;
    started = uv_shutdown(request, (uv_stream_t *)&stream->socket, net_on_shutdown);
    if (started != 0) {
        stream->shuttingDown = false;
        free(request);
        nupp_fail_format("net: %s", uv_strerror(started));
        return 0;
    }
    return 1;
}

NUPP_EXPORT uint8_t nuppNetCloseStream(NuppNetStream *stream) {
    if (stream == NULL || stream->closing) {
        return 1;
    }
    stream->closing = true;
    if (stream->started) {
        uv_read_stop((uv_stream_t *)&stream->socket);
        stream->started = false;
    }
    uv_close((uv_handle_t *)&stream->socket, net_stream_closed);
    return 1;
}

NUPP_EXPORT void nuppNetStreamDestroy(NuppNetStream *stream) {
    if (stream == NULL) {
        return;
    }
    if (!stream->closing) {
        nuppNetCloseStream(stream);
    }
    stream->destroyed = true;
    net_stream_reap(stream);
}

/* Who is at the other end.
 *
 * The question a server asks about every connection it accepts, and the reason
 * it has to be here rather than inferred: a listener knows the address it bound
 * and nothing about who reached it. Answers false for a Unix socket, which has
 * a filesystem name and no peer address at all.
 */
NUPP_EXPORT bool nuppNetStreamPeer(
    NuppNetStream *stream,
    char *host,
    size_t capacity,
    int32_t *port
) {
    struct sockaddr_storage address;
    int length = (int)sizeof address;
    if (stream == NULL || stream->closing || stream->isPipe) {
        return false;
    }
    if (uv_tcp_getpeername(&stream->socket.tcp, (struct sockaddr *)&address, &length) != 0) {
        return false;
    }
    return net_address_text((const struct sockaddr *)&address, host, capacity, port);
}

/* Which of this machine's addresses the connection is on. */
NUPP_EXPORT bool nuppNetStreamLocal(
    NuppNetStream *stream,
    char *host,
    size_t capacity,
    int32_t *port
) {
    struct sockaddr_storage address;
    int length = (int)sizeof address;
    if (stream == NULL || stream->closing || stream->isPipe) {
        return false;
    }
    if (uv_tcp_getsockname(&stream->socket.tcp, (struct sockaddr *)&address, &length) != 0) {
        return false;
    }
    return net_address_text((const struct sockaddr *)&address, host, capacity, port);
}

/* Turns Nagle's algorithm off.
 *
 * On by default in the kernel, which coalesces small writes and can hold a
 * reply for tens of milliseconds waiting for more. That is the right trade for
 * bulk transfer and the wrong one for every request-and-response protocol,
 * which is most of them. */
NUPP_EXPORT uint8_t nuppNetStreamNoDelay(NuppNetStream *stream, bool enable) {
    int failed;
    if (stream == NULL || stream->closing || stream->isPipe) {
        nupp_fail("net: the connection has no such option");
        return 0;
    }
    failed = uv_tcp_nodelay(&stream->socket.tcp, enable ? 1 : 0);
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        return 0;
    }
    return 1;
}

/* Asks the kernel to probe an idle connection, so that a peer which vanished
 * without closing is eventually noticed rather than held open forever. */
NUPP_EXPORT uint8_t nuppNetStreamKeepAlive(
    NuppNetStream *stream,
    bool enable,
    uint32_t delaySeconds
) {
    int failed;
    if (stream == NULL || stream->closing || stream->isPipe) {
        nupp_fail("net: the connection has no such option");
        return 0;
    }
    failed = uv_tcp_keepalive(&stream->socket.tcp, enable ? 1 : 0, (unsigned)delaySeconds);
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        return 0;
    }
    return 1;
}

/* --- listeners ---------------------------------------------------------- */

struct NuppNetListener {
    NetHandle socket;
    bool isPipe;
    uv_loop_t *where;
    bool closing;
    bool closed;
    bool destroyed;
    int failure;

    NuppNetStream *queue[NET_ACCEPT_QUEUE_MAX];
    size_t head;
    size_t count;
};

typedef struct NuppNetListener NuppNetListener;

static void net_listener_closed(uv_handle_t *handle) {
    NuppNetListener *listener = handle->data;
    listener->closed = true;
    if (listener->destroyed) {
        free(listener);
    }
}

static void net_discard_closed(uv_handle_t *handle) {
    free(handle);
}

/* Accepts a connection there is no room for and closes it at once. Leaving it
 * unaccepted instead would park it in the server handle, and libuv stops the
 * watcher until an accept consumes it -- which would silence the listener for
 * good however far the queue later drained. */
static void net_discard_connection(NuppNetListener *listener, uv_stream_t *server) {
    NetHandle *scratch = malloc(sizeof *scratch);
    int made;
    if (scratch == NULL) {
        listener->failure = UV_ENOMEM;
        return;
    }
    made = listener->isPipe
        ? uv_pipe_init(listener->where, &scratch->pipe, 0)
        : uv_tcp_init(listener->where, &scratch->tcp);
    if (made != 0) {
        free(scratch);
        listener->failure = made;
        return;
    }
    uv_accept(server, (uv_stream_t *)scratch);
    ((uv_handle_t *)scratch)->data = NULL;
    uv_close((uv_handle_t *)scratch, net_discard_closed);
}

/* A connection arrives whether or not anyone is ready for it. Accepting it here
 * and queueing keeps the kernel's backlog from being the only bound, and
 * refusing past the queue's own ceiling is what stops an unaccepted listener
 * from growing without limit. */
static void net_on_connection(uv_stream_t *server, int status) {
    NuppNetListener *listener = ((uv_handle_t *)server)->data;
    NuppNetStream *stream;
    int failed;
    if (status < 0) {
        listener->failure = status;
        return;
    }
    if (listener->count == NET_ACCEPT_QUEUE_MAX) {
        net_discard_connection(listener, server);
        return;
    }
    stream = net_stream_new(listener->where, listener->isPipe);
    if (stream == NULL) {
        listener->failure = UV_ENOMEM;
        net_discard_connection(listener, server);
        return;
    }
    failed = uv_accept(server, (uv_stream_t *)&stream->socket);
    if (failed != 0) {
        nuppNetStreamDestroy(stream);
        listener->failure = failed;
        return;
    }
    listener->queue[(listener->head + listener->count) % NET_ACCEPT_QUEUE_MAX] = stream;
    listener->count++;
}

NUPP_EXPORT NuppNetListener *nuppNetListen(
    NuppNetLoop *reactor,
    const uint8_t *host,
    size_t hostLength,
    uint16_t port,
    int32_t backlog,
    bool reusePort
) {
    NuppText text;
    NuppNetListener *listener;
    struct sockaddr_storage address;
    unsigned flags = 0;
    int failed;

    if (reactor == NULL) {
        nupp_fail("net: listening needs a reactor");
        return NULL;
    }
    if (!nupp_text(&text, host, hostLength, "host")) {
        return NULL;
    }
    if (uv_ip4_addr(text.value, port, (struct sockaddr_in *)&address) != 0
        && uv_ip6_addr(text.value, port, (struct sockaddr_in6 *)&address) != 0) {
        nupp_fail_format("net: %s is not an address to bind", text.value);
        nupp_text_free(&text);
        return NULL;
    }
    nupp_text_free(&text);

    listener = calloc(1, sizeof *listener);
    if (listener == NULL) {
        nupp_fail("net: out of memory");
        return NULL;
    }
    if (uv_tcp_init(&reactor->loop, &listener->socket.tcp) != 0) {
        free(listener);
        nupp_fail("net: the listener could not be created");
        return NULL;
    }
    ((uv_handle_t *)&listener->socket)->data = listener;
    listener->where = &reactor->loop;

    /* Load-balancing reuse is asked for explicitly and refused where the
     * platform's semantics are not load balancing, which is libuv's judgment
     * and not this file's. A refusal is reported rather than downgraded,
     * because a program that asked for it is depending on it. */
    if (reusePort) {
        flags |= UV_TCP_REUSEPORT;
    }
    failed = uv_tcp_bind(&listener->socket.tcp, (const struct sockaddr *)&address, flags);
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        listener->destroyed = true;
        listener->closing = true;
        uv_close((uv_handle_t *)&listener->socket, net_listener_closed);
        return NULL;
    }
    failed = uv_listen((uv_stream_t *)&listener->socket,
        backlog > 0 ? (int)backlog : 128, net_on_connection);
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        listener->destroyed = true;
        listener->closing = true;
        uv_close((uv_handle_t *)&listener->socket, net_listener_closed);
        return NULL;
    }
    return listener;
}

/* A listener on a filesystem name rather than an address.
 *
 * Everything above this -- accepting, the queue, closing -- is the same, which
 * is the point of the handle union: a Unix socket differs from a TCP one in how
 * it is named and in nothing else this file does with it.
 *
 * The name is not unlinked here. A caller that binds a path owns that path, and
 * removing a file this process did not create is not a transport's decision to
 * make. */
NUPP_EXPORT NuppNetListener *nuppNetListenPath(
    NuppNetLoop *reactor,
    const uint8_t *path,
    size_t pathLength,
    int32_t backlog
) {
    NuppText text;
    NuppNetListener *listener;
    int failed;

    if (reactor == NULL) {
        nupp_fail("net: listening needs a reactor");
        return NULL;
    }
    if (!nupp_text(&text, path, pathLength, "path")) {
        return NULL;
    }
    listener = calloc(1, sizeof *listener);
    if (listener == NULL) {
        nupp_text_free(&text);
        nupp_fail("net: out of memory");
        return NULL;
    }
    if (uv_pipe_init(&reactor->loop, &listener->socket.pipe, 0) != 0) {
        nupp_text_free(&text);
        free(listener);
        nupp_fail("net: the listener could not be created");
        return NULL;
    }
    ((uv_handle_t *)&listener->socket)->data = listener;
    listener->where = &reactor->loop;
    listener->isPipe = true;

    failed = uv_pipe_bind(&listener->socket.pipe, text.value);
    nupp_text_free(&text);
    if (failed == 0) {
        failed = uv_listen((uv_stream_t *)&listener->socket,
            backlog > 0 ? (int)backlog : 128, net_on_connection);
    }
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        listener->destroyed = true;
        listener->closing = true;
        uv_close((uv_handle_t *)&listener->socket, net_listener_closed);
        return NULL;
    }
    return listener;
}

/* The port actually bound, which is what a caller who asked for zero needs. */
NUPP_EXPORT int32_t nuppNetListenerPort(NuppNetListener *listener) {
    struct sockaddr_storage address;
    int length = (int)sizeof address;
    /* A listener bound to a filesystem name has no port, and asking a pipe
     * handle for a socket name is a different question with a plausible-looking
     * wrong answer. */
    if (listener == NULL || listener->closing || listener->isPipe) {
        return -1;
    }
    if (uv_tcp_getsockname(&listener->socket.tcp, (struct sockaddr *)&address, &length) != 0) {
        return -1;
    }
    if (address.ss_family == AF_INET6) {
        return (int32_t)ntohs(((struct sockaddr_in6 *)&address)->sin6_port);
    }
    return (int32_t)ntohs(((struct sockaddr_in *)&address)->sin_port);
}

/* Answers the next accepted connection, and says which kind of nothing a NULL
 * is: `status` is 1 with a connection, 0 when none is waiting, and -1 when the
 * listener failed. The error slot alone could not carry that, because it holds
 * whatever last failed anywhere and a quiet listener has not failed at all. */
NUPP_EXPORT NuppNetStream *nuppNetAccept(NuppNetListener *listener, int32_t *status) {
    NuppNetStream *stream;
    if (status != NULL) {
        *status = -1;
    }
    if (listener == NULL || listener->closing) {
        nupp_fail("net: the listener is closed");
        return NULL;
    }
    if (listener->count == 0) {
        if (listener->failure != 0) {
            int failure = listener->failure;
            listener->failure = 0;
            nupp_fail_format("net: %s", uv_strerror(failure));
            return NULL;
        }
        if (status != NULL) {
            *status = 0;
        }
        return NULL;
    }
    if (status != NULL) {
        *status = 1;
    }
    stream = listener->queue[listener->head];
    listener->queue[listener->head] = NULL;
    listener->head = (listener->head + 1) % NET_ACCEPT_QUEUE_MAX;
    listener->count--;
    return stream;
}

NUPP_EXPORT uint8_t nuppNetListenerClose(NuppNetListener *listener) {
    size_t at;
    if (listener == NULL || listener->closing) {
        return 1;
    }
    listener->closing = true;
    /* Connections accepted but never taken are this listener's to release: the
     * caller never saw them and has nothing to close. */
    for (at = 0; at < listener->count; at++) {
        size_t slot = (listener->head + at) % NET_ACCEPT_QUEUE_MAX;
        nuppNetStreamDestroy(listener->queue[slot]);
        listener->queue[slot] = NULL;
    }
    listener->count = 0;
    uv_close((uv_handle_t *)&listener->socket, net_listener_closed);
    return 1;
}

NUPP_EXPORT void nuppNetListenerDestroy(NuppNetListener *listener) {
    if (listener == NULL) {
        return;
    }
    if (!listener->closing) {
        nuppNetListenerClose(listener);
    }
    listener->destroyed = true;
    if (listener->closed) {
        free(listener);
    }
}

/* --- connecting --------------------------------------------------------- */

/* A connect is two waits, resolution and the handshake, behind one handle. The
 * name lookup is libuv's threaded resolver, so it is off the caller's frame
 * rather than blocking the Nupp scheduler. */
struct NuppNetConnect {
    uv_getaddrinfo_t resolve;
    uv_connect_t connect;
    uv_timer_t deadline;
    uv_loop_t *where;
    NuppNetStream *stream;

    /* Every address the name resolved to, and the next one to try. A connect
     * that starts is not a connect that succeeded, so the list has to outlive
     * the first attempt: a host whose first answer is an unreachable IPv6 and
     * whose second is a working IPv4 is the ordinary case this exists for. */
    struct addrinfo *resolved;
    struct addrinfo *next;

    uint16_t port;
    bool resolving;
    bool connecting;
    bool timing;
    bool done;
    bool destroyed;
    bool expired;
    int failure;
};

typedef struct NuppNetConnect NuppNetConnect;

/* Freed only once libuv has finished with all three of the handles a connect
 * can have outstanding: the resolution, the handshake and the deadline. */
static void net_connect_release(NuppNetConnect *request) {
    if (request->resolving || request->connecting || request->timing) {
        return;
    }
    if (request->resolved != NULL) {
        uv_freeaddrinfo(request->resolved);
        request->resolved = NULL;
    }
    if (request->stream != NULL) {
        nuppNetStreamDestroy(request->stream);
        request->stream = NULL;
    }
    free(request);
}

static void net_connect_timer_closed(uv_handle_t *handle) {
    NuppNetConnect *request = handle->data;
    request->timing = false;
    if (request->destroyed) {
        net_connect_release(request);
    }
}

static void net_connect_stop_timer(NuppNetConnect *request) {
    if (!request->timing) {
        return;
    }
    uv_timer_stop(&request->deadline);
    if (!uv_is_closing((uv_handle_t *)&request->deadline)) {
        uv_close((uv_handle_t *)&request->deadline, net_connect_timer_closed);
    }
}

/* The deadline does not cancel libuv's work -- a resolution or a handshake
 * still in its hands has to finish on its own -- it records that the answer is
 * no longer wanted, which is what the poll below reports. */
static void net_connect_expired(uv_timer_t *timer) {
    NuppNetConnect *request = timer->data;
    request->expired = true;
    request->done = true;
}

static void net_on_connect(uv_connect_t *handle, int status);

static bool net_connect_attempt(NuppNetConnect *request) {
    while (request->next != NULL) {
        struct addrinfo *at = request->next;
        request->next = at->ai_next;
        if (at->ai_family != AF_INET && at->ai_family != AF_INET6) {
            continue;
        }
        if (at->ai_family == AF_INET) {
            ((struct sockaddr_in *)at->ai_addr)->sin_port = htons(request->port);
        } else {
            ((struct sockaddr_in6 *)at->ai_addr)->sin6_port = htons(request->port);
        }
        /* A failed attempt leaves its handle unusable, so each address gets a
         * fresh one rather than the previous one being reset. */
        if (request->stream != NULL) {
            nuppNetStreamDestroy(request->stream);
        }
        request->stream = net_stream_new(request->where, false);
        if (request->stream == NULL) {
            request->failure = UV_ENOMEM;
            return false;
        }
        request->connect.data = request;
        if (uv_tcp_connect(&request->connect, &request->stream->socket.tcp,
                at->ai_addr, net_on_connect) == 0) {
            /* Cleared as the attempt starts. What the previous address said is
             * only the answer if nothing after it works, and leaving it set
             * would report a connection that succeeded as a failure. */
            request->failure = 0;
            request->connecting = true;
            return true;
        }
    }
    return false;
}

static void net_on_connect(uv_connect_t *handle, int status) {
    NuppNetConnect *request = handle->data;
    request->connecting = false;
    if (status < 0 && !request->expired) {
        /* This address did not answer. Another may: giving up on the first
         * failure is what makes a host with a dead IPv6 answer unreachable even
         * though its IPv4 one works. */
        request->failure = status;
        if (!request->destroyed && net_connect_attempt(request)) {
            return;
        }
    }
    request->done = true;
    net_connect_stop_timer(request);
    if (request->destroyed) {
        net_connect_release(request);
    }
}

static void net_on_resolved(uv_getaddrinfo_t *handle, int status, struct addrinfo *found) {
    NuppNetConnect *request = handle->data;

    request->resolving = false;
    if (status < 0) {
        request->failure = status;
        request->done = true;
        if (found != NULL) {
            uv_freeaddrinfo(found);
        }
    } else if (request->expired || request->destroyed) {
        /* The answer arrived after the caller stopped waiting for it. Finishing
         * what libuv already had is unavoidable; starting a connection nobody
         * is going to be told about is not. */
        if (found != NULL) {
            uv_freeaddrinfo(found);
        }
        request->done = true;
    } else {
        /* Kept, not walked and freed: the list has to outlive every attempt
         * made from it, and `net_connect_release` is what returns it. */
        request->resolved = found;
        request->next = found;
        if (!net_connect_attempt(request)) {
            if (request->failure == 0) {
                request->failure = UV_EAI_NONAME;
            }
            request->done = true;
        }
    }
    if (request->done) {
        net_connect_stop_timer(request);
    }
    if (request->destroyed) {
        net_connect_release(request);
    }
}

NUPP_EXPORT NuppNetConnect *nuppNetConnectBegin(
    NuppNetLoop *reactor,
    const uint8_t *host,
    size_t hostLength,
    uint16_t port,
    int32_t timeoutMs
) {
    NuppText text;
    NuppNetConnect *request;
    struct addrinfo hints;
    int started;

    if (reactor == NULL) {
        nupp_fail("net: connecting needs a reactor");
        return NULL;
    }
    if (!nupp_text(&text, host, hostLength, "host")) {
        return NULL;
    }
    request = calloc(1, sizeof *request);
    if (request == NULL) {
        nupp_text_free(&text);
        nupp_fail("net: out of memory");
        return NULL;
    }
    request->where = &reactor->loop;
    request->port = port;
    request->stream = net_stream_new(&reactor->loop, false);
    if (request->stream == NULL) {
        nupp_text_free(&text);
        free(request);
        nupp_fail("net: the socket could not be created");
        return NULL;
    }

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    request->resolve.data = request;
    started = uv_getaddrinfo(&reactor->loop, &request->resolve, net_on_resolved,
        text.value, NULL, &hints);
    nupp_text_free(&text);
    if (started != 0) {
        nuppNetStreamDestroy(request->stream);
        free(request);
        nupp_fail_format("net: %s", uv_strerror(started));
        return NULL;
    }
    request->resolving = true;
    if (timeoutMs > 0 && uv_timer_init(&reactor->loop, &request->deadline) == 0) {
        request->deadline.data = request;
        request->timing = true;
        uv_update_time(&reactor->loop);
        uv_timer_start(&request->deadline, net_connect_expired, (uint64_t)timeoutMs, 0);
    }
    return request;
}

/* Connecting to a filesystem name. No resolution to do, so the request starts
 * in the handshake rather than before it. */
NUPP_EXPORT NuppNetConnect *nuppNetConnectPath(
    NuppNetLoop *reactor,
    const uint8_t *path,
    size_t pathLength,
    int32_t timeoutMs
) {
    NuppText text;
    NuppNetConnect *request;
    int started;

    if (reactor == NULL) {
        nupp_fail("net: connecting needs a reactor");
        return NULL;
    }
    if (!nupp_text(&text, path, pathLength, "path")) {
        return NULL;
    }
    request = calloc(1, sizeof *request);
    if (request == NULL) {
        nupp_text_free(&text);
        nupp_fail("net: out of memory");
        return NULL;
    }
    request->where = &reactor->loop;
    request->stream = net_stream_new(&reactor->loop, true);
    if (request->stream == NULL) {
        nupp_text_free(&text);
        free(request);
        nupp_fail("net: the socket could not be created");
        return NULL;
    }
    request->connect.data = request;
    started = uv_pipe_connect2(&request->connect, &request->stream->socket.pipe,
        text.value, text.length, 0, net_on_connect);
    nupp_text_free(&text);
    if (started != 0) {
        nuppNetStreamDestroy(request->stream);
        free(request);
        nupp_fail_format("net: %s", uv_strerror(started));
        return NULL;
    }
    request->connecting = true;
    if (timeoutMs > 0 && uv_timer_init(&reactor->loop, &request->deadline) == 0) {
        request->deadline.data = request;
        request->timing = true;
        uv_update_time(&reactor->loop);
        uv_timer_start(&request->deadline, net_connect_expired, (uint64_t)timeoutMs, 0);
    }
    return request;
}

/* Answers 0 while the connect is still going, 1 with the stream moved to `out`
 * when it succeeded, and -1 when it failed. The stream leaves the request on
 * success, so a caller owns exactly one of them at a time. */
NUPP_EXPORT int32_t nuppNetConnectPoll(NuppNetConnect *request, NuppNetStream **out) {
    if (request == NULL || out == NULL) {
        nupp_fail("net: a connect and a destination are needed");
        return -1;
    }
    if (!request->done) {
        return 0;
    }
    if (request->expired) {
        nupp_fail("net: the connect did not finish before its deadline");
        return -1;
    }
    if (request->failure != 0) {
        nupp_fail_format("net: %s", uv_strerror(request->failure));
        return -1;
    }
    *out = request->stream;
    request->stream = NULL;
    return 1;
}

/* A resolution or handshake still in libuv's hands cannot be freed underneath
 * it, so an abandoned request is marked and released by whichever callback
 * arrives last. */
NUPP_EXPORT void nuppNetConnectDestroy(NuppNetConnect *request) {
    if (request == NULL) {
        return;
    }
    request->destroyed = true;
    net_connect_stop_timer(request);
    net_connect_release(request);
}

/* --- datagrams ---------------------------------------------------------- */

/* A datagram is a message, not a stream, so nothing here buffers bytes into a
 * run: each arrival is queued whole, with the peer that sent it and whether it
 * was larger than we could hold. Truncation is carried rather than hidden,
 * because a protocol that parses the first part of a message nobody sent is a
 * security bug and not a lost packet.
 */
#define NET_DATAGRAM_QUEUE_MAX 256
#define NET_DATAGRAM_MAX 65536

typedef struct {
    uint8_t *bytes;
    size_t length;
    bool truncated;
    char host[64];
    int32_t port;
} NetMessage;

/* A peer address some layered session has bound to. One datagram socket may
 * carry several DTLS sessions, and a session that is still learning its own
 * peer takes the oldest datagram from anybody -- so a peer another session has
 * already claimed has to be off limits, or the learner consumes records that
 * were that session's to decrypt. */
typedef struct NetPeerClaim {
    struct NetPeerClaim *next;
    char host[64];
    int32_t port;
} NetPeerClaim;

struct NuppNetDatagram {
    uv_udp_t udp;
    bool started;
    bool closing;
    bool closed;
    bool destroyed;
    unsigned holders;
    int failure;

    NetPeerClaim *claims;

    uint8_t *slab;
    NetMessage queue[NET_DATAGRAM_QUEUE_MAX];
    size_t head;
    size_t count;
};

typedef struct NuppNetDatagram NuppNetDatagram;

static void net_datagram_reap(NuppNetDatagram *socket) {
    if (!socket->closed || !socket->destroyed || socket->holders > 0) {
        return;
    }
    for (size_t at = 0; at < socket->count; at++) {
        free(socket->queue[(socket->head + at) % NET_DATAGRAM_QUEUE_MAX].bytes);
    }
    while (socket->claims != NULL) {
        NetPeerClaim *claim = socket->claims;
        socket->claims = claim->next;
        free(claim);
    }
    free(socket->slab);
    free(socket);
}

static bool net_datagram_claimed(
    NuppNetDatagram *socket,
    const char *host,
    int32_t port
) {
    const NetPeerClaim *at;
    for (at = socket->claims; at != NULL; at = at->next) {
        if (at->port == port && strcmp(at->host, host) == 0) {
            return true;
        }
    }
    return false;
}

/* Registered by the session that bound the peer, released when it unbinds or
 * goes. Best effort on purpose: a claim that could not be allocated costs a
 * learner possibly consuming a record, not correctness of the claimant's own
 * addressed receives. */
NUPP_EXPORT bool nuppNetDatagramClaimPeer(
    NuppNetDatagram *socket,
    const char *host,
    int32_t port
) {
    NetPeerClaim *claim;
    if (socket == NULL || host == NULL) {
        return false;
    }
    claim = calloc(1, sizeof *claim);
    if (claim == NULL) {
        return false;
    }
    strncpy(claim->host, host, sizeof claim->host - 1);
    claim->port = port;
    claim->next = socket->claims;
    socket->claims = claim;
    return true;
}

NUPP_EXPORT void nuppNetDatagramReleasePeer(
    NuppNetDatagram *socket,
    const char *host,
    int32_t port
) {
    NetPeerClaim **at;
    if (socket == NULL || host == NULL) {
        return;
    }
    for (at = &socket->claims; *at != NULL; at = &(*at)->next) {
        if ((*at)->port == port && strcmp((*at)->host, host) == 0) {
            NetPeerClaim *found = *at;
            *at = found->next;
            free(found);
            return;
        }
    }
}

static void net_datagram_closed(uv_handle_t *handle) {
    NuppNetDatagram *socket = handle->data;
    socket->closed = true;
    net_datagram_reap(socket);
}

NUPP_EXPORT void nuppNetDatagramRetain(NuppNetDatagram *socket) {
    if (socket != NULL) {
        socket->holders++;
    }
}

NUPP_EXPORT void nuppNetDatagramRelease(NuppNetDatagram *socket) {
    if (socket == NULL || socket->holders == 0) {
        return;
    }
    socket->holders--;
    net_datagram_reap(socket);
}

NUPP_EXPORT bool nuppNetDatagramClosed(NuppNetDatagram *socket) {
    return socket == NULL || socket->closing;
}

/* One slab, reused. libuv asks for somewhere to put the next datagram and this
 * is always that place: a datagram is copied out of it into the queue while the
 * callback still holds it, so nothing needs a second allocation per arrival
 * until a message is actually kept. */
static void net_datagram_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
    NuppNetDatagram *socket = handle->data;
    (void)suggested;
    if (socket->slab == NULL) {
        socket->slab = malloc(NET_DATAGRAM_MAX);
        if (socket->slab == NULL) {
            *buffer = uv_buf_init(NULL, 0);
            return;
        }
    }
    *buffer = uv_buf_init((char *)socket->slab, NET_DATAGRAM_MAX);
}

static void net_datagram_peer(NetMessage *message, const struct sockaddr *from) {
    message->port = 0;
    net_address_text(from, message->host, sizeof message->host, &message->port);
}

static void net_datagram_received(
    uv_udp_t *handle,
    ssize_t got,
    const uv_buf_t *buffer,
    const struct sockaddr *from,
    unsigned flags
) {
    NuppNetDatagram *socket = ((uv_handle_t *)handle)->data;
    NetMessage *message;
    size_t slot;

    if (got < 0) {
        socket->failure = (int)got;
        return;
    }
    /* Nothing arrived, as opposed to an empty datagram arriving: libuv tells the
     * two apart by whether there is a peer, and so does this. */
    if (got == 0 && from == NULL) {
        return;
    }
    if (socket->count == NET_DATAGRAM_QUEUE_MAX) {
        return;
    }
    slot = (socket->head + socket->count) % NET_DATAGRAM_QUEUE_MAX;
    message = &socket->queue[slot];
    message->length = (size_t)got;
    message->truncated = (flags & UV_UDP_PARTIAL) != 0;
    message->bytes = NULL;
    if (message->length > 0) {
        message->bytes = malloc(message->length);
        if (message->bytes == NULL) {
            socket->failure = UV_ENOMEM;
            return;
        }
        memcpy(message->bytes, buffer->base, message->length);
    }
    net_datagram_peer(message, from);
    socket->count++;
}

NUPP_EXPORT NuppNetDatagram *nuppNetBindDatagram(
    NuppNetLoop *reactor,
    const uint8_t *host,
    size_t hostLength,
    uint16_t port,
    bool reusePort
) {
    NuppText text;
    NuppNetDatagram *socket;
    struct sockaddr_storage address;
    unsigned flags = 0;
    int failed;

    if (reactor == NULL) {
        nupp_fail("net: binding needs a reactor");
        return NULL;
    }
    if (!nupp_text(&text, host, hostLength, "host")) {
        return NULL;
    }
    if (uv_ip4_addr(text.value, port, (struct sockaddr_in *)&address) != 0
        && uv_ip6_addr(text.value, port, (struct sockaddr_in6 *)&address) != 0) {
        nupp_fail_format("net: %s is not an address to bind", text.value);
        nupp_text_free(&text);
        return NULL;
    }
    nupp_text_free(&text);

    socket = calloc(1, sizeof *socket);
    if (socket == NULL) {
        nupp_fail("net: out of memory");
        return NULL;
    }
    if (uv_udp_init(&reactor->loop, &socket->udp) != 0) {
        free(socket);
        nupp_fail("net: the datagram socket could not be created");
        return NULL;
    }
    socket->udp.data = socket;
    if (reusePort) {
        flags |= UV_UDP_REUSEPORT;
    }
    failed = uv_udp_bind(&socket->udp, (const struct sockaddr *)&address, flags);
    if (failed == 0) {
        failed = uv_udp_recv_start(&socket->udp, net_datagram_alloc, net_datagram_received);
    }
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        socket->destroyed = true;
        socket->closing = true;
        uv_close((uv_handle_t *)&socket->udp, net_datagram_closed);
        return NULL;
    }
    socket->started = true;
    return socket;
}

NUPP_EXPORT int32_t nuppNetDatagramPort(NuppNetDatagram *socket) {
    struct sockaddr_storage address;
    int length = (int)sizeof address;
    if (socket == NULL || socket->closing) {
        return -1;
    }
    if (uv_udp_getsockname(&socket->udp, (struct sockaddr *)&address, &length) != 0) {
        return -1;
    }
    if (address.ss_family == AF_INET6) {
        return (int32_t)ntohs(((struct sockaddr_in6 *)&address)->sin6_port);
    }
    return (int32_t)ntohs(((struct sockaddr_in *)&address)->sin_port);
}

/* Takes the next message into `into`, answering how many bytes of it landed
 * there. `status` is 1 with a message, 0 when none is waiting and -1 on
 * failure; `truncated` is set when the datagram was larger than `capacity` or
 * larger than this process could receive at all, which are the same fact to a
 * caller and both mean the rest is gone. A zero-length answer with `status` 1 is
 * an empty datagram, which is a message like any other. */
NUPP_EXPORT intptr_t nuppNetDatagramReceive(
    NuppNetDatagram *socket,
    uint8_t *into,
    size_t capacity,
    int32_t *status,
    uint8_t *truncated,
    char *hostOut,
    size_t hostCapacity,
    int32_t *portOut
) {
    return nuppNetDatagramReceivePeer(
        socket, NULL, 0, true, into, capacity, status, truncated,
        hostOut, hostCapacity, portOut);
}

/* Takes the oldest datagram from one peer, or the oldest datagram at all while
 * a DTLS server is learning its peer. Messages for other sessions stay queued:
 * sharing one UDP socket must not make whichever session happens to poll first
 * consume another session's record. */
NUPP_EXPORT intptr_t nuppNetDatagramReceivePeer(
    NuppNetDatagram *socket,
    const char *wantedHost,
    int32_t wantedPort,
    bool anyPeer,
    uint8_t *into,
    size_t capacity,
    int32_t *status,
    uint8_t *truncated,
    char *hostOut,
    size_t hostCapacity,
    int32_t *portOut
) {
    NetMessage *message;
    size_t found = 0;
    size_t taking;
    size_t at;

    if (status != NULL) {
        *status = -1;
    }
    if (socket == NULL || socket->closing) {
        nupp_fail("net: the datagram socket is closed");
        return -1;
    }
    if (socket->count == 0) {
        if (socket->failure != 0) {
            int failure = socket->failure;
            socket->failure = 0;
            nupp_fail_format("net: %s", uv_strerror(failure));
            return -1;
        }
        if (status != NULL) {
            *status = 0;
        }
        return 0;
    }
    if (!anyPeer) {
        bool matched = false;
        for (found = 0; found < socket->count; found++) {
            message = &socket->queue[
                (socket->head + found) % NET_DATAGRAM_QUEUE_MAX];
            if (message->port == wantedPort && wantedHost != NULL &&
                strcmp(message->host, wantedHost) == 0) {
                matched = true;
                break;
            }
        }
        if (!matched) {
            if (status != NULL) {
                *status = 0;
            }
            return 0;
        }
    } else {
        /* Any peer means any peer nobody has claimed. A datagram from a
         * claimed address belongs to the session that claimed it, and it stays
         * queued for that session's own addressed receive. */
        bool available = false;
        for (found = 0; found < socket->count; found++) {
            message = &socket->queue[
                (socket->head + found) % NET_DATAGRAM_QUEUE_MAX];
            if (!net_datagram_claimed(socket, message->host, message->port)) {
                available = true;
                break;
            }
        }
        if (!available) {
            if (status != NULL) {
                *status = 0;
            }
            return 0;
        }
    }
    message = &socket->queue[
        (socket->head + found) % NET_DATAGRAM_QUEUE_MAX];
    taking = message->length < capacity ? message->length : capacity;
    if (taking > 0 && into != NULL) {
        memcpy(into, message->bytes, taking);
    }
    if (truncated != NULL) {
        *truncated = (message->truncated || taking < message->length) ? 1 : 0;
    }
    if (hostOut != NULL && hostCapacity > 0) {
        size_t length = strlen(message->host);
        if (length >= hostCapacity) {
            length = hostCapacity - 1;
        }
        memcpy(hostOut, message->host, length);
        hostOut[length] = '\0';
    }
    if (portOut != NULL) {
        *portOut = message->port;
    }
    free(message->bytes);
    for (at = found; at + 1 < socket->count; at++) {
        size_t destination = (socket->head + at) % NET_DATAGRAM_QUEUE_MAX;
        size_t source = (socket->head + at + 1) % NET_DATAGRAM_QUEUE_MAX;
        socket->queue[destination] = socket->queue[source];
    }
    memset(&socket->queue[
        (socket->head + socket->count - 1) % NET_DATAGRAM_QUEUE_MAX],
        0, sizeof socket->queue[0]);
    socket->count--;
    if (status != NULL) {
        *status = 1;
    }
    return (intptr_t)taking;
}

/* Sends one datagram. `uv_udp_try_send` rather than a queued send, because a
 * datagram either goes now or does not go: queueing one would hold bytes for a
 * message whose whole point is that nobody is promising to deliver it. */
NUPP_EXPORT uint8_t nuppNetDatagramSend(
    NuppNetDatagram *socket,
    const uint8_t *host,
    size_t hostLength,
    uint16_t port,
    const uint8_t *bytes,
    size_t length
) {
    NuppText text;
    intptr_t sent;

    if (socket == NULL || socket->closing) {
        nupp_fail("net: the datagram socket is closed");
        return 0;
    }
    if (!nupp_text(&text, host, hostLength, "host")) {
        return 0;
    }
    sent = nuppNetDatagramTrySend(socket, text.value, port, bytes, length);
    nupp_text_free(&text);
    if (sent == 0 && length > 0) {
        nupp_fail("net: the datagram socket would block");
        return 0;
    }
    return sent >= 0 ? 1 : 0;
}

/* Nonblocking datagram send in the spelling mbedTLS's BIO expects: the whole
 * message length on success, zero for backpressure, and -1 for a permanent
 * failure. */
NUPP_EXPORT intptr_t nuppNetDatagramTrySend(
    NuppNetDatagram *socket,
    const char *host,
    int32_t port,
    const uint8_t *bytes,
    size_t length
) {
    struct sockaddr_storage address;
    uv_buf_t buffer;
    int sent;
    if (socket == NULL || socket->closing) {
        nupp_fail("net: the datagram socket is closed");
        return -1;
    }
    if (host == NULL || port < 0 || port > 65535 ||
        (uv_ip4_addr(host, port, (struct sockaddr_in *)&address) != 0 &&
         uv_ip6_addr(host, port, (struct sockaddr_in6 *)&address) != 0)) {
        nupp_fail("net: the datagram peer is not an address");
        return -1;
    }
    buffer = uv_buf_init((char *)(uintptr_t)bytes, (unsigned)length);
    sent = uv_udp_try_send(
        &socket->udp, &buffer, 1, (const struct sockaddr *)&address);
    if (sent == UV_EAGAIN) {
        return 0;
    }
    if (sent < 0) {
        nupp_fail_format("net: %s", uv_strerror(sent));
        return -1;
    }
    return (intptr_t)sent;
}

NUPP_EXPORT uint8_t nuppNetDatagramClose(NuppNetDatagram *socket) {
    if (socket == NULL || socket->closing) {
        return 1;
    }
    socket->closing = true;
    if (socket->started) {
        uv_udp_recv_stop(&socket->udp);
        socket->started = false;
    }
    uv_close((uv_handle_t *)&socket->udp, net_datagram_closed);
    return 1;
}

NUPP_EXPORT void nuppNetDatagramDestroy(NuppNetDatagram *socket) {
    if (socket == NULL) {
        return;
    }
    if (!socket->closing) {
        nuppNetDatagramClose(socket);
    }
    socket->destroyed = true;
    net_datagram_reap(socket);
}

/* --- datagram options --------------------------------------------------- */

/* Sending to a broadcast address is refused by default, so a program that
 * means to has to say so. */
NUPP_EXPORT uint8_t nuppNetDatagramBroadcast(NuppNetDatagram *socket, bool enable) {
    int failed;
    if (socket == NULL || socket->closing) {
        nupp_fail("net: the datagram socket is closed");
        return 0;
    }
    failed = uv_udp_set_broadcast(&socket->udp, enable ? 1 : 0);
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        return 0;
    }
    return 1;
}

/* How many hops a multicast datagram may take. One keeps it on the local
 * segment, which is what discovery on a LAN wants and what the default is. */
NUPP_EXPORT uint8_t nuppNetDatagramMulticastTtl(NuppNetDatagram *socket, int32_t ttl) {
    int failed;
    if (socket == NULL || socket->closing) {
        nupp_fail("net: the datagram socket is closed");
        return 0;
    }
    if (ttl < 1 || ttl > 255) {
        nupp_fail("net: a multicast hop limit must be 1 through 255");
        return 0;
    }
    failed = uv_udp_set_multicast_ttl(&socket->udp, (int)ttl);
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        return 0;
    }
    return 1;
}

/* Whether this socket also receives what it sends to a group it joined. Off by
 * default here, because a discovery protocol that answers its own announcements
 * is the first bug somebody writes with one. */
NUPP_EXPORT uint8_t nuppNetDatagramMulticastLoop(NuppNetDatagram *socket, bool enable) {
    int failed;
    if (socket == NULL || socket->closing) {
        nupp_fail("net: the datagram socket is closed");
        return 0;
    }
    failed = uv_udp_set_multicast_loop(&socket->udp, enable ? 1 : 0);
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        return 0;
    }
    return 1;
}

/* Joins or leaves a multicast group.
 *
 * `interface` names which of this machine's addresses to join on, and may be
 * empty for the platform's choice. On a machine with more than one interface
 * that choice is rarely the one wanted, which is why it is offered rather than
 * assumed.
 */
NUPP_EXPORT uint8_t nuppNetDatagramMembership(
    NuppNetDatagram *socket,
    const uint8_t *group,
    size_t groupLength,
    const uint8_t *interfaceAddress,
    size_t interfaceLength,
    bool join
) {
    NuppText groupText;
    NuppText interfaceText;
    const char *on = NULL;
    int failed;

    if (socket == NULL || socket->closing) {
        nupp_fail("net: the datagram socket is closed");
        return 0;
    }
    if (!nupp_text(&groupText, group, groupLength, "group")) {
        return 0;
    }
    if (interfaceAddress != NULL && interfaceLength > 0) {
        if (!nupp_text(&interfaceText, interfaceAddress, interfaceLength, "interface")) {
            nupp_text_free(&groupText);
            return 0;
        }
        on = interfaceText.value;
    }
    failed = uv_udp_set_membership(&socket->udp, groupText.value, on,
        join ? UV_JOIN_GROUP : UV_LEAVE_GROUP);
    nupp_text_free(&groupText);
    if (on != NULL) {
        nupp_text_free(&interfaceText);
    }
    if (failed != 0) {
        nupp_fail_format("net: %s", uv_strerror(failed));
        return 0;
    }
    return 1;
}
