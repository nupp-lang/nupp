/* Bounded byte channels and fresh-state worker threads.
 *
 * Lua owns validation, serialization and request routing. This owns only byte
 * copies, thread lifecycle, and bootstrapping the selected module in another
 * LuaJIT state.
 */

#include "nupp_host.h"

#if NUPP_FEATURE_WORKERS

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#   include <windows.h>
#else
#   include <pthread.h>
#   include <sys/time.h>
#   include <time.h>
#endif

#define MAX_CHANNEL_MESSAGES 1024u
#define MAX_CHANNEL_BYTES (256u * 1024u * 1024u)

/* --- threads ------------------------------------------------------------ */

#if defined(_WIN32)
typedef CRITICAL_SECTION Mutex;
typedef CONDITION_VARIABLE Condition;
typedef HANDLE Thread;
#   define MUTEX_INIT(m) InitializeCriticalSection(m)
#   define MUTEX_FREE(m) DeleteCriticalSection(m)
#   define MUTEX_LOCK(m) EnterCriticalSection(m)
#   define MUTEX_UNLOCK(m) LeaveCriticalSection(m)
#   define CONDITION_INIT(c) InitializeConditionVariable(c)
#   define CONDITION_FREE(c) ((void)(c))
#   define CONDITION_WAKE_ONE(c) WakeConditionVariable(c)
#   define CONDITION_WAKE_ALL(c) WakeAllConditionVariable(c)
#else
typedef pthread_mutex_t Mutex;
typedef pthread_cond_t Condition;
typedef pthread_t Thread;
#   define MUTEX_INIT(m) pthread_mutex_init(m, NULL)
#   define MUTEX_FREE(m) pthread_mutex_destroy(m)
#   define MUTEX_LOCK(m) pthread_mutex_lock(m)
#   define MUTEX_UNLOCK(m) pthread_mutex_unlock(m)
#   define CONDITION_INIT(c) pthread_cond_init(c, NULL)
#   define CONDITION_FREE(c) pthread_cond_destroy(c)
#   define CONDITION_WAKE_ONE(c) pthread_cond_signal(c)
#   define CONDITION_WAKE_ALL(c) pthread_cond_broadcast(c)
#endif

/* --- channels ----------------------------------------------------------- */

typedef struct Message {
    struct Message *next;
    size_t length;
    uint8_t bytes[1];
} Message;

typedef struct {
    Mutex guard;
    Condition arrived;
    Message *head;
    Message *tail;
    size_t count;
    size_t bytes;
    bool closed;
} Channel;

static Channel *channel_new(void) {
    Channel *channel = calloc(1, sizeof *channel);
    if (channel != NULL) {
        MUTEX_INIT(&channel->guard);
        CONDITION_INIT(&channel->arrived);
    }
    return channel;
}

static void channel_free(Channel *channel) {
    Message *message;
    if (channel == NULL) {
        return;
    }
    message = channel->head;
    while (message != NULL) {
        Message *next = message->next;
        free(message);
        message = next;
    }
    MUTEX_FREE(&channel->guard);
    CONDITION_FREE(&channel->arrived);
    free(channel);
}

static void channel_close(Channel *channel) {
    if (channel == NULL) {
        return;
    }
    MUTEX_LOCK(&channel->guard);
    channel->closed = true;
    CONDITION_WAKE_ALL(&channel->arrived);
    MUTEX_UNLOCK(&channel->guard);
}

/* Refuses rather than grows. A channel that accepts everything offered turns a
 * producer that outruns its consumer into a process that runs out of memory. */
static bool channel_push(Channel *channel, const uint8_t *bytes, size_t length) {
    Message *message;
    if (channel == NULL) {
        return false;
    }
    MUTEX_LOCK(&channel->guard);
    if (channel->closed || channel->count >= MAX_CHANNEL_MESSAGES
        || channel->bytes + length > MAX_CHANNEL_BYTES) {
        MUTEX_UNLOCK(&channel->guard);
        return false;
    }
    message = malloc(sizeof *message + length);
    if (message == NULL) {
        MUTEX_UNLOCK(&channel->guard);
        return false;
    }
    message->next = NULL;
    message->length = length;
    if (length != 0) {
        memcpy(message->bytes, bytes, length);
    }
    if (channel->tail != NULL) {
        channel->tail->next = message;
    } else {
        channel->head = message;
    }
    channel->tail = message;
    channel->count++;
    channel->bytes += length;
    CONDITION_WAKE_ONE(&channel->arrived);
    MUTEX_UNLOCK(&channel->guard);
    return true;
}

#if !defined(_WIN32)
static void deadline_after(struct timespec *out, int milliseconds) {
    struct timeval now;
    gettimeofday(&now, NULL);
    out->tv_sec = now.tv_sec + milliseconds / 1000;
    out->tv_nsec = now.tv_usec * 1000 + (long)(milliseconds % 1000) * 1000000L;
    if (out->tv_nsec >= 1000000000L) {
        out->tv_sec += 1;
        out->tv_nsec -= 1000000000L;
    }
}
#endif

/* A negative timeout waits until something arrives or the channel closes; zero
 * takes whatever is already there. A closed and drained channel answers nothing
 * rather than waiting for a sender that will not come. */
static Message *channel_pop(Channel *channel, int timeoutMs) {
    Message *message;
    if (channel == NULL) {
        return NULL;
    }
    MUTEX_LOCK(&channel->guard);
    if (timeoutMs < 0) {
        while (channel->head == NULL && !channel->closed) {
#if defined(_WIN32)
            SleepConditionVariableCS(&channel->arrived, &channel->guard, INFINITE);
#else
            pthread_cond_wait(&channel->arrived, &channel->guard);
#endif
        }
    } else if (timeoutMs > 0) {
#if defined(_WIN32)
        DWORD started = GetTickCount();
        while (channel->head == NULL && !channel->closed) {
            DWORD spent = GetTickCount() - started;
            if (spent >= (DWORD)timeoutMs) {
                break;
            }
            if (!SleepConditionVariableCS(
                    &channel->arrived, &channel->guard, (DWORD)timeoutMs - spent)) {
                break;
            }
        }
#else
        struct timespec deadline;
        deadline_after(&deadline, timeoutMs);
        while (channel->head == NULL && !channel->closed) {
            if (pthread_cond_timedwait(&channel->arrived, &channel->guard, &deadline) != 0) {
                break;
            }
        }
#endif
    }
    message = channel->head;
    if (message != NULL) {
        channel->head = message->next;
        if (channel->head == NULL) {
            channel->tail = NULL;
        }
        channel->count--;
        channel->bytes -= message->length;
    }
    MUTEX_UNLOCK(&channel->guard);
    return message;
}

/* --- the payload workers run -------------------------------------------- */

static uint8_t *workerPayload;
static size_t workerPayloadLength;

void nupp_host_workers_set_payload(const uint8_t *bytes, size_t length) {
    uint8_t *copy;
    if (workerPayload != NULL) {
        return;
    }
    copy = malloc(length + 1);
    if (copy == NULL) {
        return;
    }
    memcpy(copy, bytes, length);
    copy[length] = 0;
    workerPayload = copy;
    workerPayloadLength = length;
}

typedef struct {
    char *entry;
    Channel *inbox;
    Channel *outbox;
    Mutex guard;
    char *failure;
    int status;
    bool finished;
    Thread thread;
} Worker;

static void worker_body(Worker *worker) {
    char *problem = NULL;
    NuppRuntime *runtime;

    /* The arena reserved before any of this was loaded is given back here, so
     * the state about to be created can place its machine code near the
     * interpreter. */
    nupp_host_mcode_release();
    runtime = nupp_host_runtime_new(true, &problem);
    if (runtime != NULL) {
        lua_State *state = nupp_host_runtime_state(runtime);
        lua_pushlightuserdata(state, worker->inbox);
        lua_setfield(state, LUA_GLOBALSINDEX, "__nuppWorkerIn");
        lua_pushlightuserdata(state, worker->outbox);
        lua_setfield(state, LUA_GLOBALSINDEX, "__nuppWorkerOut");
        lua_pushstring(state, worker->entry);
        lua_setfield(state, LUA_GLOBALSINDEX, "__nuppWorkerEntry");
        free(nupp_host_set_arguments(runtime, 0, NULL));
        problem = nupp_host_run(runtime, workerPayload, workerPayloadLength, "=nupp-worker");
        nupp_host_runtime_free(runtime);
    }
    /* Both ends close whatever happened, so a reader on the other side of a
     * worker that died is told rather than left waiting. */
    channel_close(worker->inbox);
    channel_close(worker->outbox);
    MUTEX_LOCK(&worker->guard);
    worker->failure = problem;
    worker->status = problem != NULL ? 1 : 0;
    worker->finished = true;
    MUTEX_UNLOCK(&worker->guard);
}

#if defined(_WIN32)
static DWORD WINAPI worker_trampoline(LPVOID raw) {
    worker_body(raw);
    return 0;
}
#else
static void *worker_trampoline(void *raw) {
    worker_body(raw);
    return NULL;
}
#endif

/* --- the Lua surface ---------------------------------------------------- */

static int channel_create(lua_State *state) {
    lua_pushlightuserdata(state, channel_new());
    return 1;
}

static int channel_destroy(lua_State *state) {
    channel_free(lua_touserdata(state, 1));
    return 0;
}

static int channel_close_entry(lua_State *state) {
    channel_close(lua_touserdata(state, 1));
    return 0;
}

static int channel_push_entry(lua_State *state) {
    size_t length = 0;
    const char *bytes = lua_tolstring(state, 2, &length);
    bool accepted = bytes != NULL
        && channel_push(lua_touserdata(state, 1), (const uint8_t *)bytes, length);
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

static int channel_pop_entry(lua_State *state) {
    lua_Integer timeout = lua_tointeger(state, 2);
    Message *message = channel_pop(
        lua_touserdata(state, 1),
        timeout < -2147483647 ? -2147483647 : timeout > 2147483647 ? 2147483647 : (int)timeout);
    if (message == NULL) {
        lua_pushnil(state);
    } else {
        lua_pushlstring(state, (const char *)message->bytes, message->length);
        free(message);
    }
    return 1;
}

static int channel_count_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t count = 0;
    if (channel != NULL) {
        MUTEX_LOCK(&channel->guard);
        count = channel->count;
        MUTEX_UNLOCK(&channel->guard);
    }
    lua_pushinteger(state, (lua_Integer)count);
    return 1;
}

static int channel_closed_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    bool closed = true;
    if (channel != NULL) {
        MUTEX_LOCK(&channel->guard);
        closed = channel->closed;
        MUTEX_UNLOCK(&channel->guard);
    }
    lua_pushboolean(state, closed ? 1 : 0);
    return 1;
}

static int worker_spawn(lua_State *state) {
    size_t length = 0;
    const char *entry = lua_tolstring(state, 1, &length);
    Channel *inbox = lua_touserdata(state, 2);
    Channel *outbox = lua_touserdata(state, 3);
    Worker *worker;

    if (entry == NULL) {
        lua_pushnil(state);
        lua_pushstring(state, "worker entry must be a string");
        return 2;
    }
    if (workerPayload == NULL) {
        lua_pushnil(state);
        lua_pushstring(state, "workers require a stamped Nupp payload");
        return 2;
    }
    if (inbox == NULL || outbox == NULL) {
        lua_pushnil(state);
        lua_pushstring(state, "worker channels are missing");
        return 2;
    }
    worker = calloc(1, sizeof *worker);
    if (worker == NULL) {
        lua_pushnil(state);
        lua_pushstring(state, "cannot start worker: out of memory");
        return 2;
    }
    worker->entry = malloc(length + 1);
    if (worker->entry == NULL) {
        free(worker);
        lua_pushnil(state);
        lua_pushstring(state, "cannot start worker: out of memory");
        return 2;
    }
    memcpy(worker->entry, entry, length);
    worker->entry[length] = '\0';
    worker->inbox = inbox;
    worker->outbox = outbox;
    MUTEX_INIT(&worker->guard);

#if defined(_WIN32)
    worker->thread = CreateThread(NULL, 0, worker_trampoline, worker, 0, NULL);
    if (worker->thread == NULL) {
#else
    if (pthread_create(&worker->thread, NULL, worker_trampoline, worker) != 0) {
#endif
        MUTEX_FREE(&worker->guard);
        free(worker->entry);
        free(worker);
        lua_pushnil(state);
        lua_pushstring(state, "cannot start worker");
        return 2;
    }
    lua_pushlightuserdata(state, worker);
    return 1;
}

static int worker_finished(lua_State *state) {
    Worker *worker = lua_touserdata(state, 1);
    bool finished = true;
    if (worker != NULL) {
        MUTEX_LOCK(&worker->guard);
        finished = worker->finished;
        MUTEX_UNLOCK(&worker->guard);
    }
    lua_pushboolean(state, finished ? 1 : 0);
    return 1;
}

static int worker_join(lua_State *state) {
    Worker *worker = lua_touserdata(state, 1);
    char *failure;
    int status;
    if (worker == NULL) {
        lua_pushinteger(state, 1);
        lua_pushstring(state, "worker handle is missing");
        return 2;
    }
#if defined(_WIN32)
    WaitForSingleObject(worker->thread, INFINITE);
    CloseHandle(worker->thread);
#else
    pthread_join(worker->thread, NULL);
#endif
    MUTEX_LOCK(&worker->guard);
    failure = worker->failure;
    status = worker->status;
    worker->failure = NULL;
    MUTEX_UNLOCK(&worker->guard);
    lua_pushinteger(state, status);
    if (failure != NULL) {
        lua_pushstring(state, failure);
        free(failure);
    } else {
        lua_pushnil(state);
    }
    MUTEX_FREE(&worker->guard);
    free(worker->entry);
    free(worker);
    return 2;
}

/* The channels this worker was started with, which is how code inside one finds
 * the ends it is supposed to speak through. */
static int current(lua_State *state) {
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppWorkerIn");
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppWorkerOut");
    return 2;
}

static int now(lua_State *state) {
    extern double nupp_monotonic_ms(void);
    lua_pushnumber(state, nupp_monotonic_ms());
    return 1;
}

static void field(lua_State *state, const char *name, lua_CFunction function) {
    lua_pushcclosure(state, function, 0);
    lua_setfield(state, -2, name);
}

int nupp_host_workers_open(lua_State *state) {
    lua_createtable(state, 0, 12);
    field(state, "channelCreate", channel_create);
    field(state, "channelDestroy", channel_destroy);
    field(state, "channelClose", channel_close_entry);
    field(state, "channelPush", channel_push_entry);
    field(state, "channelPop", channel_pop_entry);
    field(state, "channelCount", channel_count_entry);
    field(state, "channelClosed", channel_closed_entry);
    field(state, "workerSpawn", worker_spawn);
    field(state, "workerFinished", worker_finished);
    field(state, "workerJoin", worker_join);
    field(state, "current", current);
    field(state, "now", now);
    return 1;
}

#endif /* NUPP_FEATURE_WORKERS */
