#include <limits.h>
#include <stddef.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

typedef struct NuppLuaBytes {
    const char *data;
    size_t length;
} NuppLuaBytes;

typedef struct ProtectedCall {
    char *error;
    size_t error_capacity;
    int status;
} ProtectedCall;

typedef struct StringCall {
    ProtectedCall call;
    const char *data;
    size_t length;
} StringCall;

typedef struct ArgumentsCall {
    ProtectedCall call;
    const NuppLuaBytes *arguments;
    size_t count;
} ArgumentsCall;

typedef struct RunCall {
    ProtectedCall call;
    const char *chunk;
    size_t chunk_length;
    const char *name;
} RunCall;

typedef struct PreloadCall {
    ProtectedCall call;
    const char *module;
    const char *source;
    size_t source_length;
    const char *name;
} PreloadCall;

typedef struct ProtectedDispatch {
    ProtectedCall *call;
    lua_CFunction function;
} ProtectedDispatch;

static void copy_error(ProtectedCall *call, const char *text, size_t length) {
    if (call->error == NULL || call->error_capacity == 0) return;
    if (length >= call->error_capacity) length = call->error_capacity - 1;
    if (length != 0) memcpy(call->error, text, length);
    call->error[length] = '\0';
}

static void fallback_error(ProtectedCall *call) {
    static const char fallback[] = "LuaJIT protected operation failed";
    copy_error(call, fallback, sizeof fallback - 1);
}

/* This itself runs inside the outer lua_cpcall. lua_tolstring may allocate
 * while converting a numeric error, so even error extraction must stay here. */
static void capture_error(lua_State *state, ProtectedCall *call, int status) {
    size_t length = 0;
    const char *text = lua_tolstring(state, -1, &length);
    call->status = status;
    if (text == NULL) {
        static const char unknown[] = "unknown LuaJIT error";
        copy_error(call, unknown, sizeof unknown - 1);
    } else {
        copy_error(call, text, length);
    }
}

static int open_libraries(lua_State *state) {
    luaL_openlibs(state);
    return 0;
}

static int install_host_record(lua_State *state) {
    lua_createtable(state, 0, 3);
    lua_pushinteger(state, 1);
    lua_setfield(state, -2, "hostAbi");
    lua_createtable(state, 0, 0);
    lua_setfield(state, -2, "hostFeatures");
    lua_createtable(state, 0, 0);
    lua_setfield(state, -2, "resources");
    lua_setfield(state, LUA_GLOBALSINDEX, "__nuppHost");
    return 0;
}

static int set_executable(lua_State *state) {
    StringCall *context = (StringCall *)lua_touserdata(state, 1);
    lua_pushlstring(state, context->data, context->length);
    lua_setfield(state, LUA_GLOBALSINDEX, "__NUPP_EXECUTABLE");
    return 0;
}

static int set_arguments(lua_State *state) {
    ArgumentsCall *context = (ArgumentsCall *)lua_touserdata(state, 1);
    size_t index;
    lua_createtable(state, (int)context->count, 0);
    for (index = 0; index < context->count; ++index) {
        lua_pushlstring(state, context->arguments[index].data,
            context->arguments[index].length);
        lua_rawseti(state, -2, (int)index + 1);
    }
    lua_setfield(state, LUA_GLOBALSINDEX, "arg");
    return 0;
}

static int run_chunk(lua_State *state) {
    RunCall *context = (RunCall *)lua_touserdata(state, 1);
    int status = luaL_loadbuffer(state, context->chunk,
        context->chunk_length, context->name);
    if (status != 0) {
        capture_error(state, &context->call, status);
        return 0;
    }
    status = lua_pcall(state, 0, 0, 0);
    if (status != 0) capture_error(state, &context->call, status);
    return 0;
}

static int preload_module(lua_State *state) {
    PreloadCall *context = (PreloadCall *)lua_touserdata(state, 1);
    int status = luaL_loadbuffer(state, context->source,
        context->source_length, context->name);
    if (status != 0) {
        capture_error(state, &context->call, status);
        return 0;
    }
    lua_getfield(state, LUA_GLOBALSINDEX, "package");
    lua_getfield(state, -1, "preload");
    if (lua_type(state, -1) != LUA_TTABLE) {
        static const char missing[] =
            "pinned LuaJIT did not install package.preload";
        context->call.status = LUA_ERRRUN;
        copy_error(&context->call, missing, sizeof missing - 1);
        return 0;
    }
    lua_pushvalue(state, -3);
    lua_setfield(state, -2, context->module);
    return 0;
}

/* The outer cpcall protects construction of this inner protected call. The
 * inner pcall catches an operation or metamethod error while this C frame is
 * still live, which lets error conversion happen without exposing Rust to a
 * longjmp either. */
static int protected_dispatch(lua_State *state) {
    ProtectedDispatch *dispatch =
        (ProtectedDispatch *)lua_touserdata(state, 1);
    int status;
    lua_pushcfunction(state, dispatch->function);
    lua_pushlightuserdata(state, dispatch->call);
    status = lua_pcall(state, 1, 0, 0);
    if (status != 0) capture_error(state, dispatch->call, status);
    return 0;
}

static int protect(lua_State *state, lua_CFunction function,
    ProtectedCall *call) {
    int base = lua_gettop(state);
    int outer_status;
    ProtectedDispatch dispatch = {call, function};
    call->status = 0;
    fallback_error(call);
    /* lua_cpcall enters a protected LuaJIT C frame without allocating a Lua
     * closure first. Any allocation failure or metamethod error below returns
     * here instead of longjmping through the Rust caller. */
    outer_status = lua_cpcall(state, protected_dispatch, &dispatch);
    lua_settop(state, base);
    return outer_status != 0 ? outer_status : call->status;
}

int nupp_lua_openlibs(lua_State *state, char *error, size_t error_capacity) {
    ProtectedCall call = {error, error_capacity, 0};
    return protect(state, open_libraries, &call);
}

int nupp_lua_install_host_record(lua_State *state, char *error,
    size_t error_capacity) {
    ProtectedCall call = {error, error_capacity, 0};
    return protect(state, install_host_record, &call);
}

int nupp_lua_set_executable(lua_State *state, const char *data, size_t length,
    char *error, size_t error_capacity) {
    StringCall context = {{error, error_capacity, 0}, data, length};
    return protect(state, set_executable, &context.call);
}

int nupp_lua_set_arguments(lua_State *state, const NuppLuaBytes *arguments,
    size_t count, char *error, size_t error_capacity) {
    ArgumentsCall context = {{error, error_capacity, 0}, arguments, count};
    if (count > INT_MAX) {
        static const char too_many[] =
            "too many arguments for LuaJIT's arg table";
        copy_error(&context.call, too_many, sizeof too_many - 1);
        return LUA_ERRRUN;
    }
    return protect(state, set_arguments, &context.call);
}

int nupp_lua_run(lua_State *state, const char *chunk, size_t chunk_length,
    const char *name, char *error, size_t error_capacity) {
    RunCall context = {
        {error, error_capacity, 0}, chunk, chunk_length, name
    };
    return protect(state, run_chunk, &context.call);
}

int nupp_lua_preload(lua_State *state, const char *module,
    const char *source, size_t source_length, const char *name,
    char *error, size_t error_capacity) {
    PreloadCall context = {
        {error, error_capacity, 0}, module, source, source_length, name
    };
    return protect(state, preload_module, &context.call);
}
