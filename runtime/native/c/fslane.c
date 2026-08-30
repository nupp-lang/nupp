/* Whole-file transfers, off the calling thread.
 *
 * A transfer is submitted, settles on libuv's thread pool, and is observed by
 * polling. Nothing here calls Lua and nothing here blocks the submitter, which
 * is what lets one caller wait by sleeping and another wait by parking a task
 * and pumping this from its frame.
 *
 * The pool, the queue and the workers are libuv's. What is left is the lane's
 * own accounting: how many transfers may be live, how many bytes they may hold
 * between them, and how large one may be -- because a queue that grows with its
 * callers eventually takes the process with it.
 */

#include "nupp_native.h"

#include <uv.h>

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STATUS_PENDING 0
#define STATUS_READY 1
#define STATUS_FAILED 2
#define STATUS_CANCELED 3

#define MAX_REQUESTS 128
#define MAX_BYTES (256u * 1024u * 1024u)
#define MAX_REQUEST_BYTES (256u * 1024u * 1024u)

typedef enum { WORK_READ, WORK_WRITE, WORK_COPY } WorkKind;

/* One transfer's shared state, held by the caller's handle and by the work
 * running on the pool, released by whichever lets go last. */
typedef struct Slot {
    atomic_int status;
    atomic_int references;
    uv_mutex_t guard;

    WorkKind kind;
    char *first;
    char *second;
    uint8_t *contents;
    size_t contentsLength;
    uint32_t mode;

    uint8_t *data;
    size_t length;
    char *reason;
    size_t charged;

    uv_work_t work;

    /* Intake and cancellation links, each used on its list at most once. */
    struct Slot *intakeNext;
    struct Slot *cancelNext;
} Slot;

struct NuppRequest {
    Slot *slot;
};

typedef struct NuppRequest NuppRequest;

static atomic_size_t requestsLive;
static atomic_size_t bytesInFlight;
static atomic_size_t settledCount;

/* The lane's own loop, on its own thread, so a submission from Lua never waits
 * on one. libuv's pool does the work; this exists only to have somewhere for
 * its completions to be delivered. */
static uv_loop_t laneLoop;
static uv_async_t laneWake;
static uv_thread_t laneThread;
static uv_mutex_t arrivalsGuard;
static uv_cond_t arrivalsSignal;
static size_t arrivals;
static atomic_int laneStarted;

/* Submissions and cancellations cross to the lane thread through these lists:
 * `uv_async_send` is the one libuv call another thread may make, so queueing
 * and cancelling work on the lane's loop happens on the lane's thread. */
static uv_mutex_t intakeGuard;
static Slot *intakeFirst;
static Slot *intakeLast;
static Slot *cancelFirst;

static void slot_release(Slot *slot) {
    if (atomic_fetch_sub(&slot->references, 1) != 1) {
        return;
    }
    uv_mutex_destroy(&slot->guard);
    free(slot->first);
    free(slot->second);
    free(slot->contents);
    free(slot->data);
    free(slot->reason);
    free(slot);
}

/* Returns a transfer's share of the budget. Tied to the caller's handle rather
 * than to the shared state, which is the difference between a cap on what a
 * program is holding and a cap on what the pool has finished touching. */
static void refund(size_t charge) {
    atomic_fetch_sub(&requestsLive, 1);
    atomic_fetch_sub(&bytesInFlight, charge);
}

static void settle(Slot *slot, int status) {
    int expected = STATUS_PENDING;
    /* A canceled transfer keeps its verdict: the work finished, but nobody is
     * left who asked for it, so the bytes go nowhere. */
    if (!atomic_compare_exchange_strong(&slot->status, &expected, status)) {
        uv_mutex_lock(&slot->guard);
        free(slot->data);
        free(slot->reason);
        slot->data = NULL;
        slot->length = 0;
        slot->reason = NULL;
        uv_mutex_unlock(&slot->guard);
    }
    atomic_fetch_add(&settledCount, 1);
    uv_mutex_lock(&arrivalsGuard);
    arrivals++;
    uv_cond_broadcast(&arrivalsSignal);
    uv_mutex_unlock(&arrivalsGuard);
}

static void fail_slot(Slot *slot, int code, const char *what) {
    char scratch[512];
    snprintf(scratch, sizeof scratch, "%s: %s", what, uv_strerror(code));
    uv_mutex_lock(&slot->guard);
    slot->reason = malloc(strlen(scratch) + 1);
    if (slot->reason != NULL) {
        strcpy(slot->reason, scratch);
    }
    uv_mutex_unlock(&slot->guard);
    settle(slot, STATUS_FAILED);
}

/* --- the work ----------------------------------------------------------- */

static bool read_whole(Slot *slot, int *code) {
    uv_fs_t request;
    int64_t size;
    uint8_t *bytes;
    int64_t got = 0;

    /* Nonblocking, so a FIFO submitted as if it were a file refuses or reads
     * empty instead of wedging one of the pool's threads forever. */
    uv_fs_open(NULL, &request, slot->first, UV_FS_O_RDONLY | UV_FS_O_NONBLOCK, 0, NULL);
    if (request.result < 0) {
        *code = (int)request.result;
        uv_fs_req_cleanup(&request);
        return false;
    }
    {
        uv_file handle = (uv_file)request.result;
        uv_fs_req_cleanup(&request);
        uv_fs_fstat(NULL, &request, handle, NULL);
        if (request.result < 0) {
            *code = (int)request.result;
            uv_fs_req_cleanup(&request);
            uv_fs_close(NULL, &request, handle, NULL);
            uv_fs_req_cleanup(&request);
            return false;
        }
        size = (int64_t)request.statbuf.st_size;
        uv_fs_req_cleanup(&request);
        if (size > (int64_t)MAX_REQUEST_BYTES) {
            /* Priced at submission from a smaller size; a file that grew past
             * the ceiling in between must not buy what it never paid for. */
            uv_fs_close(NULL, &request, handle, NULL);
            uv_fs_req_cleanup(&request);
            *code = UV_EFBIG;
            return false;
        }
        bytes = malloc((size_t)size + 1);
        if (bytes == NULL) {
            uv_fs_close(NULL, &request, handle, NULL);
            uv_fs_req_cleanup(&request);
            *code = UV_ENOMEM;
            return false;
        }
        while (got < size) {
            uv_buf_t buffer = uv_buf_init((char *)bytes + got, (unsigned)(size - got));
            int64_t step;
            uv_fs_read(NULL, &request, handle, &buffer, 1, got, NULL);
            step = request.result;
            uv_fs_req_cleanup(&request);
            if (step < 0) {
                free(bytes);
                uv_fs_close(NULL, &request, handle, NULL);
                uv_fs_req_cleanup(&request);
                *code = (int)step;
                return false;
            }
            if (step == 0) {
                break;
            }
            got += step;
        }
        uv_fs_close(NULL, &request, handle, NULL);
        uv_fs_req_cleanup(&request);
    }
    bytes[got] = 0;
    uv_mutex_lock(&slot->guard);
    slot->data = bytes;
    slot->length = (size_t)got;
    uv_mutex_unlock(&slot->guard);
    return true;
}

/* Writes through a temporary beside the destination and moves it into place, so
 * a reader sees either the previous contents or the new ones and never a
 * half-written file. */
static bool write_atomic(Slot *slot, int *code) {
    uv_fs_t request;
    NuppBuffer temporary;
    const char *slash = strrchr(slot->first, '/');
    uint64_t stamp = 0;
    char stampText[17];
    uv_file handle;
    bool ok = true;
    bool keep = false;
    uint32_t keepMode = 0;

    /* The rename replaces the destination's inode, so an existing mode has to
     * come along; a fresh destination gets what `write_whole` would create. */
    uv_fs_stat(NULL, &request, slot->first, NULL);
    if (request.result >= 0) {
        keep = true;
        keepMode = (uint32_t)request.statbuf.st_mode & 07777u;
    }
    uv_fs_req_cleanup(&request);

    nupp_buffer_init(&temporary);
    if (slash != NULL) {
        nupp_buffer_append(&temporary, slot->first, (size_t)(slash - slot->first) + 1);
    }
    uv_random(NULL, NULL, &stamp, sizeof stamp, 0, NULL);
    snprintf(stampText, sizeof stampText, "%016llx", (unsigned long long)stamp);
    nupp_buffer_append(&temporary, ".nupp-write-", 12);
    nupp_buffer_append(&temporary, stampText, 16);
    nupp_buffer_push(&temporary, 0);
    if (temporary.failed) {
        nupp_buffer_free(&temporary);
        *code = UV_ENOMEM;
        return false;
    }

    uv_fs_open(NULL, &request, (const char *)temporary.data,
        UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_EXCL, keep ? 0600 : 0666, NULL);
    if (request.result < 0) {
        *code = (int)request.result;
        uv_fs_req_cleanup(&request);
        nupp_buffer_free(&temporary);
        return false;
    }
    handle = (uv_file)request.result;
    uv_fs_req_cleanup(&request);
    if (keep) {
        uv_fs_fchmod(NULL, &request, handle, (int)keepMode, NULL);
        if (request.result < 0) {
            *code = (int)request.result;
            ok = false;
        }
        uv_fs_req_cleanup(&request);
    }
    if (ok) {
        size_t written = 0;
        while (written < slot->contentsLength) {
            uv_buf_t buffer = uv_buf_init((char *)slot->contents + written,
                (unsigned)(slot->contentsLength - written));
            int64_t step;
            uv_fs_write(NULL, &request, handle, &buffer, 1, (int64_t)written, NULL);
            step = request.result;
            uv_fs_req_cleanup(&request);
            if (step < 0) {
                *code = (int)step;
                ok = false;
                break;
            }
            written += (size_t)step;
        }
    }
    if (ok) {
        uv_fs_fsync(NULL, &request, handle, NULL);
        if (request.result < 0) {
            *code = (int)request.result;
            ok = false;
        }
        uv_fs_req_cleanup(&request);
    }
    uv_fs_close(NULL, &request, handle, NULL);
    uv_fs_req_cleanup(&request);
    if (ok) {
        uv_fs_rename(NULL, &request, (const char *)temporary.data, slot->first, NULL);
        if (request.result < 0) {
            *code = (int)request.result;
            ok = false;
        }
        uv_fs_req_cleanup(&request);
    }
    if (!ok) {
        uv_fs_unlink(NULL, &request, (const char *)temporary.data, NULL);
        uv_fs_req_cleanup(&request);
    }
    nupp_buffer_free(&temporary);
    return ok;
}

static bool write_whole(Slot *slot, int *code) {
    uv_fs_t request;
    uv_file handle;
    size_t written = 0;
    bool ok = true;
    int flags = slot->mode == 1
        ? (UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_APPEND)
        : (UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_TRUNC);

    uv_fs_open(NULL, &request, slot->first, flags, 0666, NULL);
    if (request.result < 0) {
        *code = (int)request.result;
        uv_fs_req_cleanup(&request);
        return false;
    }
    handle = (uv_file)request.result;
    uv_fs_req_cleanup(&request);
    while (written < slot->contentsLength) {
        uv_buf_t buffer = uv_buf_init((char *)slot->contents + written,
            (unsigned)(slot->contentsLength - written));
        int64_t step;
        uv_fs_write(NULL, &request, handle, &buffer, 1,
            slot->mode == 1 ? -1 : (int64_t)written, NULL);
        step = request.result;
        uv_fs_req_cleanup(&request);
        if (step < 0) {
            *code = (int)step;
            ok = false;
            break;
        }
        written += (size_t)step;
    }
    uv_fs_close(NULL, &request, handle, NULL);
    uv_fs_req_cleanup(&request);
    return ok;
}

/* Runs on one of libuv's pool threads. */
static void perform(uv_work_t *work) {
    Slot *slot = work->data;
    int code = 0;
    bool ok;
    switch (slot->kind) {
        case WORK_READ: ok = read_whole(slot, &code); break;
        case WORK_WRITE:
            ok = slot->mode == 2 ? write_atomic(slot, &code) : write_whole(slot, &code);
            break;
        default: {
            uv_fs_t request;
            uv_fs_copyfile(NULL, &request, slot->first, slot->second, 0, NULL);
            ok = request.result >= 0;
            code = (int)request.result;
            uv_fs_req_cleanup(&request);
            break;
        }
    }
    if (ok) {
        settle(slot, STATUS_READY);
    } else {
        fail_slot(slot, code, slot->first);
    }
}

static void finished(uv_work_t *work, int status) {
    Slot *slot = work->data;
    if (status == UV_ECANCELED) {
        settle(slot, STATUS_CANCELED);
    }
    slot_release(slot);
}

/* Runs on the lane thread: the one place `uv_queue_work` and `uv_cancel` may
 * touch the lane's loop. Intake drains before cancellations so a cancel always
 * finds its work already queued. */
static void woken(uv_async_t *handle) {
    Slot *queue;
    Slot *cancels;
    (void)handle;
    uv_mutex_lock(&intakeGuard);
    queue = intakeFirst;
    intakeFirst = NULL;
    intakeLast = NULL;
    cancels = cancelFirst;
    cancelFirst = NULL;
    uv_mutex_unlock(&intakeGuard);
    while (queue != NULL) {
        Slot *slot = queue;
        int code;
        queue = slot->intakeNext;
        slot->intakeNext = NULL;
        code = uv_queue_work(&laneLoop, &slot->work, perform, finished);
        if (code != 0) {
            fail_slot(slot, code, slot->first);
            slot_release(slot);
        }
    }
    while (cancels != NULL) {
        Slot *slot = cancels;
        cancels = slot->cancelNext;
        slot->cancelNext = NULL;
        uv_cancel((uv_req_t *)&slot->work);
        slot_release(slot);
    }
}

static void lane_thread(void *unused) {
    (void)unused;
    uv_run(&laneLoop, UV_RUN_DEFAULT);
}

/* One lane per process, brought up the first time something is submitted. Every
 * caller into this library is on the thread that owns the Lua state, so two
 * submissions cannot race here. */
static bool ensure_lane(void) {
    int state = atomic_load(&laneStarted);
    if (state == 1) {
        return true;
    }
    /* A lane that failed to come up stays down: retrying would initialize
     * libuv objects a first attempt already initialized, which is undefined. */
    if (state != 0
        || uv_loop_init(&laneLoop) != 0
        || uv_async_init(&laneLoop, &laneWake, woken) != 0
        || uv_mutex_init(&arrivalsGuard) != 0
        || uv_cond_init(&arrivalsSignal) != 0
        || uv_mutex_init(&intakeGuard) != 0
        || uv_thread_create(&laneThread, lane_thread, NULL) != 0) {
        atomic_store(&laneStarted, -1);
        nupp_fail("cannot create the file transfer lane");
        return false;
    }
    atomic_store(&laneStarted, 1);
    return true;
}

static bool admit(size_t charge) {
    size_t live, held;
    if (charge > MAX_REQUEST_BYTES) {
        nupp_fail_format("the transfer is larger than the %u-byte limit",
            (unsigned)MAX_REQUEST_BYTES);
        return false;
    }
    live = atomic_fetch_add(&requestsLive, 1) + 1;
    if (live > MAX_REQUESTS) {
        atomic_fetch_sub(&requestsLive, 1);
        nupp_fail_format("more than %d transfers are in flight", MAX_REQUESTS);
        return false;
    }
    held = atomic_fetch_add(&bytesInFlight, charge) + charge;
    if (held > MAX_BYTES) {
        atomic_fetch_sub(&bytesInFlight, charge);
        atomic_fetch_sub(&requestsLive, 1);
        nupp_fail_format("transfers in flight would hold more than %u bytes",
            (unsigned)MAX_BYTES);
        return false;
    }
    return true;
}

static char *owned(const uint8_t *data, size_t length, const char *what) {
    NuppText text;
    char *copy;
    if (!nupp_text(&text, data, length, what)) {
        return NULL;
    }
    copy = malloc(text.length + 1);
    if (copy != NULL) {
        memcpy(copy, text.value, text.length + 1);
    }
    nupp_text_free(&text);
    return copy;
}

static NuppRequest *submit(Slot *slot, size_t charge) {
    NuppRequest *request;
    if (!ensure_lane() || !admit(charge)) {
        slot_release(slot);
        return NULL;
    }
    request = malloc(sizeof *request);
    if (request == NULL) {
        refund(charge);
        slot_release(slot);
        nupp_fail("out of memory");
        return NULL;
    }
    slot->charged = charge;
    /* One for the caller, one for the work. */
    atomic_store(&slot->references, 2);
    slot->work.data = slot;
    request->slot = slot;
    /* Queueing on the lane's loop is the lane thread's call to make; this
     * only leaves the slot where that thread will find it, and wakes it. */
    uv_mutex_lock(&intakeGuard);
    slot->intakeNext = NULL;
    if (intakeLast != NULL) {
        intakeLast->intakeNext = slot;
    } else {
        intakeFirst = slot;
    }
    intakeLast = slot;
    uv_mutex_unlock(&intakeGuard);
    uv_async_send(&laneWake);
    return request;
}

static Slot *new_slot(WorkKind kind) {
    Slot *slot = calloc(1, sizeof *slot);
    if (slot == NULL) {
        nupp_fail("out of memory");
        return NULL;
    }
    atomic_init(&slot->status, STATUS_PENDING);
    atomic_init(&slot->references, 1);
    if (uv_mutex_init(&slot->guard) != 0) {
        free(slot);
        nupp_fail("out of memory");
        return NULL;
    }
    slot->kind = kind;
    return slot;
}

/* Submits a whole-file read. The file is sized on this thread, because a lane
 * that cannot price a transfer cannot bound itself. */
NUPP_EXPORT NuppRequest *nuppFsSubmitRead(const uint8_t *data, size_t length) {
    uv_fs_t request;
    Slot *slot;
    char *path = owned(data, length, "path");
    size_t charge;
    if (path == NULL) {
        return NULL;
    }
    uv_fs_stat(NULL, &request, path, NULL);
    if (request.result < 0) {
        nupp_fail_format("%s: %s", path, uv_strerror((int)request.result));
        uv_fs_req_cleanup(&request);
        free(path);
        return NULL;
    }
    charge = (size_t)request.statbuf.st_size;
    uv_fs_req_cleanup(&request);
    slot = new_slot(WORK_READ);
    if (slot == NULL) {
        free(path);
        return NULL;
    }
    slot->first = path;
    return submit(slot, charge);
}

/* Submits a whole-file write. `mode` replaces, appends, or writes through a
 * temporary beside the destination, in that order. */
NUPP_EXPORT NuppRequest *nuppFsSubmitWrite(
    const uint8_t *data, size_t length,
    const uint8_t *bytes, size_t bytesLength, uint32_t mode
) {
    Slot *slot;
    char *path;
    if (bytes == NULL && bytesLength != 0) {
        nupp_fail("file contents are null");
        return NULL;
    }
    if (mode > 2) {
        nupp_fail("unknown write mode");
        return NULL;
    }
    path = owned(data, length, "path");
    if (path == NULL) {
        return NULL;
    }
    slot = new_slot(WORK_WRITE);
    if (slot == NULL) {
        free(path);
        return NULL;
    }
    slot->first = path;
    slot->contents = malloc(bytesLength + 1);
    if (slot->contents == NULL) {
        slot_release(slot);
        nupp_fail("out of memory");
        return NULL;
    }
    if (bytesLength != 0) {
        memcpy(slot->contents, bytes, bytesLength);
    }
    slot->contentsLength = bytesLength;
    slot->mode = mode;
    return submit(slot, bytesLength);
}

/* Submits a copy. The bytes never reach this process, so the lane charges the
 * transfer a slot rather than a size. */
NUPP_EXPORT NuppRequest *nuppFsSubmitCopy(
    const uint8_t *from, size_t fromLength, const uint8_t *to, size_t toLength
) {
    Slot *slot;
    char *source = owned(from, fromLength, "path");
    char *destination;
    if (source == NULL) {
        return NULL;
    }
    destination = owned(to, toLength, "destination path");
    if (destination == NULL) {
        free(source);
        return NULL;
    }
    slot = new_slot(WORK_COPY);
    if (slot == NULL) {
        free(source);
        free(destination);
        return NULL;
    }
    slot->first = source;
    slot->second = destination;
    return submit(slot, 0);
}

/* --- observing ---------------------------------------------------------- */

NUPP_EXPORT int32_t nuppFsStatus(const NuppRequest *request) {
    return request != NULL
        ? (int32_t)atomic_load(&request->slot->status) : STATUS_FAILED;
}

NUPP_EXPORT const uint8_t *nuppFsData(const NuppRequest *request) {
    const uint8_t *data;
    if (request == NULL) {
        return NULL;
    }
    uv_mutex_lock(&request->slot->guard);
    data = request->slot->data;
    uv_mutex_unlock(&request->slot->guard);
    return data;
}

NUPP_EXPORT size_t nuppFsLength(const NuppRequest *request) {
    size_t length;
    if (request == NULL) {
        return 0;
    }
    uv_mutex_lock(&request->slot->guard);
    length = request->slot->length;
    uv_mutex_unlock(&request->slot->guard);
    return length;
}

/* Copies a failed transfer's reason into the shared error slot and answers it,
 * so every failure is read the same way. */
NUPP_EXPORT const char *nuppFsError(const NuppRequest *request) {
    if (request != NULL) {
        uv_mutex_lock(&request->slot->guard);
        if (request->slot->reason != NULL) {
            nupp_fail(request->slot->reason);
        }
        uv_mutex_unlock(&request->slot->guard);
    }
    return nuppNativeError();
}

/* Abandons a pending transfer. The work still finishes if it has started; its
 * result is dropped, because a pool thread already reading cannot be recalled. */
NUPP_EXPORT bool nuppFsCancel(NuppRequest *request) {
    int expected = STATUS_PENDING;
    bool abandoned;
    if (request == NULL) {
        return false;
    }
    abandoned = atomic_compare_exchange_strong(
        &request->slot->status, &expected, STATUS_CANCELED);
    /* Skipping work the pool has not started yet is the lane thread's call to
     * make; this only asks for it. */
    if (abandoned && atomic_load(&laneStarted) == 1) {
        Slot *slot = request->slot;
        atomic_fetch_add(&slot->references, 1);
        uv_mutex_lock(&intakeGuard);
        slot->cancelNext = cancelFirst;
        cancelFirst = slot;
        uv_mutex_unlock(&intakeGuard);
        uv_async_send(&laneWake);
    }
    return abandoned;
}

NUPP_EXPORT void nuppFsDestroy(NuppRequest *request) {
    if (request != NULL) {
        size_t charge = request->slot->charged;
        slot_release(request->slot);
        free(request);
        refund(charge);
    }
}

/* How many transfers settled since the last poll, without waiting. This is the
 * readiness pump a scheduler drives. */
NUPP_EXPORT size_t nuppFsPoll(void) {
    if (atomic_load(&laneStarted) != 1) {
        return 0;
    }
    uv_mutex_lock(&arrivalsGuard);
    arrivals = 0;
    uv_mutex_unlock(&arrivalsGuard);
    return atomic_exchange(&settledCount, 0);
}

/* The same, sleeping up to a deadline for the first settlement. The count is
 * read under the same lock a worker raises it under, so a settlement that lands
 * between the check and the sleep is seen rather than slept through. */
NUPP_EXPORT size_t nuppFsWait(uint64_t milliseconds) {
    if (atomic_load(&laneStarted) != 1) {
        return 0;
    }
    uv_mutex_lock(&arrivalsGuard);
    if (arrivals == 0) {
        uv_cond_timedwait(&arrivalsSignal, &arrivalsGuard,
            milliseconds * (uint64_t)1000000);
    }
    arrivals = 0;
    uv_mutex_unlock(&arrivalsGuard);
    return atomic_exchange(&settledCount, 0);
}

NUPP_EXPORT size_t nuppFsPending(void) {
    return atomic_load(&requestsLive);
}
