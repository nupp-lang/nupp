/* Bounded message channels and fresh-state worker threads.
 *
 * Lua owns validation and request routing. Dynamically shaped values retain the
 * byte codec; predefined scalar frames stay native from enqueue through dequeue.
 * This also owns thread lifecycle and bootstrapping a scheduler lane in another
 * LuaJIT state.
 */

#include "nupp_host.h"

#if NUPP_FEATURE_WORKERS

#include <stdlib.h>
#include <string.h>
#include <math.h>

#if defined(_WIN32)
#   include <windows.h>
#else
#   include <pthread.h>
#   include <unistd.h>
#   include <sys/time.h>
#   include <time.h>
#endif

#define MAX_CHANNEL_MESSAGES 1024u
#define MAX_CHANNEL_BYTES (256u * 1024u * 1024u)
#define MAX_CHANNEL_SCHEMAS 254u
#define MAX_SCHEMA_FIELDS 16u

/* The one native monotonic provider exported by the Rust base runtime. Worker
 * deadlines read it rather than defining another clock surface here. */
extern uint64_t nuppNativeV2MonotonicNs(void);

static double monotonic_ms(void) {
    return (double)nuppNativeV2MonotonicNs() / 1.0e6;
}

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

/* One allocation riding a message. A region attachment retains an engine
 * block beside the extent the sender's handle named (NEP 22); a moved
 * attachment owns a malloc allocation outright, and whoever destroys the
 * message unread frees it, exactly once (NEP 23). For a moved attachment
 * `first` carries the element count and `length` the layout tag. */
#define ATTACHMENT_REGION 0
#define ATTACHMENT_MOVED 1

typedef struct {
    int kind;
    void *block;
    size_t first;
    size_t length;
} RegionAttachment;

#define MAX_MESSAGE_ATTACHMENTS 255u

typedef struct Message {
    struct Message *next;
    int kind;
    lua_Integer id;
    lua_Number number;
    uint16_t schemaId;
    uint16_t attachmentCount;
    size_t attachmentOffset;
    size_t recordOffset;
    size_t headerLength;
    size_t bodyLength;
    size_t valueLength;
    uint8_t bytes[1];
} Message;

static void message_release_attachments(Message *message) {
    if (message->attachmentCount != 0) {
        RegionAttachment *attachments =
            (RegionAttachment *)(void *)(message->bytes + message->attachmentOffset);
        size_t index;
        for (index = 0; index < message->attachmentCount; index++) {
            if (attachments[index].kind == ATTACHMENT_MOVED) {
                free(attachments[index].block);
            } else {
                nupp_host_region_release(attachments[index].block);
            }
        }
        message->attachmentCount = 0;
    }
}

enum {
    MESSAGE_BYTES = 0,
    MESSAGE_NUMBER_TASK = 1,
    MESSAGE_NUMBER_REPLY = 2,
    MESSAGE_STRING_TASK = 3,
    MESSAGE_STRING_REPLY = 4,
    MESSAGE_RECORD_TASK = 5,
    MESSAGE_RECORD_REPLY = 6,
    MESSAGE_BUFFER_TASK = 7,
    MESSAGE_BUFFER_REPLY = 8
};

#define MAX_CHANNEL_DICT 256u

enum {
    SCHEMA_NUMBER = 0,
    SCHEMA_STRING = 1,
    SCHEMA_BOOLEAN = 2
};

/* An optional stored field keeps its primitive kind and adds this flag; a
 * missing value travels as a cleared presence mark rather than a rejection. */
#define SCHEMA_OPTIONAL 4
#define SCHEMA_BASE(kind) ((kind) & 3)

typedef struct {
    char *name;
    size_t nameLength;
    int kind;
} SchemaField;

typedef struct {
    uint16_t id;
    char *key;
    size_t keyLength;
    char *address;
    size_t addressLength;
    size_t fieldCount;
    SchemaField fields[MAX_SCHEMA_FIELDS];
} Schema;

typedef struct {
    Mutex guard;
    Condition arrived;
    Message *head;
    Message *tail;
    size_t count;
    size_t bytes;
    size_t schemaCount;
    Schema schemas[MAX_CHANNEL_SCHEMAS];
    /* An ordered, append-only serializer dictionary of record addresses for
     * the byte-codec fallback. Each state materializes index to metatable
     * lazily, so messages carry dictionary indexes rather than addresses. */
    char *dict[MAX_CHANNEL_DICT];
    size_t dictLengths[MAX_CHANNEL_DICT];
    size_t dictCount;
    bool closed;
} Channel;

typedef enum {
    TASK_QUEUED = 1,
    TASK_RUNNING = 2,
    TASK_CANCEL_REQUESTED = 3,
    TASK_CANCELLED = 4,
    TASK_DONE = 5
} WorkerTaskStatus;

typedef struct WorkerTask {
    struct WorkerTask *next;
    lua_Integer id;
    double deadline;
    bool hasDeadline;
    WorkerTaskStatus status;
} WorkerTask;

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
    size_t schemaIndex;
    if (channel == NULL) {
        return;
    }
    message = channel->head;
    while (message != NULL) {
        Message *next = message->next;
        message_release_attachments(message);
        free(message);
        message = next;
    }
    for (schemaIndex = 0; schemaIndex < channel->schemaCount; schemaIndex++) {
        Schema *schema = &channel->schemas[schemaIndex];
        size_t fieldIndex;
        free(schema->key);
        free(schema->address);
        for (fieldIndex = 0; fieldIndex < schema->fieldCount; fieldIndex++) {
            free(schema->fields[fieldIndex].name);
        }
    }
    for (schemaIndex = 0; schemaIndex < channel->dictCount; schemaIndex++) {
        free(channel->dict[schemaIndex]);
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

static char *copy_bytes(const char *bytes, size_t length) {
    char *copy = malloc(length + 1);
    if (copy != NULL) {
        if (length != 0) {
            memcpy(copy, bytes, length);
        }
        copy[length] = '\0';
    }
    return copy;
}

static int schema_kind(const char *name, size_t length) {
    int optional = 0;
    if (length > 0 && name[length - 1] == '?') {
        optional = SCHEMA_OPTIONAL;
        length--;
    }
    if (length == 6 && memcmp(name, "number", 6) == 0) {
        return SCHEMA_NUMBER | optional;
    }
    if (length == 6 && memcmp(name, "string", 6) == 0) {
        return SCHEMA_STRING | optional;
    }
    if (length == 7 && memcmp(name, "boolean", 7) == 0) {
        return SCHEMA_BOOLEAN | optional;
    }
    return -1;
}

static void schema_discard(Schema *schema) {
    size_t index;
    free(schema->key);
    free(schema->address);
    for (index = 0; index < schema->fieldCount; index++) {
        free(schema->fields[index].name);
    }
    memset(schema, 0, sizeof *schema);
}

static Schema *channel_schema_by_key(Channel *channel,
                                     const char *key,
                                     size_t keyLength) {
    size_t index;
    for (index = 0; index < channel->schemaCount; index++) {
        Schema *schema = &channel->schemas[index];
        if (schema->keyLength == keyLength
            && memcmp(schema->key, key, keyLength) == 0) {
            return schema;
        }
    }
    return NULL;
}

static Schema *channel_schema_by_id(Channel *channel, uint16_t id) {
    size_t index = id >= 2 ? (size_t)id - 2 : MAX_CHANNEL_SCHEMAS;
    return index < channel->schemaCount ? &channel->schemas[index] : NULL;
}

/* Defines one immutable channel-local schema the first time its stable address is
 * sent. Both Lua states reach the same C channel object, so the returned short id is
 * immediately meaningful to its receiver without copying the descriptor per value. */
static Schema *channel_schema(lua_State *state,
                              Channel *channel,
                              int keyIndex,
                              int addressIndex,
                              int fieldsIndex,
                              int typesIndex) {
    Schema pending;
    Schema *existing;
    const char *key;
    const char *address;
    size_t keyLength = 0;
    size_t addressLength = 0;
    size_t fieldCount;
    size_t index;
    if (channel == NULL || lua_type(state, keyIndex) != LUA_TSTRING
        || lua_type(state, addressIndex) != LUA_TSTRING
        || lua_type(state, fieldsIndex) != LUA_TTABLE
        || lua_type(state, typesIndex) != LUA_TTABLE) {
        return NULL;
    }
    key = lua_tolstring(state, keyIndex, &keyLength);
    address = lua_tolstring(state, addressIndex, &addressLength);
    fieldCount = lua_objlen(state, fieldsIndex);
    if (key == NULL || keyLength == 0 || address == NULL || addressLength == 0 || fieldCount == 0
        || fieldCount > MAX_SCHEMA_FIELDS || lua_objlen(state, typesIndex) != fieldCount) {
        return NULL;
    }
    MUTEX_LOCK(&channel->guard);
    existing = channel_schema_by_key(channel, key, keyLength);
    MUTEX_UNLOCK(&channel->guard);
    if (existing != NULL) {
        return existing;
    }

    memset(&pending, 0, sizeof pending);
    pending.key = copy_bytes(key, keyLength);
    pending.keyLength = keyLength;
    pending.address = copy_bytes(address, addressLength);
    pending.addressLength = addressLength;
    pending.fieldCount = fieldCount;
    if (pending.key == NULL || pending.address == NULL) {
        schema_discard(&pending);
        return NULL;
    }
    for (index = 0; index < fieldCount; index++) {
        const char *name;
        const char *kindName;
        size_t nameLength = 0;
        size_t kindLength = 0;
        int kind;
        lua_rawgeti(state, fieldsIndex, (int)index + 1);
        name = lua_tolstring(state, -1, &nameLength);
        lua_rawgeti(state, typesIndex, (int)index + 1);
        kindName = lua_tolstring(state, -1, &kindLength);
        kind = kindName != NULL ? schema_kind(kindName, kindLength) : -1;
        if (name == NULL || nameLength == 0 || kind < 0) {
            lua_pop(state, 2);
            schema_discard(&pending);
            return NULL;
        }
        pending.fields[index].name = copy_bytes(name, nameLength);
        pending.fields[index].nameLength = nameLength;
        pending.fields[index].kind = kind;
        lua_pop(state, 2);
        if (pending.fields[index].name == NULL) {
            schema_discard(&pending);
            return NULL;
        }
    }

    MUTEX_LOCK(&channel->guard);
    existing = channel_schema_by_key(channel, key, keyLength);
    if (existing == NULL && channel->schemaCount < MAX_CHANNEL_SCHEMAS) {
        pending.id = (uint16_t)(channel->schemaCount + 2);
        channel->schemas[channel->schemaCount] = pending;
        existing = &channel->schemas[channel->schemaCount++];
        memset(&pending, 0, sizeof pending);
    }
    MUTEX_UNLOCK(&channel->guard);
    schema_discard(&pending);
    return existing;
}

/* Refuses rather than grows. A channel that accepts everything offered turns a
 * producer that outruns its consumer into a process that runs out of memory. */
static bool channel_push_message(Channel *channel,
                                 int kind,
                                 lua_Integer id,
                                 lua_Number number,
                                 const uint8_t *header,
                                 size_t headerLength,
                                 const uint8_t *body,
                                 size_t bodyLength,
                                 const uint8_t *value,
                                 size_t valueLength,
                                 const RegionAttachment *attachments,
                                 size_t attachmentCount) {
    Message *message;
    size_t length;
    size_t attachmentOffset;
    size_t storage;
    if (channel == NULL || attachmentCount > MAX_MESSAGE_ATTACHMENTS) {
        return false;
    }
    if (headerLength > MAX_CHANNEL_BYTES || bodyLength > MAX_CHANNEL_BYTES - headerLength
        || valueLength > MAX_CHANNEL_BYTES - headerLength - bodyLength) {
        return false;
    }
    length = headerLength + bodyLength + valueLength;
    attachmentOffset = (length + sizeof(void *) - 1) & ~(sizeof(void *) - 1);
    storage = attachmentOffset + attachmentCount * sizeof(RegionAttachment);
    MUTEX_LOCK(&channel->guard);
    if (channel->closed || channel->count >= MAX_CHANNEL_MESSAGES
        || channel->bytes + length > MAX_CHANNEL_BYTES) {
        MUTEX_UNLOCK(&channel->guard);
        return false;
    }
    message = malloc(sizeof *message + storage);
    if (message == NULL) {
        MUTEX_UNLOCK(&channel->guard);
        return false;
    }
    message->next = NULL;
    message->kind = kind;
    message->id = id;
    message->number = number;
    message->attachmentCount = (uint16_t)attachmentCount;
    message->attachmentOffset = attachmentOffset;
    message->recordOffset = 0;
    message->headerLength = headerLength;
    message->bodyLength = bodyLength;
    message->valueLength = valueLength;
    if (headerLength != 0) {
        memcpy(message->bytes, header, headerLength);
    }
    if (bodyLength != 0) {
        memcpy(message->bytes + headerLength, body, bodyLength);
    }
    if (valueLength != 0) {
        memcpy(message->bytes + headerLength + bodyLength, value, valueLength);
    }
    if (attachmentCount != 0) {
        memcpy(message->bytes + attachmentOffset, attachments,
            attachmentCount * sizeof(RegionAttachment));
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

static bool channel_push(Channel *channel,
                         const uint8_t *header,
                         size_t headerLength,
                         const uint8_t *body,
                         size_t bodyLength) {
    return channel_push_message(channel, MESSAGE_BYTES, 0, 0,
        header, headerLength, body, bodyLength, NULL, 0, NULL, 0);
}

static bool channel_push_number(Channel *channel,
                                int kind,
                                lua_Integer id,
                                lua_Number number,
                                const uint8_t *module,
                                size_t moduleLength,
                                const uint8_t *member,
                                size_t memberLength) {
    if (channel == NULL || (kind != MESSAGE_NUMBER_TASK && kind != MESSAGE_NUMBER_REPLY)) {
        return false;
    }
    return channel_push_message(channel, kind, id, number,
        module, moduleLength, member, memberLength, NULL, 0, NULL, 0);
}

static bool channel_push_string(Channel *channel,
                                int kind,
                                lua_Integer id,
                                const uint8_t *module,
                                size_t moduleLength,
                                const uint8_t *member,
                                size_t memberLength,
                                const uint8_t *value,
                                size_t valueLength) {
    if (channel == NULL || value == NULL
        || (kind != MESSAGE_STRING_TASK && kind != MESSAGE_STRING_REPLY)) {
        return false;
    }
    return channel_push_message(channel, kind, id, 0,
        module, moduleLength, member, memberLength, value, valueLength, NULL, 0);
}

typedef struct {
    lua_Number numbers[MAX_SCHEMA_FIELDS];
    const char *strings[MAX_SCHEMA_FIELDS];
    size_t lengths[MAX_SCHEMA_FIELDS];
    uint8_t present[MAX_SCHEMA_FIELDS];
} RecordData;

static bool record_data(lua_State *state,
                        int valueIndex,
                        const Schema *schema,
                        RecordData *data,
                        size_t *stringBytes) {
    size_t index;
    size_t stored = 0;
    if (lua_type(state, valueIndex) != LUA_TTABLE) {
        return false;
    }
    /* An exact record stores its declared fields and nothing else. A value
     * mutated through `any` to carry extra keys returns to the dynamic copy,
     * which preserves them, rather than silently dropping them here. */
    lua_pushnil(state);
    while (lua_next(state, valueIndex) != 0) {
        stored++;
        lua_pop(state, 1);
    }
    memset(data, 0, sizeof *data);
    *stringBytes = 0;
    for (index = 0; index < schema->fieldCount; index++) {
        const SchemaField *field = &schema->fields[index];
        int base = SCHEMA_BASE(field->kind);
        lua_pushlstring(state, field->name, field->nameLength);
        lua_rawget(state, valueIndex);
        if (lua_type(state, -1) == LUA_TNIL && (field->kind & SCHEMA_OPTIONAL) != 0) {
            data->present[index] = 0;
        } else if (base == SCHEMA_NUMBER && lua_type(state, -1) == LUA_TNUMBER) {
            data->numbers[index] = lua_tonumber(state, -1);
            data->present[index] = 1;
        } else if (base == SCHEMA_BOOLEAN && lua_type(state, -1) == LUA_TBOOLEAN) {
            data->numbers[index] = lua_toboolean(state, -1) ? 1 : 0;
            data->present[index] = 1;
        } else if (base == SCHEMA_STRING && lua_type(state, -1) == LUA_TSTRING) {
            data->strings[index] = lua_tolstring(state, -1, &data->lengths[index]);
            if (data->lengths[index] > MAX_CHANNEL_BYTES - *stringBytes) {
                lua_pop(state, 1);
                return false;
            }
            *stringBytes += data->lengths[index];
            data->present[index] = 1;
        } else {
            lua_pop(state, 1);
            return false;
        }
        if (data->present[index] != 0) {
            stored--;
        }
        lua_pop(state, 1);
    }
    return stored == 0;
}

static bool channel_push_record(Channel *channel,
                                int kind,
                                lua_Integer id,
                                const uint8_t *module,
                                size_t moduleLength,
                                const uint8_t *member,
                                size_t memberLength,
                                const Schema *schema,
                                const RecordData *data,
                                size_t stringBytes) {
    Message *message;
    size_t length;
    size_t index;
    size_t offset;
    size_t recordOffset;
    size_t recordStorage;
    lua_Number *numbers;
    size_t *lengths;
    if (channel == NULL || schema == NULL
        || (kind != MESSAGE_RECORD_TASK && kind != MESSAGE_RECORD_REPLY)
        || moduleLength > MAX_CHANNEL_BYTES || memberLength > MAX_CHANNEL_BYTES - moduleLength
        || stringBytes > MAX_CHANNEL_BYTES - moduleLength - memberLength) {
        return false;
    }
    length = moduleLength + memberLength + stringBytes;
    recordOffset = (length + sizeof(lua_Number) - 1) & ~(sizeof(lua_Number) - 1);
    recordStorage = recordOffset
        + schema->fieldCount * sizeof(lua_Number)
        + schema->fieldCount * sizeof(size_t)
        + schema->fieldCount;
    MUTEX_LOCK(&channel->guard);
    if (channel->closed || channel->count >= MAX_CHANNEL_MESSAGES
        || channel->bytes + length > MAX_CHANNEL_BYTES) {
        MUTEX_UNLOCK(&channel->guard);
        return false;
    }
    message = malloc(sizeof *message + recordStorage);
    if (message == NULL) {
        MUTEX_UNLOCK(&channel->guard);
        return false;
    }
    message->next = NULL;
    message->kind = kind;
    message->id = id;
    message->number = 0;
    message->schemaId = schema->id;
    message->attachmentCount = 0;
    message->attachmentOffset = 0;
    message->recordOffset = recordOffset;
    message->headerLength = moduleLength;
    message->bodyLength = memberLength;
    message->valueLength = stringBytes;
    if (moduleLength != 0) {
        memcpy(message->bytes, module, moduleLength);
    }
    if (memberLength != 0) {
        memcpy(message->bytes + moduleLength, member, memberLength);
    }
    offset = moduleLength + memberLength;
    numbers = (lua_Number *)(void *)(message->bytes + recordOffset);
    lengths = (size_t *)(void *)(numbers + schema->fieldCount);
    {
        uint8_t *present = (uint8_t *)(void *)(lengths + schema->fieldCount);
        for (index = 0; index < schema->fieldCount; index++) {
            numbers[index] = data->numbers[index];
            lengths[index] = data->lengths[index];
            present[index] = data->present[index];
            if (data->present[index] != 0
                && SCHEMA_BASE(schema->fields[index].kind) == SCHEMA_STRING
                && data->lengths[index] != 0) {
                memcpy(message->bytes + offset, data->strings[index], data->lengths[index]);
                offset += data->lengths[index];
            }
        }
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
 * rather than waiting for a sender that will not come.
 *
 * Queue state is observed only under the mutex, and every push signals. An
 * earlier fast path polled `head` without synchronization and skipped the signal
 * when its waiter counter said nobody slept. That is a C data race, and under a
 * parallel test-runner join it occasionally left the consumer parked after every
 * producer had returned to its inbox. */
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
            BOOL waited;
            if (spent >= (DWORD)timeoutMs) {
                break;
            }
            waited = SleepConditionVariableCS(
                &channel->arrived, &channel->guard, (DWORD)timeoutMs - spent);
            if (!waited) {
                break;
            }
        }
#else
        struct timespec deadline;
        deadline_after(&deadline, timeoutMs);
        while (channel->head == NULL && !channel->closed) {
            int waited;
            waited = pthread_cond_timedwait(&channel->arrived, &channel->guard, &deadline);
            if (waited != 0) {
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
        channel->bytes -= message->headerLength + message->bodyLength + message->valueLength;
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
    Channel *inbox;
    Channel *outbox;
    char *failure;
    int status;
    Thread thread;
    Mutex taskGuard;
    WorkerTask *tasks;
    lua_Integer currentTask;
} Worker;

static WorkerTask *worker_task_find(Worker *worker, lua_Integer id) {
    WorkerTask *task;
    for (task = worker != NULL ? worker->tasks : NULL; task != NULL; task = task->next) {
        if (task->id == id) {
            return task;
        }
    }
    return NULL;
}

static void worker_tasks_free(Worker *worker) {
    WorkerTask *task = worker->tasks;
    while (task != NULL) {
        WorkerTask *next = task->next;
        free(task);
        task = next;
    }
    worker->tasks = NULL;
}

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
        lua_pushlightuserdata(state, worker);
        lua_setfield(state, LUA_GLOBALSINDEX, "__nuppWorkerHandle");
        lua_pushstring(state, "nupp.workers");
        lua_setfield(state, LUA_GLOBALSINDEX, "__nuppWorkerEntry");
        free(nupp_host_set_arguments(runtime, 0, NULL));
        problem = nupp_host_run(runtime, workerPayload, workerPayloadLength, "=nupp-worker");
        nupp_host_runtime_free(runtime);
    }
    /* Both ends close whatever happened, so a reader on the other side of a
     * worker that died is told rather than left waiting. */
    channel_close(worker->inbox);
    channel_close(worker->outbox);
    worker->failure = problem;
    worker->status = problem != NULL ? 1 : 0;
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
    size_t headerLength = 0;
    size_t bodyLength = 0;
    const char *header = lua_tolstring(state, 2, &headerLength);
    const char *body = lua_tolstring(state, 3, &bodyLength);
    bool accepted = header != NULL && body != NULL
        && channel_push(lua_touserdata(state, 1),
            (const uint8_t *)header, headerLength,
            (const uint8_t *)body, bodyLength);
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

static int channel_push_number_task_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    lua_Integer id = lua_tointeger(state, 2);
    size_t moduleLength = 0;
    size_t memberLength = 0;
    const char *module = lua_tolstring(state, 3, &moduleLength);
    const char *member = lua_tolstring(state, 4, &memberLength);
    bool accepted = channel != NULL && lua_isnumber(state, 2)
        && module != NULL && member != NULL && lua_isnumber(state, 5)
        && channel_push_number(channel, MESSAGE_NUMBER_TASK, id,
            lua_tonumber(state, 5),
            (const uint8_t *)module, moduleLength,
            (const uint8_t *)member, memberLength);
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

static int channel_push_number_reply_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    bool accepted = channel != NULL && lua_isnumber(state, 2) && lua_isnumber(state, 3)
        && channel_push_number(channel, MESSAGE_NUMBER_REPLY,
            lua_tointeger(state, 2), lua_tonumber(state, 3),
            NULL, 0, NULL, 0);
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

static int channel_push_string_task_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t moduleLength = 0;
    size_t memberLength = 0;
    size_t valueLength = 0;
    const char *module = lua_tolstring(state, 3, &moduleLength);
    const char *member = lua_tolstring(state, 4, &memberLength);
    const char *value = lua_tolstring(state, 5, &valueLength);
    bool accepted = channel != NULL && lua_isnumber(state, 2)
        && module != NULL && member != NULL && value != NULL
        && channel_push_string(channel, MESSAGE_STRING_TASK,
            lua_tointeger(state, 2),
            (const uint8_t *)module, moduleLength,
            (const uint8_t *)member, memberLength,
            (const uint8_t *)value, valueLength);
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

static int channel_push_string_reply_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t valueLength = 0;
    const char *value = lua_tolstring(state, 3, &valueLength);
    bool accepted = channel != NULL && lua_isnumber(state, 2) && value != NULL
        && channel_push_string(channel, MESSAGE_STRING_REPLY,
            lua_tointeger(state, 2),
            NULL, 0, NULL, 0,
            (const uint8_t *)value, valueLength);
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

/* --- spike: buffer-only transport ---------------------------------------- */

static int channel_dict_register_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t addressLength = 0;
    const char *address = lua_tolstring(state, 2, &addressLength);
    size_t index;
    lua_Integer found = 0;
    if (channel == NULL || address == NULL || addressLength == 0) {
        lua_pushnil(state);
        return 1;
    }
    MUTEX_LOCK(&channel->guard);
    for (index = 0; index < channel->dictCount; index++) {
        if (channel->dictLengths[index] == addressLength
            && memcmp(channel->dict[index], address, addressLength) == 0) {
            found = (lua_Integer)index + 1;
            break;
        }
    }
    if (found == 0 && channel->dictCount < MAX_CHANNEL_DICT) {
        char *copy = copy_bytes(address, addressLength);
        if (copy != NULL) {
            channel->dict[channel->dictCount] = copy;
            channel->dictLengths[channel->dictCount] = addressLength;
            channel->dictCount++;
            found = (lua_Integer)channel->dictCount;
        }
    }
    MUTEX_UNLOCK(&channel->guard);
    if (found == 0) {
        lua_pushnil(state);
    } else {
        lua_pushinteger(state, found);
    }
    return 1;
}

static int channel_dict_count_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t count = 0;
    if (channel != NULL) {
        MUTEX_LOCK(&channel->guard);
        count = channel->dictCount;
        MUTEX_UNLOCK(&channel->guard);
    }
    lua_pushinteger(state, (lua_Integer)count);
    return 1;
}

static int channel_dict_address_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    lua_Integer index = lua_tointeger(state, 2);
    if (channel == NULL || index < 1 || (size_t)index > channel->dictCount) {
        lua_pushnil(state);
    } else {
        lua_pushlstring(state, channel->dict[index - 1], channel->dictLengths[index - 1]);
    }
    return 1;
}

/* Reads a flat {handle, first, length, ...} array into attachment records. A
 * region handle entry retains its block; an entry whose first slot is the
 * moved allocation's pointer as native-width bytes takes ownership of that
 * allocation, with count and layout tag in the remaining slots. Answers the
 * count, or (size_t)-1 for a malformed array with the parsed entries undone:
 * regions released, moved allocations freed, since the caller has already
 * handed them over. */
static size_t buffer_attachments_read(lua_State *state,
                                      int index,
                                      RegionAttachment *out) {
    size_t triples;
    size_t position;
    if (lua_isnoneornil(state, index)) {
        return 0;
    }
    if (lua_type(state, index) != LUA_TTABLE) {
        return (size_t)-1;
    }
    triples = lua_objlen(state, index) / 3;
    if (triples > MAX_MESSAGE_ATTACHMENTS) {
        return (size_t)-1;
    }
    for (position = 0; position < triples; position++) {
        void *block;
        int kind = ATTACHMENT_REGION;
        lua_Integer first;
        lua_Integer length;
        int valid;
        lua_rawgeti(state, index, (int)(position * 3 + 1));
        if (lua_type(state, -1) == LUA_TSTRING) {
            size_t pointerLength = 0;
            const char *pointerBytes = lua_tolstring(state, -1, &pointerLength);
            block = NULL;
            if (pointerLength == sizeof(void *)) {
                kind = ATTACHMENT_MOVED;
                memcpy(&block, pointerBytes, sizeof(void *));
            }
        } else {
            block = nupp_host_region_block(state, -1);
        }
        lua_rawgeti(state, index, (int)(position * 3 + 2));
        first = lua_tointeger(state, -1);
        lua_rawgeti(state, index, (int)(position * 3 + 3));
        length = lua_tointeger(state, -1);
        lua_pop(state, 3);
        valid = block != NULL
            && (kind == ATTACHMENT_MOVED ? first >= 0 && length >= 1
                                         : first >= 1 && length >= 0);
        if (!valid) {
            size_t undo;
            /* A moved allocation was handed over even when its entry is
             * malformed, so an invalid range still frees it. */
            if (kind == ATTACHMENT_MOVED && block != NULL) {
                free(block);
            }
            for (undo = 0; undo < position; undo++) {
                if (out[undo].kind == ATTACHMENT_MOVED) {
                    free(out[undo].block);
                } else {
                    nupp_host_region_release(out[undo].block);
                }
            }
            return (size_t)-1;
        }
        out[position].kind = kind;
        out[position].block = block;
        out[position].first = (size_t)first;
        out[position].length = (size_t)length;
        if (kind == ATTACHMENT_REGION) {
            nupp_host_region_retain(block);
        }
    }
    return triples;
}

/* Undoes a read whose message never formed: the failed push owns the moved
 * allocations from the call on, so they are freed here rather than by the
 * caller. */
static void buffer_attachments_release(RegionAttachment *attachments, size_t count) {
    size_t index;
    for (index = 0; index < count; index++) {
        if (attachments[index].kind == ATTACHMENT_MOVED) {
            free(attachments[index].block);
        } else {
            nupp_host_region_release(attachments[index].block);
        }
    }
}

static int channel_push_buffer_task_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t moduleLength = 0;
    size_t memberLength = 0;
    size_t bytesLength = 0;
    const char *module = lua_tolstring(state, 3, &moduleLength);
    const char *member = lua_tolstring(state, 4, &memberLength);
    const char *bytes = lua_tolstring(state, 6, &bytesLength);
    RegionAttachment attachments[MAX_MESSAGE_ATTACHMENTS];
    size_t attachmentCount = buffer_attachments_read(state, 7, attachments);
    bool accepted = false;
    if (channel != NULL && lua_isnumber(state, 2) && lua_isnumber(state, 5)
        && module != NULL && member != NULL && bytes != NULL
        && attachmentCount != (size_t)-1) {
        accepted = channel_push_message(channel, MESSAGE_BUFFER_TASK,
            lua_tointeger(state, 2), lua_tonumber(state, 5),
            (const uint8_t *)module, moduleLength,
            (const uint8_t *)member, memberLength,
            (const uint8_t *)bytes, bytesLength, attachments, attachmentCount);
        if (!accepted) {
            buffer_attachments_release(attachments, attachmentCount);
        }
    }
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

static int channel_push_buffer_reply_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t bytesLength = 0;
    const char *bytes = lua_tolstring(state, 4, &bytesLength);
    RegionAttachment attachments[MAX_MESSAGE_ATTACHMENTS];
    size_t attachmentCount = buffer_attachments_read(state, 5, attachments);
    bool accepted = false;
    if (channel != NULL && lua_isnumber(state, 2) && lua_isnumber(state, 3)
        && bytes != NULL && attachmentCount != (size_t)-1) {
        accepted = channel_push_message(channel, MESSAGE_BUFFER_REPLY,
            lua_tointeger(state, 2), lua_tonumber(state, 3),
            NULL, 0, NULL, 0,
            (const uint8_t *)bytes, bytesLength, attachments, attachmentCount);
        if (!accepted) {
            buffer_attachments_release(attachments, attachmentCount);
        }
    }
    lua_pushboolean(state, accepted ? 1 : 0);
    return 1;
}

/* Registers one schema on a channel and answers its short id, or nil when the
 * descriptor is unusable. The caller caches the id per channel, so the
 * fingerprint, address, and field tables cross into C once rather than on
 * every push. */
static int channel_schema_register_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    Schema *schema = channel_schema(state, channel, 2, 3, 4, 5);
    if (schema == NULL) {
        lua_pushnil(state);
    } else {
        lua_pushinteger(state, (lua_Integer)schema->id);
    }
    return 1;
}

static const Schema *channel_schema_argument(lua_State *state,
                                             Channel *channel,
                                             int idIndex) {
    lua_Integer id;
    if (channel == NULL || !lua_isnumber(state, idIndex)) {
        return NULL;
    }
    id = lua_tointeger(state, idIndex);
    if (id < 2 || id > 65535) {
        return NULL;
    }
    return channel_schema_by_id(channel, (uint16_t)id);
}

static int channel_push_record_task_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    size_t moduleLength = 0;
    size_t memberLength = 0;
    const char *module = lua_tolstring(state, 3, &moduleLength);
    const char *member = lua_tolstring(state, 4, &memberLength);
    const Schema *schema = channel_schema_argument(state, channel, 5);
    RecordData data;
    size_t stringBytes = 0;
    int status = 0;
    if (schema != NULL && module != NULL && member != NULL && lua_isnumber(state, 2)
        && record_data(state, 6, schema, &data, &stringBytes)) {
        status = channel_push_record(channel, MESSAGE_RECORD_TASK,
            lua_tointeger(state, 2),
            (const uint8_t *)module, moduleLength,
            (const uint8_t *)member, memberLength,
            schema, &data, stringBytes) ? 1 : -1;
    }
    lua_pushinteger(state, status);
    return 1;
}

static int channel_push_record_reply_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    const Schema *schema = channel_schema_argument(state, channel, 3);
    RecordData data;
    size_t stringBytes = 0;
    int status = 0;
    if (schema != NULL && lua_isnumber(state, 2)
        && record_data(state, 4, schema, &data, &stringBytes)) {
        status = channel_push_record(channel, MESSAGE_RECORD_REPLY,
            lua_tointeger(state, 2), NULL, 0, NULL, 0,
            schema, &data, stringBytes) ? 1 : -1;
    }
    lua_pushinteger(state, status);
    return 1;
}

static void channel_push_record_value(lua_State *state,
                                      const Channel *channel,
                                      const Message *message) {
    const Schema *schema = channel_schema_by_id((Channel *)channel, message->schemaId);
    size_t offset = message->headerLength + message->bodyLength;
    size_t index;
    const lua_Number *numbers;
    const size_t *lengths;
    if (schema == NULL) {
        lua_pushnil(state);
        return;
    }
    numbers = (const lua_Number *)(const void *)(message->bytes + message->recordOffset);
    lengths = (const size_t *)(const void *)(numbers + schema->fieldCount);
    {
        const uint8_t *present = (const uint8_t *)(const void *)(lengths + schema->fieldCount);
        lua_createtable(state, 0, (int)schema->fieldCount + 1);
        lua_pushlstring(state, schema->address, schema->addressLength);
        lua_rawseti(state, -2, 0);
        for (index = 0; index < schema->fieldCount; index++) {
            const SchemaField *field = &schema->fields[index];
            if (present[index] == 0) {
                continue;
            }
            lua_pushlstring(state, field->name, field->nameLength);
            if (SCHEMA_BASE(field->kind) == SCHEMA_NUMBER) {
                lua_pushnumber(state, numbers[index]);
            } else if (SCHEMA_BASE(field->kind) == SCHEMA_BOOLEAN) {
                lua_pushboolean(state, numbers[index] != 0 ? 1 : 0);
            } else {
                lua_pushlstring(state, (const char *)message->bytes + offset,
                    lengths[index]);
                offset += lengths[index];
            }
            lua_rawset(state, -3);
        }
    }
}

/* Pushes the message's attachments as one flat {handle, first, length, ...}
 * array, or nil when there are none. Each attachment's reference transfers
 * into the pushed handle, so the freed message releases nothing. */
static void channel_pop_attachments(lua_State *state, Message *message) {
    RegionAttachment *attachments;
    size_t index;
    if (message->attachmentCount == 0) {
        lua_pushnil(state);
        return;
    }
    attachments = (RegionAttachment *)(void *)(message->bytes + message->attachmentOffset);
    lua_createtable(state, (int)message->attachmentCount * 3, 0);
    for (index = 0; index < message->attachmentCount; index++) {
        if (attachments[index].kind == ATTACHMENT_MOVED) {
            lua_pushlightuserdata(state, attachments[index].block);
        } else {
            nupp_host_region_push_handle(state, attachments[index].block);
        }
        lua_rawseti(state, -2, (int)(index * 3 + 1));
        lua_pushinteger(state, (lua_Integer)attachments[index].first);
        lua_rawseti(state, -2, (int)(index * 3 + 2));
        lua_pushinteger(state, (lua_Integer)attachments[index].length);
        lua_rawseti(state, -2, (int)(index * 3 + 3));
    }
    message->attachmentCount = 0;
}

static int channel_pop_entry(lua_State *state) {
    Channel *channel = lua_touserdata(state, 1);
    lua_Integer timeout = lua_tointeger(state, 2);
    Message *message = channel_pop(
        channel,
        timeout < -2147483647 ? -2147483647 : timeout > 2147483647 ? 2147483647 : (int)timeout);
    if (message == NULL) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
    } else if (message->kind == MESSAGE_NUMBER_TASK) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_NUMBER_TASK);
        lua_pushinteger(state, message->id);
        lua_pushlstring(state, (const char *)message->bytes, message->headerLength);
        lua_pushlstring(state,
            (const char *)message->bytes + message->headerLength,
            message->bodyLength);
        lua_pushnumber(state, message->number);
        free(message);
    } else if (message->kind == MESSAGE_NUMBER_REPLY) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_NUMBER_REPLY);
        lua_pushinteger(state, message->id);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnumber(state, message->number);
        free(message);
    } else if (message->kind == MESSAGE_STRING_TASK) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_STRING_TASK);
        lua_pushinteger(state, message->id);
        lua_pushlstring(state, (const char *)message->bytes, message->headerLength);
        lua_pushlstring(state,
            (const char *)message->bytes + message->headerLength,
            message->bodyLength);
        lua_pushlstring(state,
            (const char *)message->bytes + message->headerLength + message->bodyLength,
            message->valueLength);
        free(message);
    } else if (message->kind == MESSAGE_STRING_REPLY) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_STRING_REPLY);
        lua_pushinteger(state, message->id);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushlstring(state, (const char *)message->bytes, message->valueLength);
        free(message);
    } else if (message->kind == MESSAGE_RECORD_TASK) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_RECORD_TASK);
        lua_pushinteger(state, message->id);
        lua_pushlstring(state, (const char *)message->bytes, message->headerLength);
        lua_pushlstring(state,
            (const char *)message->bytes + message->headerLength,
            message->bodyLength);
        channel_push_record_value(state, channel, message);
        free(message);
    } else if (message->kind == MESSAGE_RECORD_REPLY) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_RECORD_REPLY);
        lua_pushinteger(state, message->id);
        lua_pushnil(state);
        lua_pushnil(state);
        channel_push_record_value(state, channel, message);
        free(message);
    } else if (message->kind == MESSAGE_BUFFER_TASK) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_BUFFER_TASK);
        lua_pushinteger(state, message->id);
        lua_pushlstring(state, (const char *)message->bytes, message->headerLength);
        lua_pushlstring(state,
            (const char *)message->bytes + message->headerLength,
            message->bodyLength);
        lua_pushlstring(state,
            (const char *)message->bytes + message->headerLength + message->bodyLength,
            message->valueLength);
        lua_pushnumber(state, message->number);
        channel_pop_attachments(state, message);
        free(message);
        return 9;
    } else if (message->kind == MESSAGE_BUFFER_REPLY) {
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushinteger(state, MESSAGE_BUFFER_REPLY);
        lua_pushinteger(state, message->id);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushlstring(state, (const char *)message->bytes, message->valueLength);
        lua_pushnumber(state, message->number);
        channel_pop_attachments(state, message);
        free(message);
        return 9;
    } else {
        lua_pushlstring(state, (const char *)message->bytes, message->headerLength);
        lua_pushlstring(state,
            (const char *)message->bytes + message->headerLength,
            message->bodyLength);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
        lua_pushnil(state);
        free(message);
    }
    return 7;
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
    Channel *inbox = lua_touserdata(state, 1);
    Channel *outbox = lua_touserdata(state, 2);
    Worker *worker;

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
    worker->inbox = inbox;
    worker->outbox = outbox;
    MUTEX_INIT(&worker->taskGuard);
#if defined(_WIN32)
    worker->thread = CreateThread(NULL, 0, worker_trampoline, worker, 0, NULL);
    if (worker->thread == NULL) {
#else
    if (pthread_create(&worker->thread, NULL, worker_trampoline, worker) != 0) {
#endif
        MUTEX_FREE(&worker->taskGuard);
        free(worker);
        lua_pushnil(state);
        lua_pushstring(state, "cannot start worker");
        return 2;
    }
    lua_pushlightuserdata(state, worker);
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
    failure = worker->failure;
    status = worker->status;
    worker->failure = NULL;
    lua_pushinteger(state, status);
    if (failure != NULL) {
        lua_pushstring(state, failure);
        free(failure);
    } else {
        lua_pushnil(state);
    }
    MUTEX_LOCK(&worker->taskGuard);
    worker_tasks_free(worker);
    MUTEX_UNLOCK(&worker->taskGuard);
    MUTEX_FREE(&worker->taskGuard);
    free(worker);
    return 2;
}

static Worker *current_worker(lua_State *state) {
    Worker *worker;
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppWorkerHandle");
    worker = lua_touserdata(state, -1);
    lua_pop(state, 1);
    return worker;
}

static int worker_task_create(lua_State *state) {
    Worker *worker = lua_touserdata(state, 1);
    lua_Integer id = lua_tointeger(state, 2);
    WorkerTask *task;
    bool created = false;
    if (worker == NULL || id < 1) {
        lua_pushboolean(state, 0);
        return 1;
    }
    task = calloc(1, sizeof *task);
    if (task == NULL) {
        lua_pushboolean(state, 0);
        return 1;
    }
    task->id = id;
    task->status = TASK_QUEUED;
    if (!lua_isnoneornil(state, 3)) {
        task->deadline = lua_tonumber(state, 3);
        task->hasDeadline = isfinite(task->deadline);
    }
    MUTEX_LOCK(&worker->taskGuard);
    if (worker_task_find(worker, id) == NULL) {
        task->next = worker->tasks;
        worker->tasks = task;
        created = true;
    }
    MUTEX_UNLOCK(&worker->taskGuard);
    if (!created) {
        free(task);
    }
    lua_pushboolean(state, created ? 1 : 0);
    return 1;
}

/* 1 means a queued task was excluded, 2 means a running task received the
 * request, and zero means somebody had already requested or settled it. */
static int worker_task_cancel(lua_State *state) {
    Worker *worker = lua_touserdata(state, 1);
    lua_Integer id = lua_tointeger(state, 2);
    WorkerTask *task;
    int result = 0;
    if (worker != NULL) {
        MUTEX_LOCK(&worker->taskGuard);
        task = worker_task_find(worker, id);
        if (task != NULL && task->status == TASK_QUEUED) {
            task->status = TASK_CANCELLED;
            result = 1;
        } else if (task != NULL && task->status == TASK_RUNNING) {
            task->status = TASK_CANCEL_REQUESTED;
            result = 2;
        }
        MUTEX_UNLOCK(&worker->taskGuard);
    }
    lua_pushinteger(state, result);
    return 1;
}

/* Called in the lane immediately after it reads the physical work frame. The
 * compare-and-change here is the queued/running race boundary. */
static int worker_task_start(lua_State *state) {
    Worker *worker = current_worker(state);
    lua_Integer id = lua_tointeger(state, 1);
    WorkerTask *task;
    bool run = false;
    bool deadline = false;
    if (worker != NULL) {
        MUTEX_LOCK(&worker->taskGuard);
        task = worker_task_find(worker, id);
        if (task != NULL && task->status == TASK_QUEUED) {
            deadline = task->hasDeadline && monotonic_ms() >= task->deadline;
            if (deadline) {
                task->status = TASK_CANCELLED;
            } else {
                task->status = TASK_RUNNING;
                worker->currentTask = id;
                run = true;
            }
        }
        MUTEX_UNLOCK(&worker->taskGuard);
    }
    lua_pushboolean(state, run ? 1 : 0);
    lua_pushboolean(state, deadline ? 1 : 0);
    return 2;
}

static int worker_task_checkpoint(lua_State *state) {
    Worker *worker = current_worker(state);
    WorkerTask *task;
    bool cancelled = false;
    bool deadline = false;
    if (worker != NULL) {
        MUTEX_LOCK(&worker->taskGuard);
        task = worker_task_find(worker, worker->currentTask);
        if (task != NULL) {
            deadline = task->hasDeadline && monotonic_ms() >= task->deadline;
            cancelled = deadline || task->status == TASK_CANCEL_REQUESTED
                || task->status == TASK_CANCELLED;
            if (cancelled && task->status == TASK_RUNNING) {
                task->status = TASK_CANCEL_REQUESTED;
            }
        }
        MUTEX_UNLOCK(&worker->taskGuard);
    }
    lua_pushboolean(state, cancelled ? 1 : 0);
    lua_pushboolean(state, deadline ? 1 : 0);
    return 2;
}

static int worker_task_finish(lua_State *state) {
    Worker *worker = current_worker(state);
    lua_Integer id = lua_tointeger(state, 1);
    WorkerTask *task;
    bool cancelled = false;
    bool deadline = false;
    if (worker != NULL) {
        MUTEX_LOCK(&worker->taskGuard);
        task = worker_task_find(worker, id);
        if (task != NULL) {
            deadline = task->hasDeadline && monotonic_ms() >= task->deadline;
            cancelled = deadline || task->status == TASK_CANCEL_REQUESTED
                || task->status == TASK_CANCELLED;
            task->status = TASK_DONE;
        }
        if (worker->currentTask == id) {
            worker->currentTask = 0;
        }
        MUTEX_UNLOCK(&worker->taskGuard);
    }
    lua_pushboolean(state, cancelled ? 1 : 0);
    lua_pushboolean(state, deadline ? 1 : 0);
    return 2;
}

static int worker_task_release(lua_State *state) {
    Worker *worker = lua_touserdata(state, 1);
    lua_Integer id = lua_tointeger(state, 2);
    WorkerTask **at;
    if (worker != NULL) {
        MUTEX_LOCK(&worker->taskGuard);
        at = &worker->tasks;
        while (*at != NULL) {
            if ((*at)->id == id) {
                WorkerTask *removed = *at;
                *at = removed->next;
                free(removed);
                break;
            }
            at = &(*at)->next;
        }
        MUTEX_UNLOCK(&worker->taskGuard);
    }
    return 0;
}

static int worker_task_status(lua_State *state) {
    Worker *worker = lua_touserdata(state, 1);
    lua_Integer id = lua_tointeger(state, 2);
    WorkerTask *task;
    int status = 0;
    if (worker != NULL) {
        MUTEX_LOCK(&worker->taskGuard);
        task = worker_task_find(worker, id);
        status = task != NULL ? (int)task->status : 0;
        MUTEX_UNLOCK(&worker->taskGuard);
    }
    lua_pushinteger(state, status);
    return 1;
}

/* The channels this worker was started with, which is how code inside one finds
 * the ends it is supposed to speak through. */
static int current(lua_State *state) {
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppWorkerIn");
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppWorkerOut");
    return 2;
}

static int worker_parallelism(lua_State *state) {
    long count = 1;
#if defined(_WIN32)
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    count = (long)info.dwNumberOfProcessors;
#elif defined(_SC_NPROCESSORS_ONLN)
    count = sysconf(_SC_NPROCESSORS_ONLN);
#endif
    if (count < 1) {
        count = 1;
    }
    lua_pushinteger(state, (lua_Integer)count);
    return 1;
}

static void field(lua_State *state, const char *name, lua_CFunction function) {
    lua_pushcclosure(state, function, 0);
    lua_setfield(state, -2, name);
}

int nupp_host_workers_open(lua_State *state) {
    lua_createtable(state, 0, 32);
    field(state, "channelSchemaRegister", channel_schema_register_entry);
    field(state, "channelDictRegister", channel_dict_register_entry);
    field(state, "channelDictCount", channel_dict_count_entry);
    field(state, "channelDictAddress", channel_dict_address_entry);
    field(state, "channelPushBufferTask", channel_push_buffer_task_entry);
    field(state, "channelPushBufferReply", channel_push_buffer_reply_entry);
    field(state, "channelCreate", channel_create);
    field(state, "channelDestroy", channel_destroy);
    field(state, "channelClose", channel_close_entry);
    field(state, "channelPush", channel_push_entry);
    field(state, "channelPushNumberTask", channel_push_number_task_entry);
    field(state, "channelPushNumberReply", channel_push_number_reply_entry);
    field(state, "channelPushStringTask", channel_push_string_task_entry);
    field(state, "channelPushStringReply", channel_push_string_reply_entry);
    field(state, "channelPushRecordTask", channel_push_record_task_entry);
    field(state, "channelPushRecordReply", channel_push_record_reply_entry);
    field(state, "channelPop", channel_pop_entry);
    field(state, "channelCount", channel_count_entry);
    field(state, "channelClosed", channel_closed_entry);
    field(state, "workerSpawn", worker_spawn);
    field(state, "workerJoin", worker_join);
    field(state, "workerTaskCreate", worker_task_create);
    field(state, "workerTaskCancel", worker_task_cancel);
    field(state, "workerTaskStart", worker_task_start);
    field(state, "workerTaskCheckpoint", worker_task_checkpoint);
    field(state, "workerTaskFinish", worker_task_finish);
    field(state, "workerTaskRelease", worker_task_release);
    field(state, "workerTaskStatus", worker_task_status);
    field(state, "current", current);
    field(state, "workerParallelism", worker_parallelism);
    return 1;
}

#endif /* NUPP_FEATURE_WORKERS */
