/* Lua stack adapter for the embedding application's host channel.
 *
 * `nupp.host` requests reach the application's registered C handlers through
 * this module, `nupp.host.native`, which the runtime preloads when an
 * application creates or attaches it.
 *
 * Stack and longjmp: as in worker_shim.c, every lua_* operation runs in a Lua C
 * callback whose caller holds a protected frame, so a failure may longjmp
 * through this file but never through Rust. Rust is reached only through the
 * adapter table below, between Lua operations, and every entry is a Rust panic
 * firewall that answers a conservative value.
 *
 * Ownership: a handler's arguments are borrowed for the length of its call. A
 * string argument's bytes belong to the Lua string on this frame's stack; a byte
 * argument's belong to the span the caller holds, which outlives the call. An
 * answer belongs to Rust from `nupp_host_answer` until `release`, and is copied
 * into Lua values before it is released.
 *
 * Handlers run here, from a Lua C function rather than through the FFI, so a
 * handler may call back into the runtime that called it.
 */

#include <stdint.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>

#define MAX_VALUES 255

enum {
    VALUE_NIL = 0,
    VALUE_BOOLEAN = 1,
    VALUE_NUMBER = 2,
    VALUE_STRING = 3,
    VALUE_BYTES = 4,
    VALUE_HANDLE = 5
};

/* Must match `nupp_value` in host/include/nupp.h. */
typedef struct NuppHostValue {
    uint32_t kind;
    int boolean;
    double number;
    unsigned char *data;
    size_t length;
    void *handle;
} NuppHostValue;

typedef void (*NuppHostHandler)(void *runtime, uint64_t request, const char *kind,
    const NuppHostValue *arguments, size_t count, void *userdata);
typedef void (*NuppHostCancel)(void *runtime, uint64_t request, void *userdata);

/* The Rust half, handed over once per process before any runtime opens this
 * module. Field order and signatures must exactly match `HostAdapterTable` in
 * host_channel.rs. */
typedef struct NuppRustHostAdapter {
    /* 1 and the handler's registration when `kind` has one, else 0. */
    int (*lookup)(const void *channel, const char *kind, size_t length,
        NuppHostHandler *handler, void **userdata, void **runtime);
    /* Records a request about to be dispatched: 1, or 0 for a duplicate id. */
    int (*dispatched)(const void *channel, uint64_t request, int post,
        const char *kind, size_t length);
    /* 0 while unanswered, 1 answered, 2 failed; fills the answer's view. */
    int (*answer)(const void *channel, uint64_t request, size_t *count,
        const NuppHostValue **values, const char **message, size_t *message_length);
    /* Frees a taken answer and forgets the request. */
    void (*release)(const void *channel, uint64_t request);
    /* Copies up to `capacity` answered request ids; answers how many. */
    size_t (*ready)(const void *channel, uint64_t *requests, size_t capacity);
    /* Marks a request abandoned; 1 and its kind's cancel callback when it has one. */
    int (*cancelled)(const void *channel, uint64_t request, NuppHostCancel *cancel,
        void **userdata, void **runtime);
    /* 1 and the next pushed message, borrowed until the next pop, or 0. */
    int (*pop)(const void *channel, const char **kind, size_t *kind_length,
        size_t *count, const NuppHostValue **values);
} NuppRustHostAdapter;

static const NuppRustHostAdapter *rust;

void nupp_host_shim_install(const NuppRustHostAdapter *table) {
    rust = table;
}

static const void *channel_of(lua_State *state) {
    const void *channel;
    lua_pushliteral(state, "__nuppHostChannel");
    lua_rawget(state, LUA_GLOBALSINDEX);
    channel = lua_islightuserdata(state, -1) ? lua_touserdata(state, -1) : NULL;
    lua_pop(state, 1);
    return channel;
}

static const void *required_channel(lua_State *state) {
    const void *channel = channel_of(state);
    if (channel == NULL || rust == NULL) {
        luaL_error(state, "no embedding application is attached to this runtime");
    }
    return channel;
}

static uint64_t request_id(lua_State *state, int index) {
    lua_Number number = luaL_checknumber(state, index);
    if (number < 1 || number > 9007199254740991.0 || number != (lua_Number)(uint64_t)number) {
        luaL_argerror(state, index, "a request id must be a positive integer");
    }
    return (uint64_t)number;
}

static int attached(lua_State *state) {
    lua_pushboolean(state, channel_of(state) != NULL && rust != NULL);
    return 1;
}

/* dispatch(operation, request, kind, count, bytes, ...) calls the kind's handler.
 * `bytes[i]` is `{address, length}` for a byte argument at position i. Answers
 * true, or false and a reason when no handler answers the kind. */
static int dispatch(lua_State *state) {
    const void *channel = required_channel(state);
    int operation = (int)luaL_checkinteger(state, 1);
    int post = operation == 1;
    uint64_t request = request_id(state, 2);
    size_t kind_length;
    const char *kind = luaL_checklstring(state, 3, &kind_length);
    lua_Integer count = luaL_checkinteger(state, 4);
    int has_bytes = lua_istable(state, 5);
    NuppHostValue values[MAX_VALUES];
    NuppHostHandler handler = NULL;
    void *userdata = NULL;
    void *runtime = NULL;
    if (count < 0 || count > MAX_VALUES || lua_gettop(state) < 5 + count) {
        return luaL_error(state, "a host request has no valid value count");
    }
    if (!rust->lookup(channel, kind, kind_length, &handler, &userdata, &runtime) || handler == NULL) {
        lua_pushboolean(state, 0);
        lua_pushfstring(state, "no host answers %s", kind);
        return 2;
    }
    for (lua_Integer position = 1; position <= count; position++) {
        int index = (int)(5 + position);
        NuppHostValue *value = &values[position - 1];
        memset(value, 0, sizeof *value);
        if (has_bytes) {
            lua_rawgeti(state, 5, (int)position);
            if (lua_istable(state, -1)) {
                lua_rawgeti(state, -1, 1);
                lua_rawgeti(state, -2, 2);
                value->kind = VALUE_BYTES;
                value->data = (unsigned char *)(uintptr_t)lua_tonumber(state, -2);
                value->length = (size_t)lua_tonumber(state, -1);
                lua_pop(state, 3);
                continue;
            }
            lua_pop(state, 1);
        }
        switch (lua_type(state, index)) {
        case LUA_TNIL:
            value->kind = VALUE_NIL;
            break;
        case LUA_TBOOLEAN:
            value->kind = VALUE_BOOLEAN;
            value->boolean = lua_toboolean(state, index);
            break;
        case LUA_TNUMBER:
            value->kind = VALUE_NUMBER;
            value->number = lua_tonumber(state, index);
            break;
        case LUA_TSTRING:
            value->kind = VALUE_STRING;
            value->data = (unsigned char *)(uintptr_t)lua_tolstring(state, index, &value->length);
            break;
        default:
            return luaL_error(state, "host request %s value %d cannot cross", kind, (int)position);
        }
    }
    /* A send has no answer, so nothing records it; its handler sees request 0. */
    if (operation == 2) {
        handler(runtime, 0, kind, values, (size_t)count, userdata);
        lua_pushboolean(state, 1);
        return 1;
    }
    if (!rust->dispatched(channel, request, post, kind, kind_length)) {
        return luaL_error(state, "host request %d was dispatched twice", (int)request);
    }
    handler(runtime, request, kind, values, (size_t)count, userdata);
    lua_pushboolean(state, 1);
    return 1;
}

/* take(request) answers nothing while the host has not answered; false and the
 * host's message when it failed; or true, a kind letter per value ("n", "b",
 * "d", "s" for text, "y" for bytes) and the values themselves. */
static int take(lua_State *state) {
    const void *channel = required_channel(state);
    uint64_t request = request_id(state, 1);
    size_t count = 0;
    const NuppHostValue *values = NULL;
    const char *message = NULL;
    size_t message_length = 0;
    char kinds[MAX_VALUES];
    int status = rust->answer(channel, request, &count, &values, &message, &message_length);
    if (status == 0) return 0;
    if (status == 2) {
        lua_pushboolean(state, 0);
        lua_pushlstring(state, message != NULL ? message : "", message_length);
        rust->release(channel, request);
        return 2;
    }
    if (count > MAX_VALUES || !lua_checkstack(state, (int)count + 4)) {
        rust->release(channel, request);
        return luaL_error(state, "a host answer has too many values");
    }
    lua_pushboolean(state, 1);
    for (size_t index = 0; index < count; index++) {
        switch (values[index].kind) {
        case VALUE_BOOLEAN: kinds[index] = 'b'; break;
        case VALUE_NUMBER: kinds[index] = 'd'; break;
        case VALUE_STRING: kinds[index] = 's'; break;
        case VALUE_BYTES: kinds[index] = 'y'; break;
        default: kinds[index] = 'n'; break;
        }
    }
    lua_pushlstring(state, kinds, count);
    for (size_t index = 0; index < count; index++) {
        const NuppHostValue *value = &values[index];
        switch (value->kind) {
        case VALUE_BOOLEAN:
            lua_pushboolean(state, value->boolean);
            break;
        case VALUE_NUMBER:
            lua_pushnumber(state, value->number);
            break;
        case VALUE_STRING:
        case VALUE_BYTES:
            lua_pushlstring(state, (const char *)value->data, value->length);
            break;
        default:
            lua_pushnil(state);
            break;
        }
    }
    rust->release(channel, request);
    return (int)count + 2;
}

/* ready() answers the ids of the requests answered since it was last asked. */
static int ready(lua_State *state) {
    const void *channel = required_channel(state);
    uint64_t requests[64];
    int index = 0;
    size_t taken;
    lua_createtable(state, 0, 0);
    do {
        taken = rust->ready(channel, requests, 64);
        for (size_t each = 0; each < taken; each++) {
            lua_pushnumber(state, (lua_Number)requests[each]);
            lua_rawseti(state, -2, ++index);
        }
    } while (taken == 64);
    return 1;
}

/* cancel(request) marks a request abandoned and tells its kind's host. */
static int cancel(lua_State *state) {
    const void *channel = required_channel(state);
    uint64_t request = request_id(state, 1);
    NuppHostCancel callback = NULL;
    void *userdata = NULL;
    void *runtime = NULL;
    if (rust->cancelled(channel, request, &callback, &userdata, &runtime) && callback != NULL) {
        callback(runtime, request, userdata);
    }
    return 0;
}

/* drain(list) moves every pushed message into list, in push order and flat:
 * each message is its kind, its value count and its values. Answers how many
 * slots it wrote, so one call and no table per message carries a frame's
 * input, however many messages it holds. */
static int drain(lua_State *state) {
    const void *channel = required_channel(state);
    const char *kind = NULL;
    size_t kind_length = 0, count = 0;
    const NuppHostValue *values = NULL;
    lua_Integer slot = 0;
    luaL_checktype(state, 1, LUA_TTABLE);
    while (rust->pop(channel, &kind, &kind_length, &count, &values)) {
        if (count > MAX_VALUES) return luaL_error(state, "a pushed host message has too many values");
        lua_pushlstring(state, kind, kind_length);
        lua_rawseti(state, 1, (int)++slot);
        lua_pushinteger(state, (lua_Integer)count);
        lua_rawseti(state, 1, (int)++slot);
        for (size_t index = 0; index < count; index++) {
            const NuppHostValue *value = &values[index];
            switch (value->kind) {
            case VALUE_BOOLEAN: lua_pushboolean(state, value->boolean); break;
            case VALUE_NUMBER: lua_pushnumber(state, value->number); break;
            case VALUE_STRING: lua_pushlstring(state, (const char *)value->data, value->length); break;
            default: lua_pushnil(state); break;
            }
            lua_rawseti(state, 1, (int)++slot);
        }
    }
    lua_pushinteger(state, slot);
    return 1;
}

static void field(lua_State *state, const char *name, lua_CFunction function) {
    lua_pushcclosure(state, function, 0);
    lua_setfield(state, -2, name);
}

int nupp_luaopen_host_channel(lua_State *state) {
    lua_createtable(state, 0, 6);
    field(state, "attached", attached);
    field(state, "dispatch", dispatch);
    field(state, "take", take);
    field(state, "ready", ready);
    field(state, "cancel", cancel);
    field(state, "drain", drain);
    return 1;
}
