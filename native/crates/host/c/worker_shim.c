/* Lua stack adapter for Rust-owned workers and shared bytes.
 *
 * Stack and longjmp: every lua_* operation is executed by a Lua C callback,
 * never by Rust. The callback's caller has a Lua protected frame (host chunks
 * use lua_shim.c and worker chunks use the same host runner), so allocation or
 * metamethod failure may longjmp through this C frame but never through Rust.
 * Rust is called only after input conversion and returns before another Lua
 * operation. The functions below never retain lua_State or a Lua stack pointer.
 *
 * Rust callback ABI: every nupp_rust_* export catches Rust panics and returns a
 * conservative C value. Rust panic unwinding therefore cannot enter this file;
 * conversely, no Lua operation occurs while a Rust frame is active. Extern
 * signatures below must exactly match the repr(C) Rust declarations.
 *
 * Ownership and lifetime:
 * - channel/worker/account/builder pointers transfer one Rust Arc/Box owner to
 *   Lua lightuserdata or userdata and are destroyed/joined/finalized once;
 * - message pointers transfer from channel_pop until message_destroy; returned
 *   byte pointers are borrowed only until that destroy and copied immediately;
 * - region pointers carry one Arc owner per Lua handle; data pointers remain
 *   immutable and valid while the handle is live;
 * - a builder reservation pointer is exclusive until one commit, during which
 *   every operation that could reallocate is rejected;
 * - Lua string and attachment-array pointers are borrowed for one synchronous
 *   Rust call, which copies or takes ownership before returning.
 *
 * Thread affinity: each callback runs on its lua_State's owner thread. Channels,
 * region Arcs, and task mutexes are the only cross-thread values. Host and task
 * lightuserdata remain backed by Rust owners for the full lifetime of the Lua
 * state that can read them. Parent and worker states are never entered across
 * lanes.
 */

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>

#define ATTACHMENT_REGION 0
#define ATTACHMENT_MOVED 1
#define MAX_ATTACHMENTS 255u

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

typedef struct RawAttachment {
    int kind;
    void *block;
    size_t first;
    size_t length;
} RawAttachment;

/* These functions are Rust panic firewalls as well as ownership adapters. Do
 * not add a direct Rust export here unless its body uses ffi_value/ffi_void. */
extern void *nupp_rust_worker_channel_new(void);
extern void nupp_rust_worker_channel_destroy(const void *channel);
extern void nupp_rust_worker_channel_close(const void *channel);
extern size_t nupp_rust_worker_channel_count(const void *channel);
extern int nupp_rust_worker_channel_closed(const void *channel);
extern int nupp_rust_worker_channel_push(const void *channel, int kind,
    int64_t id, double number, const uint8_t *first, size_t first_length,
    const uint8_t *second, size_t second_length, const uint8_t *value,
    size_t value_length, const RawAttachment *attachments,
    size_t attachment_count);
extern void *nupp_rust_worker_channel_pop(const void *channel, int timeout_ms);
extern void nupp_rust_worker_message_destroy(void *message);
extern int nupp_rust_worker_message_kind(const void *message);
extern int64_t nupp_rust_worker_message_id(const void *message);
extern double nupp_rust_worker_message_number(const void *message);
extern const uint8_t *nupp_rust_worker_message_bytes(const void *message,
    int which, size_t *length);
extern size_t nupp_rust_worker_message_attachment_count(const void *message);
extern int nupp_rust_worker_message_take_attachment(void *message,
    size_t index, RawAttachment *out);
extern size_t nupp_rust_worker_channel_dict_register(const void *channel,
    const uint8_t *address, size_t length);
extern size_t nupp_rust_worker_channel_dict_count(const void *channel);
extern const uint8_t *nupp_rust_worker_channel_dict_address(
    const void *channel, size_t index, size_t *length);

extern void *nupp_rust_region_new(const uint8_t *data, size_t length);
extern void *nupp_rust_region_read_file(const uint8_t *path, size_t length,
    char *error, size_t error_capacity);
extern void nupp_rust_region_retain(const void *region);
extern void nupp_rust_region_release(const void *region);
extern const uint8_t *nupp_rust_region_data(const void *region);
extern size_t nupp_rust_region_length(const void *region);
extern void *nupp_rust_region_account_new(void);
extern void nupp_rust_region_account_destroy(void *account);
extern size_t nupp_rust_region_account_charge(void *account,
    const void *region);
extern void nupp_rust_region_account_discharge(void *account,
    const void *region);
extern size_t nupp_rust_region_accounted(const void *account);
extern void *nupp_rust_region_builder_new(void);
extern void nupp_rust_region_builder_destroy(void *builder);
extern int nupp_rust_region_builder_append(void *builder,
    const uint8_t *data, size_t length);
extern uint8_t *nupp_rust_region_builder_reserve(void *builder, size_t count);
extern int nupp_rust_region_builder_commit(void *builder, size_t written);
extern int nupp_rust_region_builder_open(const void *builder);
extern void *nupp_rust_region_builder_freeze(void *builder);

extern void *nupp_rust_worker_spawn(const void *host, const void *inbox,
    const void *outbox, char *error, size_t error_capacity);
extern int nupp_rust_worker_join(void *worker, char *error,
    size_t error_capacity);
extern int nupp_rust_worker_task_create(const void *worker, int64_t id,
    int has_deadline, double deadline_ms);
extern int nupp_rust_worker_task_cancel(const void *worker, int64_t id);
extern int nupp_rust_worker_task_start(const void *tasks, int64_t id,
    int *deadline);
extern int nupp_rust_worker_task_checkpoint(const void *tasks, int *deadline);
extern int nupp_rust_worker_task_finish(const void *tasks, int64_t id,
    int *deadline);
extern void nupp_rust_worker_task_release(const void *worker, int64_t id);
extern int nupp_rust_worker_task_status(const void *worker, int64_t id);
extern size_t nupp_rust_worker_parallelism(void);

/* --- shared region handles and per-state accounting --------------------- */

#define REGION_METATABLE "nupp.mem.sharedbytes.region.rust"
#define BUILDER_METATABLE "nupp.mem.sharedbytes.builder.rust"
#define ACCOUNT_REGISTRY "nupp.mem.sharedbytes.account.rust"
typedef struct RegionHandle { void *block; } RegionHandle;
typedef struct BuilderHandle { void *builder; } BuilderHandle;

typedef struct RegionAccount { void *owner; } RegionAccount;

static int account_gc(lua_State *state) {
    RegionAccount *account = lua_touserdata(state, 1);
    if (account != NULL && account->owner != NULL) {
        /* Clear after the Rust call so normal finalization transfers the Box
         * exactly once. A caught Rust panic leaks rather than exposing a stale
         * freed pointer or unwinding through Lua. */
        nupp_rust_region_account_destroy(account->owner);
        account->owner = NULL;
    }
    return 0;
}

static RegionAccount *account_find(lua_State *state) {
    RegionAccount *account;
    lua_getfield(state, LUA_REGISTRYINDEX, ACCOUNT_REGISTRY);
    account = lua_touserdata(state, -1);
    lua_pop(state, 1);
    return account;
}

static RegionAccount *account_get(lua_State *state) {
    RegionAccount *account = account_find(state);
    if (account != NULL) return account;
    account = lua_newuserdata(state, sizeof *account);
    account->owner = nupp_rust_region_account_new();
    lua_createtable(state, 0, 1);
    lua_pushcclosure(state, account_gc, 0);
    lua_setfield(state, -2, "__gc");
    lua_setmetatable(state, -2);
    lua_setfield(state, LUA_REGISTRYINDEX, ACCOUNT_REGISTRY);
    return account;
}

static void account_charge(lua_State *state, void *block) {
    RegionAccount *account = account_get(state);
    size_t step = account != NULL && account->owner != NULL
        ? nupp_rust_region_account_charge(account->owner, block) : 0;
    if (step != 0) lua_gc(state, LUA_GCSTEP, (int)step);
}

static void account_discharge(lua_State *state, void *block) {
    RegionAccount *account = account_find(state);
    if (account != NULL && account->owner != NULL) {
        nupp_rust_region_account_discharge(account->owner, block);
    }
}

static int region_handle_gc(lua_State *state) {
    RegionHandle *handle = lua_touserdata(state, 1);
    if (handle != NULL && handle->block != NULL) {
        /* Finalizers are idempotent: the Arc owner is released once and the Lua
         * userdata is cleared before it can be observed by another finalizer. */
        account_discharge(state, handle->block);
        nupp_rust_region_release(handle->block);
        handle->block = NULL;
    }
    return 0;
}

static void region_push_handle(lua_State *state, void *block) {
    RegionHandle *handle = lua_newuserdata(state, sizeof *handle);
    handle->block = block;
    lua_getfield(state, LUA_REGISTRYINDEX, REGION_METATABLE);
    if (lua_isnil(state, -1)) {
        lua_pop(state, 1);
        lua_createtable(state, 0, 1);
        lua_pushcclosure(state, region_handle_gc, 0);
        lua_setfield(state, -2, "__gc");
        lua_pushvalue(state, -1);
        lua_setfield(state, LUA_REGISTRYINDEX, REGION_METATABLE);
    }
    lua_setmetatable(state, -2);
    account_charge(state, block);
}

static void *region_block(lua_State *state, int index) {
    RegionHandle *handle = lua_touserdata(state, index);
    void *block = NULL;
    if (handle == NULL || !lua_getmetatable(state, index)) return NULL;
    lua_getfield(state, LUA_REGISTRYINDEX, REGION_METATABLE);
    if (lua_rawequal(state, -1, -2)) block = handle->block;
    lua_pop(state, 2);
    return block;
}

/* --- channels ----------------------------------------------------------- */

static int channel_create(lua_State *state) {
    lua_pushlightuserdata(state, nupp_rust_worker_channel_new());
    return 1;
}

static int channel_destroy(lua_State *state) {
    void *channel = lua_touserdata(state, 1);
    if (channel != NULL) nupp_rust_worker_channel_destroy(channel);
    return 0;
}

static int channel_close(lua_State *state) {
    nupp_rust_worker_channel_close(lua_touserdata(state, 1));
    return 0;
}

static int channel_push(lua_State *state) {
    void *channel = lua_touserdata(state, 1);
    size_t header_length = 0, body_length = 0;
    const char *header = lua_tolstring(state, 2, &header_length);
    const char *body = lua_tolstring(state, 3, &body_length);
    int accepted = channel != NULL && header != NULL && body != NULL
        && nupp_rust_worker_channel_push(channel, MESSAGE_BYTES, 0, 0,
            (const uint8_t *)header, header_length,
            (const uint8_t *)body, body_length, NULL, 0, NULL, 0);
    lua_pushboolean(state, accepted);
    return 1;
}

static int push_scalar(lua_State *state, int kind, int task, int string_value) {
    void *channel = lua_touserdata(state, 1);
    int64_t id = (int64_t)lua_tointeger(state, 2);
    size_t module_length = 0, member_length = 0, value_length = 0;
    const char *module = task ? lua_tolstring(state, 3, &module_length) : NULL;
    const char *member = task ? lua_tolstring(state, 4, &member_length) : NULL;
    int value_index = task ? 5 : 3;
    const char *value = string_value
        ? lua_tolstring(state, value_index, &value_length) : NULL;
    double number = string_value ? 0 : lua_tonumber(state, value_index);
    int accepted = channel != NULL && (!task || (module != NULL && member != NULL))
        && (!string_value || value != NULL)
        && nupp_rust_worker_channel_push(channel, kind, id, number,
            (const uint8_t *)module, module_length,
            (const uint8_t *)member, member_length,
            (const uint8_t *)value, value_length, NULL, 0);
    lua_pushboolean(state, accepted);
    return 1;
}

static int push_number_task(lua_State *state) {
    return push_scalar(state, MESSAGE_NUMBER_TASK, 1, 0);
}
static int push_number_reply(lua_State *state) {
    return push_scalar(state, MESSAGE_NUMBER_REPLY, 0, 0);
}
static int push_string_task(lua_State *state) {
    return push_scalar(state, MESSAGE_STRING_TASK, 1, 1);
}
static int push_string_reply(lua_State *state) {
    return push_scalar(state, MESSAGE_STRING_REPLY, 0, 1);
}

/* Moved pointers are transferred from the call onward. A malformed list frees
 * every moved allocation already handed over; region references are borrowed
 * here and cloned by Rust only if the frame forms. */
static size_t read_attachments(lua_State *state, int index,
    RawAttachment *out) {
    size_t entries, triples, position;
    if (lua_isnoneornil(state, index)) return 0;
    if (lua_type(state, index) != LUA_TTABLE) return (size_t)-1;
    entries = lua_objlen(state, index);
    if (entries % 3 != 0) return (size_t)-1;
    triples = entries / 3;
    if (triples > MAX_ATTACHMENTS) return (size_t)-1;
    for (position = 0; position < triples; ++position) {
        void *block = NULL;
        int kind = ATTACHMENT_REGION;
        lua_Integer first, length;
        lua_rawgeti(state, index, (int)(position * 3 + 1));
        if (lua_type(state, -1) == LUA_TSTRING) {
            size_t pointer_length = 0;
            const char *pointer = lua_tolstring(state, -1, &pointer_length);
            if (pointer_length == sizeof(void *)) {
                kind = ATTACHMENT_MOVED;
                memcpy(&block, pointer, sizeof(void *));
            }
        } else {
            block = region_block(state, -1);
        }
        lua_rawgeti(state, index, (int)(position * 3 + 2));
        first = lua_tointeger(state, -1);
        lua_rawgeti(state, index, (int)(position * 3 + 3));
        length = lua_tointeger(state, -1);
        lua_pop(state, 3);
        if (block == NULL || (kind == ATTACHMENT_MOVED
            ? first < 0 || length < 1 : first < 1 || length < 0)) {
            size_t undo;
            if (kind == ATTACHMENT_MOVED && block != NULL) free(block);
            for (undo = 0; undo < position; ++undo) {
                if (out[undo].kind == ATTACHMENT_MOVED) free(out[undo].block);
            }
            return (size_t)-1;
        }
        out[position].kind = kind;
        out[position].block = block;
        out[position].first = (size_t)first;
        out[position].length = (size_t)length;
    }
    return triples;
}

static int push_buffer(lua_State *state, int kind, int task) {
    void *channel = lua_touserdata(state, 1);
    int64_t id = (int64_t)lua_tointeger(state, 2);
    size_t module_length = 0, member_length = 0, value_length = 0;
    const char *module = task ? lua_tolstring(state, 3, &module_length) : NULL;
    const char *member = task ? lua_tolstring(state, 4, &member_length) : NULL;
    int count_index = task ? 5 : 3;
    int value_index = task ? 6 : 4;
    int attachments_index = task ? 7 : 5;
    double count = lua_tonumber(state, count_index);
    const char *value = lua_tolstring(state, value_index, &value_length);
    RawAttachment attachments[MAX_ATTACHMENTS];
    size_t attachment_count;
    int accepted = 0;
    /* Moved blocks are owned by whoever reads them: by read_attachments until
     * it returns, and by the Rust push from the moment it is called. Reject
     * the fixed arguments first so the blocks are read only when the push
     * will run to take them. */
    if (channel == NULL || value == NULL || (task && (module == NULL || member == NULL))) {
        lua_pushboolean(state, 0);
        return 1;
    }
    attachment_count = read_attachments(state, attachments_index, attachments);
    if (attachment_count != (size_t)-1) {
        accepted = nupp_rust_worker_channel_push(channel, kind, id, count,
            (const uint8_t *)module, module_length,
            (const uint8_t *)member, member_length,
            (const uint8_t *)value, value_length,
            attachments, attachment_count);
    }
    lua_pushboolean(state, accepted);
    return 1;
}

static int push_buffer_task(lua_State *state) {
    return push_buffer(state, MESSAGE_BUFFER_TASK, 1);
}
static int push_buffer_reply(lua_State *state) {
    return push_buffer(state, MESSAGE_BUFFER_REPLY, 0);
}

/* Native record frames are an optimization. Returning nil/zero selects the
 * existing buffer codec, keeping the wire contract smaller and safer. */
static int schema_register(lua_State *state) { lua_pushnil(state); return 1; }
static int push_record(lua_State *state) { lua_pushinteger(state, 0); return 1; }

static int dict_register(lua_State *state) {
    void *channel = lua_touserdata(state, 1);
    size_t length = 0;
    const char *address = lua_tolstring(state, 2, &length);
    size_t answer = channel != NULL && address != NULL
        ? nupp_rust_worker_channel_dict_register(channel,
            (const uint8_t *)address, length) : 0;
    if (answer == 0) lua_pushnil(state); else lua_pushinteger(state, (lua_Integer)answer);
    return 1;
}

static int dict_count(lua_State *state) {
    lua_pushinteger(state, (lua_Integer)nupp_rust_worker_channel_dict_count(
        lua_touserdata(state, 1)));
    return 1;
}

static int dict_address(lua_State *state) {
    size_t length = 0;
    const uint8_t *address = nupp_rust_worker_channel_dict_address(
        lua_touserdata(state, 1), (size_t)lua_tointeger(state, 2), &length);
    if (address == NULL) lua_pushnil(state);
    else lua_pushlstring(state, (const char *)address, length);
    return 1;
}

static void push_message_bytes(lua_State *state, void *message, int which) {
    size_t length = 0;
    const uint8_t *bytes = nupp_rust_worker_message_bytes(message, which, &length);
    lua_pushlstring(state, (const char *)bytes, length);
}

static void push_attachments(lua_State *state, void *message) {
    size_t count = nupp_rust_worker_message_attachment_count(message);
    size_t index;
    if (count == 0) { lua_pushnil(state); return; }
    lua_createtable(state, (int)(count * 3), 0);
    for (index = 0; index < count; ++index) {
        RawAttachment attachment;
        if (!nupp_rust_worker_message_take_attachment(message, index, &attachment)) {
            lua_pushnil(state);
            lua_rawseti(state, -2, (int)(index * 3 + 1));
            continue;
        }
        if (attachment.kind == ATTACHMENT_REGION) {
            region_push_handle(state, attachment.block);
        } else {
            lua_pushlightuserdata(state, attachment.block);
        }
        lua_rawseti(state, -2, (int)(index * 3 + 1));
        lua_pushinteger(state, (lua_Integer)attachment.first);
        lua_rawseti(state, -2, (int)(index * 3 + 2));
        lua_pushinteger(state, (lua_Integer)attachment.length);
        lua_rawseti(state, -2, (int)(index * 3 + 3));
    }
}

static int channel_pop(lua_State *state) {
    lua_Integer timeout = lua_tointeger(state, 2);
    int bounded = timeout < INT32_MIN ? INT32_MIN
        : timeout > INT32_MAX ? INT32_MAX : (int)timeout;
    void *message = nupp_rust_worker_channel_pop(lua_touserdata(state, 1), bounded);
    int kind;
    if (message == NULL) {
        int index;
        for (index = 0; index < 7; ++index) lua_pushnil(state);
        return 7;
    }
    /* `message` remains the unique transferred Box owner until every borrowed
     * byte has been copied into Lua and every attachment has been taken. */
    kind = nupp_rust_worker_message_kind(message);
    if (kind == MESSAGE_BYTES) {
        push_message_bytes(state, message, 0);
        push_message_bytes(state, message, 1);
        lua_pushnil(state); lua_pushnil(state); lua_pushnil(state);
        lua_pushnil(state); lua_pushnil(state);
    } else {
        lua_pushnil(state); lua_pushnil(state);
        lua_pushinteger(state, kind);
        lua_pushinteger(state, (lua_Integer)nupp_rust_worker_message_id(message));
        if (kind == MESSAGE_NUMBER_TASK || kind == MESSAGE_STRING_TASK
            || kind == MESSAGE_BUFFER_TASK) {
            push_message_bytes(state, message, 0);
            push_message_bytes(state, message, 1);
        } else {
            lua_pushnil(state); lua_pushnil(state);
        }
        if (kind == MESSAGE_NUMBER_TASK || kind == MESSAGE_NUMBER_REPLY) {
            lua_pushnumber(state, nupp_rust_worker_message_number(message));
        } else if (kind == MESSAGE_STRING_TASK || kind == MESSAGE_STRING_REPLY
            || kind == MESSAGE_BUFFER_TASK || kind == MESSAGE_BUFFER_REPLY) {
            push_message_bytes(state, message, 2);
        } else {
            lua_pushnil(state);
        }
        if (kind == MESSAGE_BUFFER_TASK || kind == MESSAGE_BUFFER_REPLY) {
            lua_pushnumber(state, nupp_rust_worker_message_number(message));
            push_attachments(state, message);
            nupp_rust_worker_message_destroy(message);
            return 9;
        }
    }
    nupp_rust_worker_message_destroy(message);
    return 7;
}

static int channel_count(lua_State *state) {
    lua_pushinteger(state, (lua_Integer)nupp_rust_worker_channel_count(
        lua_touserdata(state, 1)));
    return 1;
}

static int channel_closed(lua_State *state) {
    lua_pushboolean(state, nupp_rust_worker_channel_closed(
        lua_touserdata(state, 1)));
    return 1;
}

/* --- workers and task cancellation ------------------------------------- */

static void *global_pointer(lua_State *state, const char *name) {
    void *answer;
    lua_getfield(state, LUA_GLOBALSINDEX, name);
    answer = lua_touserdata(state, -1);
    lua_pop(state, 1);
    return answer;
}

static int worker_spawn(lua_State *state) {
    char error[4096] = {0};
    /* Host and channels remain owned by HostRuntime/Lua until the returned
     * worker is joined. Rust clones channel Arcs before this callback returns. */
    void *worker = nupp_rust_worker_spawn(
        global_pointer(state, "__nuppWorkerHost"),
        lua_touserdata(state, 1), lua_touserdata(state, 2),
        error, sizeof error);
    if (worker == NULL) {
        lua_pushnil(state);
        lua_pushstring(state, error[0] != '\0' ? error : "cannot start worker");
        return 2;
    }
    lua_pushlightuserdata(state, worker);
    return 1;
}

static int worker_join(lua_State *state) {
    char error[4096] = {0};
    int status = nupp_rust_worker_join(lua_touserdata(state, 1), error, sizeof error);
    lua_pushinteger(state, status);
    if (error[0] == '\0') lua_pushnil(state); else lua_pushstring(state, error);
    return 2;
}

static int task_create(lua_State *state) {
    int has_deadline = !lua_isnoneornil(state, 3);
    double deadline = has_deadline ? lua_tonumber(state, 3) : 0;
    lua_pushboolean(state, nupp_rust_worker_task_create(
        lua_touserdata(state, 1), (int64_t)lua_tointeger(state, 2),
        has_deadline && isfinite(deadline), deadline));
    return 1;
}

static int task_cancel(lua_State *state) {
    lua_pushinteger(state, nupp_rust_worker_task_cancel(
        lua_touserdata(state, 1), (int64_t)lua_tointeger(state, 2)));
    return 1;
}

static int task_start(lua_State *state) {
    int deadline = 0;
    int run = nupp_rust_worker_task_start(
        global_pointer(state, "__nuppWorkerTasks"),
        (int64_t)lua_tointeger(state, 1), &deadline);
    lua_pushboolean(state, run);
    lua_pushboolean(state, deadline);
    return 2;
}

static int task_checkpoint(lua_State *state) {
    int deadline = 0;
    int cancelled = nupp_rust_worker_task_checkpoint(
        global_pointer(state, "__nuppWorkerTasks"), &deadline);
    lua_pushboolean(state, cancelled);
    lua_pushboolean(state, deadline);
    return 2;
}

static int task_finish(lua_State *state) {
    int deadline = 0;
    int cancelled = nupp_rust_worker_task_finish(
        global_pointer(state, "__nuppWorkerTasks"),
        (int64_t)lua_tointeger(state, 1), &deadline);
    lua_pushboolean(state, cancelled);
    lua_pushboolean(state, deadline);
    return 2;
}

static int task_release(lua_State *state) {
    nupp_rust_worker_task_release(lua_touserdata(state, 1),
        (int64_t)lua_tointeger(state, 2));
    return 0;
}

static int task_status(lua_State *state) {
    lua_pushinteger(state, nupp_rust_worker_task_status(
        lua_touserdata(state, 1), (int64_t)lua_tointeger(state, 2)));
    return 1;
}

static int current(lua_State *state) {
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppWorkerIn");
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppWorkerOut");
    return 2;
}

static int parallelism(lua_State *state) {
    lua_pushinteger(state, (lua_Integer)nupp_rust_worker_parallelism());
    return 1;
}

/* --- shared bytes surface ---------------------------------------------- */

static int region_from_string(lua_State *state) {
    size_t length = 0;
    const char *text = lua_tolstring(state, 1, &length);
    void *block = text != NULL
        ? nupp_rust_region_new((const uint8_t *)text, length) : NULL;
    if (block == NULL) { lua_pushnil(state); lua_pushnil(state); return 2; }
    region_push_handle(state, block);
    lua_pushinteger(state, (lua_Integer)length);
    return 2;
}

static int region_read_file(lua_State *state) {
    size_t length = 0;
    const char *path = lua_tolstring(state, 1, &length);
    char error[1024] = {0};
    void *block = path != NULL ? nupp_rust_region_read_file(
        (const uint8_t *)path, length, error, sizeof error) : NULL;
    if (block == NULL) {
        lua_pushnil(state);
        lua_pushstring(state, error[0] != '\0' ? error : "a file path is required");
        return 2;
    }
    region_push_handle(state, block);
    lua_pushnil(state);
    return 2;
}

static int region_text(lua_State *state) {
    void *block = region_block(state, 1);
    lua_Integer first = lua_tointeger(state, 2);
    lua_Integer last = lua_tointeger(state, 3);
    size_t length = block != NULL ? nupp_rust_region_length(block) : 0;
    if (block == NULL || first < 1 || last > (lua_Integer)length || first > last + 1) {
        lua_pushnil(state);
    } else {
        lua_pushlstring(state,
            (const char *)nupp_rust_region_data(block) + (first - 1),
            (size_t)(last - first + 1));
    }
    return 1;
}

static int region_pointer(lua_State *state) {
    void *block = region_block(state, 1);
    if (block == NULL) lua_pushnil(state);
    else lua_pushlightuserdata(state, (void *)nupp_rust_region_data(block));
    return 1;
}

static int region_length(lua_State *state) {
    void *block = region_block(state, 1);
    if (block == NULL) lua_pushnil(state);
    else lua_pushinteger(state, (lua_Integer)nupp_rust_region_length(block));
    return 1;
}

static int builder_gc(lua_State *state) {
    BuilderHandle *handle = lua_touserdata(state, 1);
    if (handle != NULL && handle->builder != NULL) {
        /* Rust owns all reservation storage. Destruction invalidates a borrowed
         * reservation pointer, which Lua cannot use safely after dropping the
         * builder handle; clearing makes repeated finalization harmless. */
        nupp_rust_region_builder_destroy(handle->builder);
        handle->builder = NULL;
    }
    return 0;
}

static int builder_new(lua_State *state) {
    BuilderHandle *handle = lua_newuserdata(state, sizeof *handle);
    handle->builder = nupp_rust_region_builder_new();
    if (handle->builder == NULL) { lua_pushnil(state); return 1; }
    lua_getfield(state, LUA_REGISTRYINDEX, BUILDER_METATABLE);
    if (lua_isnil(state, -1)) {
        lua_pop(state, 1);
        lua_createtable(state, 0, 1);
        lua_pushcclosure(state, builder_gc, 0);
        lua_setfield(state, -2, "__gc");
        lua_pushvalue(state, -1);
        lua_setfield(state, LUA_REGISTRYINDEX, BUILDER_METATABLE);
    }
    lua_setmetatable(state, -2);
    return 1;
}

static int builder_append(lua_State *state) {
    BuilderHandle *handle = lua_touserdata(state, 1);
    size_t length = 0;
    const char *data = lua_tolstring(state, 2, &length);
    int accepted = handle != NULL && handle->builder != NULL && data != NULL
        && nupp_rust_region_builder_append(handle->builder,
            (const uint8_t *)data, length);
    lua_pushboolean(state, accepted);
    if (accepted || handle == NULL || handle->builder == NULL
        || !nupp_rust_region_builder_open(handle->builder)) lua_pushnil(state);
    else lua_pushliteral(state, "open");
    return 2;
}

static int builder_reserve(lua_State *state) {
    BuilderHandle *handle = lua_touserdata(state, 1);
    lua_Integer count = lua_tointeger(state, 2);
    void *pointer = handle != NULL && handle->builder != NULL && count >= 0
        ? nupp_rust_region_builder_reserve(handle->builder, (size_t)count) : NULL;
    if (pointer == NULL) lua_pushnil(state); else lua_pushlightuserdata(state, pointer);
    if (pointer != NULL || handle == NULL || handle->builder == NULL
        || !nupp_rust_region_builder_open(handle->builder)) lua_pushnil(state);
    else lua_pushliteral(state, "open");
    return 2;
}

static int builder_commit(lua_State *state) {
    BuilderHandle *handle = lua_touserdata(state, 1);
    lua_Integer written = lua_tointeger(state, 2);
    lua_pushboolean(state, handle != NULL && handle->builder != NULL && written >= 0
        && nupp_rust_region_builder_commit(handle->builder, (size_t)written));
    return 1;
}

static int builder_freeze(lua_State *state) {
    BuilderHandle *handle = lua_touserdata(state, 1);
    void *block = handle != NULL && handle->builder != NULL
        ? nupp_rust_region_builder_freeze(handle->builder) : NULL;
    if (block == NULL) {
        lua_pushnil(state);
        if (handle != NULL && handle->builder != NULL
            && nupp_rust_region_builder_open(handle->builder)) {
            lua_pushliteral(state, "open");
        } else {
            lua_pushnil(state);
        }
        return 2;
    }
    region_push_handle(state, block);
    lua_pushinteger(state, (lua_Integer)nupp_rust_region_length(block));
    return 2;
}

static int region_accounted(lua_State *state) {
    RegionAccount *account = account_find(state);
    lua_pushinteger(state, (lua_Integer)(account != NULL && account->owner != NULL
        ? nupp_rust_region_accounted(account->owner) : 0));
    return 1;
}

static void field(lua_State *state, const char *name, lua_CFunction function) {
    lua_pushcclosure(state, function, 0);
    lua_setfield(state, -2, name);
}

int nupp_luaopen_workers(lua_State *state) {
    lua_createtable(state, 0, 24);
    field(state, "channelCreate", channel_create);
    field(state, "channelDestroy", channel_destroy);
    field(state, "channelClose", channel_close);
    field(state, "channelPush", channel_push);
    field(state, "channelPushNumberTask", push_number_task);
    field(state, "channelPushNumberReply", push_number_reply);
    field(state, "channelPushStringTask", push_string_task);
    field(state, "channelPushStringReply", push_string_reply);
    field(state, "channelSchemaRegister", schema_register);
    field(state, "channelPushRecordTask", push_record);
    field(state, "channelPushRecordReply", push_record);
    field(state, "channelDictRegister", dict_register);
    field(state, "channelDictCount", dict_count);
    field(state, "channelDictAddress", dict_address);
    field(state, "channelPushBufferTask", push_buffer_task);
    field(state, "channelPushBufferReply", push_buffer_reply);
    field(state, "channelPop", channel_pop);
    field(state, "channelCount", channel_count);
    field(state, "channelClosed", channel_closed);
    field(state, "workerSpawn", worker_spawn);
    field(state, "workerJoin", worker_join);
    field(state, "workerTaskCreate", task_create);
    field(state, "workerTaskCancel", task_cancel);
    field(state, "workerTaskStart", task_start);
    field(state, "workerTaskCheckpoint", task_checkpoint);
    field(state, "workerTaskFinish", task_finish);
    field(state, "workerTaskRelease", task_release);
    field(state, "workerTaskStatus", task_status);
    field(state, "current", current);
    field(state, "workerParallelism", parallelism);
    return 1;
}

int nupp_luaopen_sharedbytes(lua_State *state) {
    lua_createtable(state, 0, 11);
    field(state, "fromString", region_from_string);
    field(state, "readFile", region_read_file);
    field(state, "text", region_text);
    field(state, "pointer", region_pointer);
    field(state, "length", region_length);
    field(state, "builderNew", builder_new);
    field(state, "builderAppend", builder_append);
    field(state, "builderReserve", builder_reserve);
    field(state, "builderCommit", builder_commit);
    field(state, "builderFreeze", builder_freeze);
    field(state, "accounted", region_accounted);
    return 1;
}
