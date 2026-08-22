/* Whole-file transfers, off the calling thread.
 *
 * A transfer is submitted, settles on a worker, and is observed by polling.
 * Nothing here calls Lua and nothing here blocks the submitter, which is what
 * lets one caller wait by sleeping and another wait by parking a task and
 * pumping this from its frame.
 *
 * The lane is bounded in three directions -- how many transfers may be live, how
 * many bytes they may hold between them, and how large one may be -- because a
 * queue that grows with its callers eventually takes the process with it.
 */

#include "platform.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STATUS_PENDING 0
#define STATUS_READY 1
#define STATUS_FAILED 2
#define STATUS_CANCELED 3

#define WORKERS 4
#define QUEUE_DEPTH 256
#define MAX_REQUESTS 128
#define MAX_BYTES (256u * 1024u * 1024u)
#define MAX_REQUEST_BYTES (256u * 1024u * 1024u)

/* --- the shared state --------------------------------------------------- */

typedef enum { WORK_READ, WORK_WRITE, WORK_COPY } WorkKind;

/* One transfer's shared state, held by the caller's handle and by the worker
 * that will settle it, and released by whichever lets go last. */
typedef struct {
    atomic_int status;
    atomic_int references;

    /* Guards everything below, which a worker writes once and a caller reads
     * after seeing a settled status. */
    NuppMutex *guard;
    uint8_t *data;
    size_t length;
    char *reason;

    size_t charged;
} Slot;

typedef struct {
    Slot *slot;
    WorkKind kind;
    char *first;
    char *second;
    uint8_t *contents;
    size_t contentsLength;
    uint32_t mode;
} Job;

struct NuppRequest {
    Slot *slot;
};

typedef struct NuppRequest NuppRequest;

static atomic_size_t requests_live;
static atomic_size_t bytes_in_flight;
static atomic_size_t settled_count;

/* The queue, its workers, and the arrival counter the pump reads, all created
 * on the first submission. A program that never touches a file never starts a
 * thread. */
static NuppMutex *lane_guard;
static NuppCondition *lane_not_empty;
static NuppCondition *lane_not_full;
static Job lane_queue[QUEUE_DEPTH];
static size_t lane_head;
static size_t lane_count;

static NuppMutex *arrivals_guard;
static NuppCondition *arrivals_signal;
static size_t arrivals;

static atomic_int lane_started;

/* --- lifetime ----------------------------------------------------------- */

static void slot_release(Slot *slot) {
    if (atomic_fetch_sub(&slot->references, 1) != 1) {
        return;
    }
    nupp_mutex_free(slot->guard);
    free(slot->data);
    free(slot->reason);
    free(slot);
}

static void job_free(Job *job) {
    free(job->first);
    free(job->second);
    free(job->contents);
}

/* Returns a transfer's share of the budget.
 *
 * This is tied to the caller's handle rather than to the shared state, which is
 * the difference between a cap on what a program is holding and a cap on what
 * the workers have finished touching. The second cannot be observed without a
 * race: a worker publishes READY from inside the state both sides share, so a
 * caller releasing the instant it sees the result is still counted until the
 * worker gets around to dropping its own reference.
 *
 * The cost is that a cancelled transfer is refunded while its worker may still
 * be reading. Those bytes are transient and belong to work already in flight;
 * what the cap exists to bound is what a caller can keep accumulating. */
static void refund(size_t charge) {
    atomic_fetch_sub(&requests_live, 1);
    atomic_fetch_sub(&bytes_in_flight, charge);
}

/* --- settling ----------------------------------------------------------- */

static void settle(Slot *slot, uint8_t *data, size_t length, char *reason, int status) {
    int expected = STATUS_PENDING;
    nupp_mutex_lock(slot->guard);
    slot->data = data;
    slot->length = length;
    slot->reason = reason;
    /* A canceled transfer keeps its verdict: the work finished, but nobody is
     * left who asked for it, so the bytes go nowhere. */
    if (!atomic_compare_exchange_strong(&slot->status, &expected, status)) {
        free(slot->data);
        free(slot->reason);
        slot->data = NULL;
        slot->length = 0;
        slot->reason = NULL;
    }
    nupp_mutex_unlock(slot->guard);

    atomic_fetch_add(&settled_count, 1);
    nupp_mutex_lock(arrivals_guard);
    arrivals++;
    nupp_condition_broadcast(arrivals_signal);
    nupp_mutex_unlock(arrivals_guard);
}

/* The reason a worker failed, copied out of the error slot -- which is per
 * thread, and the thread that will read it is not this one. */
static char *taken_reason(void) {
    const char *text = nuppNativeError();
    size_t length = strlen(text);
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, text, length + 1);
    return copy;
}

/* Writes through a temporary beside the destination and moves it into place, so
 * a reader sees either the previous contents or the new ones and never a
 * half-written file. */
static bool write_atomic(const char *path, const uint8_t *contents, size_t length) {
    NuppBuffer temporary;
    const char *slash = strrchr(path, '/');
    uint64_t stamp;
    char stampText[17];
    NuppFile *file;
    bool taken = false;
    bool ok;

    nupp_buffer_init(&temporary);
    if (slash != NULL) {
        nupp_buffer_append(&temporary, path, (size_t)(slash - path) + 1);
    }
    nupp_fs_random(&stamp, sizeof stamp);
    snprintf(stampText, sizeof stampText, "%016llx", (unsigned long long)stamp);
    nupp_buffer_append(&temporary, ".nupp-write-", 12);
    nupp_buffer_append(&temporary, stampText, 16);
    nupp_buffer_push(&temporary, 0);
    if (temporary.failed) {
        nupp_buffer_free(&temporary);
        nupp_fail("out of memory");
        return false;
    }

    file = nupp_fs_create_new((const char *)temporary.data, &taken);
    if (file == NULL) {
        if (taken) {
            nupp_fail("the temporary name for an atomic write was taken");
        }
        nupp_buffer_free(&temporary);
        return false;
    }
    ok = nupp_fs_write(file, contents, length) >= 0 && nupp_fs_sync(file);
    if (!nupp_fs_close(file)) {
        ok = false;
    }
    if (ok) {
        ok = nupp_fs_replace((const char *)temporary.data, path);
    }
    if (!ok) {
        nupp_fs_remove((const char *)temporary.data, false);
    }
    nupp_buffer_free(&temporary);
    return ok;
}

static void perform(Job *job) {
    NuppBuffer out;
    bool ok;
    switch (job->kind) {
        case WORK_READ:
            nupp_buffer_init(&out);
            if (!nupp_fs_read_whole(job->first, &out)) {
                nupp_buffer_free(&out);
                settle(job->slot, NULL, 0, taken_reason(), STATUS_FAILED);
                return;
            }
            {
                size_t length = out.length;
                uint8_t *data = out.data;
                /* An empty file still answers an allocation, so the pointer the
                 * binding reads is a real one whatever the length says. */
                if (data == NULL) {
                    data = malloc(1);
                    if (data == NULL) {
                        settle(job->slot, NULL, 0, taken_reason(), STATUS_FAILED);
                        return;
                    }
                    data[0] = 0;
                }
                nupp_buffer_init(&out);
                settle(job->slot, data, length, NULL, STATUS_READY);
            }
            return;

        case WORK_WRITE:
            if (job->mode == 2) {
                ok = write_atomic(job->first, job->contents, job->contentsLength);
            } else {
                ok = nupp_fs_write_whole(
                    job->first, job->contents, job->contentsLength, job->mode == 1);
            }
            break;

        case WORK_COPY:
        default:
            ok = nupp_fs_copy(job->first, job->second);
            break;
    }
    if (ok) {
        settle(job->slot, NULL, 0, NULL, STATUS_READY);
    } else {
        settle(job->slot, NULL, 0, taken_reason(), STATUS_FAILED);
    }
}

static void worker(void *unused) {
    (void)unused;
    for (;;) {
        Job job;
        nupp_mutex_lock(lane_guard);
        while (lane_count == 0) {
            nupp_condition_wait(lane_not_empty, lane_guard);
        }
        job = lane_queue[lane_head];
        lane_head = (lane_head + 1) % QUEUE_DEPTH;
        lane_count--;
        nupp_condition_signal(lane_not_full);
        nupp_mutex_unlock(lane_guard);

        perform(&job);
        job_free(&job);
        slot_release(job.slot);
    }
}

/* --- starting ----------------------------------------------------------- */

/* One lane per process, brought up the first time something is submitted.
 *
 * The double check is not an optimisation. Every caller into this library is on
 * the thread that owns the Lua state, so two submissions cannot race here; what
 * the flag prevents is the second submission paying for the check again. */
static bool ensure_lane(void) {
    int index;
    if (atomic_load(&lane_started) == 1) {
        return true;
    }
    lane_guard = nupp_mutex_new();
    lane_not_empty = nupp_condition_new();
    lane_not_full = nupp_condition_new();
    arrivals_guard = nupp_mutex_new();
    arrivals_signal = nupp_condition_new();
    if (lane_guard == NULL || lane_not_empty == NULL || lane_not_full == NULL
        || arrivals_guard == NULL || arrivals_signal == NULL) {
        nupp_fail("cannot create the file transfer lane");
        return false;
    }
    for (index = 0; index < WORKERS; index++) {
        if (!nupp_thread_spawn(worker, NULL)) {
            return false;
        }
    }
    atomic_store(&lane_started, 1);
    return true;
}

static bool admit(size_t charge) {
    size_t live, held;
    if (charge > MAX_REQUEST_BYTES) {
        nupp_fail_format(
            "the transfer is larger than the %u-byte limit", (unsigned)MAX_REQUEST_BYTES);
        return false;
    }
    live = atomic_fetch_add(&requests_live, 1) + 1;
    if (live > MAX_REQUESTS) {
        atomic_fetch_sub(&requests_live, 1);
        nupp_fail_format("more than %d transfers are in flight", MAX_REQUESTS);
        return false;
    }
    held = atomic_fetch_add(&bytes_in_flight, charge) + charge;
    if (held > MAX_BYTES) {
        atomic_fetch_sub(&bytes_in_flight, charge);
        atomic_fetch_sub(&requests_live, 1);
        nupp_fail_format(
            "transfers in flight would hold more than %u bytes", (unsigned)MAX_BYTES);
        return false;
    }
    return true;
}

static NuppRequest *submit(Job *job, size_t charge) {
    Slot *slot;
    NuppRequest *request;

    if (!ensure_lane()) {
        job_free(job);
        return NULL;
    }
    if (!admit(charge)) {
        job_free(job);
        return NULL;
    }
    slot = malloc(sizeof *slot);
    request = malloc(sizeof *request);
    if (slot == NULL || request == NULL) {
        free(slot);
        free(request);
        job_free(job);
        refund(charge);
        nupp_fail("out of memory");
        return NULL;
    }
    atomic_init(&slot->status, STATUS_PENDING);
    atomic_init(&slot->references, 2); /* this handle, and the job */
    slot->guard = nupp_mutex_new();
    slot->data = NULL;
    slot->length = 0;
    slot->reason = NULL;
    slot->charged = charge;
    if (slot->guard == NULL) {
        free(slot);
        free(request);
        job_free(job);
        refund(charge);
        nupp_fail("out of memory");
        return NULL;
    }
    job->slot = slot;
    request->slot = slot;

    nupp_mutex_lock(lane_guard);
    while (lane_count == QUEUE_DEPTH) {
        nupp_condition_wait(lane_not_full, lane_guard);
    }
    lane_queue[(lane_head + lane_count) % QUEUE_DEPTH] = *job;
    lane_count++;
    nupp_condition_signal(lane_not_empty);
    nupp_mutex_unlock(lane_guard);
    return request;
}

/* --- submitting --------------------------------------------------------- */

/* A path argument, copied because the job outlives the call that made it. */
static char *owned_path(const uint8_t *data, size_t length, const char *what) {
    NuppText text;
    char *copy;
    if (!nupp_text(&text, data, length, what)) {
        return NULL;
    }
    copy = malloc(text.length + 1);
    if (copy == NULL) {
        nupp_text_free(&text);
        nupp_fail("out of memory");
        return NULL;
    }
    memcpy(copy, text.value, text.length + 1);
    nupp_text_free(&text);
    return copy;
}

/* Submits a whole-file read. The file is sized on this thread, because a lane
 * that cannot price a transfer cannot bound itself. */
NUPP_EXPORT NuppRequest *nuppFsSubmitRead(const uint8_t *data, size_t length) {
    Job job;
    NuppFileInfo info;
    char *path = owned_path(data, length, "path");
    if (path == NULL) {
        return NULL;
    }
    if (!nupp_fs_stat(path, true, &info)) {
        free(path);
        return NULL;
    }
    memset(&job, 0, sizeof job);
    job.kind = WORK_READ;
    job.first = path;
    return submit(&job, (size_t)info.size);
}

/* Submits a whole-file write. `mode` replaces, appends, or writes through a
 * temporary beside the destination, in that order. */
NUPP_EXPORT NuppRequest *nuppFsSubmitWrite(
    const uint8_t *data, size_t length,
    const uint8_t *bytes, size_t bytesLength,
    uint32_t mode
) {
    Job job;
    char *path;
    uint8_t *contents;

    if (bytes == NULL && bytesLength != 0) {
        nupp_fail("file contents are null");
        return NULL;
    }
    if (mode > 2) {
        nupp_fail("unknown write mode");
        return NULL;
    }
    path = owned_path(data, length, "path");
    if (path == NULL) {
        return NULL;
    }
    contents = malloc(bytesLength + 1);
    if (contents == NULL) {
        free(path);
        nupp_fail("out of memory");
        return NULL;
    }
    if (bytesLength != 0) {
        memcpy(contents, bytes, bytesLength);
    }
    memset(&job, 0, sizeof job);
    job.kind = WORK_WRITE;
    job.first = path;
    job.contents = contents;
    job.contentsLength = bytesLength;
    job.mode = mode;
    return submit(&job, bytesLength);
}

/* Submits a copy. The bytes never reach this process, so the lane charges the
 * transfer a slot rather than a size. */
NUPP_EXPORT NuppRequest *nuppFsSubmitCopy(
    const uint8_t *from, size_t fromLength, const uint8_t *to, size_t toLength
) {
    Job job;
    char *source = owned_path(from, fromLength, "path");
    char *destination;
    if (source == NULL) {
        return NULL;
    }
    destination = owned_path(to, toLength, "destination path");
    if (destination == NULL) {
        free(source);
        return NULL;
    }
    memset(&job, 0, sizeof job);
    job.kind = WORK_COPY;
    job.first = source;
    job.second = destination;
    return submit(&job, 0);
}

/* --- observing ---------------------------------------------------------- */

/* Answers whether a transfer is pending, ready, failed, or canceled. */
NUPP_EXPORT int32_t nuppFsStatus(const NuppRequest *request) {
    if (request == NULL) {
        return STATUS_FAILED;
    }
    return (int32_t)atomic_load(&request->slot->status);
}

/* Answers a settled read's bytes. Valid until the transfer is destroyed. */
NUPP_EXPORT const uint8_t *nuppFsData(const NuppRequest *request) {
    const uint8_t *data;
    if (request == NULL) {
        return NULL;
    }
    nupp_mutex_lock(request->slot->guard);
    data = request->slot->data;
    nupp_mutex_unlock(request->slot->guard);
    return data;
}

/* Answers a settled read's byte count. */
NUPP_EXPORT size_t nuppFsLength(const NuppRequest *request) {
    size_t length;
    if (request == NULL) {
        return 0;
    }
    nupp_mutex_lock(request->slot->guard);
    length = request->slot->length;
    nupp_mutex_unlock(request->slot->guard);
    return length;
}

/* Copies a failed transfer's reason into the shared error slot and answers it,
 * so every failure is read the same way. */
NUPP_EXPORT const char *nuppFsError(const NuppRequest *request) {
    if (request != NULL) {
        nupp_mutex_lock(request->slot->guard);
        if (request->slot->reason != NULL) {
            nupp_fail(request->slot->reason);
        }
        nupp_mutex_unlock(request->slot->guard);
    }
    return nuppNativeError();
}

/* Abandons a pending transfer. The work still finishes; its result is dropped,
 * because a worker already reading cannot be recalled. */
NUPP_EXPORT bool nuppFsCancel(NuppRequest *request) {
    int expected = STATUS_PENDING;
    if (request == NULL) {
        return false;
    }
    return atomic_compare_exchange_strong(
        &request->slot->status, &expected, STATUS_CANCELED);
}

/* Releases the caller's handle and its share of the lane's budget. */
NUPP_EXPORT void nuppFsDestroy(NuppRequest *request) {
    if (request != NULL) {
        size_t charge = request->slot->charged;
        slot_release(request->slot);
        free(request);
        refund(charge);
    }
}

/* Answers how many transfers settled since the last poll, without waiting. This
 * is the readiness pump a scheduler drives. */
NUPP_EXPORT size_t nuppFsPoll(void) {
    if (atomic_load(&lane_started) != 1) {
        return 0;
    }
    nupp_mutex_lock(arrivals_guard);
    arrivals = 0;
    nupp_mutex_unlock(arrivals_guard);
    return atomic_exchange(&settled_count, 0);
}

/* The same, sleeping up to a deadline for the first settlement. This is what
 * keeps a program with no scheduler from spinning on a status.
 *
 * The count is read under the same lock a worker raises it under, so a
 * settlement that lands between the check and the sleep is seen rather than
 * slept through. */
NUPP_EXPORT size_t nuppFsWait(uint64_t milliseconds) {
    if (atomic_load(&lane_started) != 1) {
        return 0;
    }
    nupp_mutex_lock(arrivals_guard);
    if (arrivals == 0) {
        nupp_condition_wait_for(arrivals_signal, arrivals_guard, milliseconds);
    }
    arrivals = 0;
    nupp_mutex_unlock(arrivals_guard);
    return atomic_exchange(&settled_count, 0);
}

/* How many transfers the caller still holds. */
NUPP_EXPORT size_t nuppFsPending(void) {
    return atomic_load(&requests_live);
}
