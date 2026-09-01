#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
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

typedef struct FeatureCall {
    ProtectedCall call;
    const char *name;
} FeatureCall;

typedef struct ResourceCall {
    ProtectedCall call;
    const char *path;
    const char *data;
    size_t length;
} ResourceCall;

typedef struct ComponentCall {
    ProtectedCall call;
    const char *chunk;
    size_t chunk_length;
    const char *name;
    int reference;
} ComponentCall;

typedef struct ComponentStartCall {
    ProtectedCall call;
    int reference;
    const NuppLuaBytes *arguments;
    size_t count;
} ComponentStartCall;

typedef struct ExportCall {
    ProtectedCall call;
    int component;
    const char *name;
    int reference;
} ExportCall;

typedef struct ReferenceCall {
    ProtectedCall call;
    int reference;
} ReferenceCall;

typedef struct NuppLuaValue {
    uint32_t kind;
    int boolean;
    double number;
    const char *data;
    size_t length;
    int reference;
} NuppLuaValue;

typedef struct ValuesCall {
    ProtectedCall call;
    int callable;
    const NuppLuaValue *arguments;
    size_t argument_count;
    int results;
    size_t result_count;
} ValuesCall;

typedef struct ResultCall {
    ProtectedCall call;
    int results;
    size_t index;
    char *data;
    size_t capacity;
    NuppLuaValue value;
} ResultCall;

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

static void fail_call(ProtectedCall *call, const char *text) {
    call->status = LUA_ERRRUN;
    copy_error(call, text, strlen(text));
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

static void push_arguments(lua_State *state, const NuppLuaBytes *arguments,
    size_t count) {
    size_t index;
    lua_createtable(state, (int)count, 0);
    for (index = 0; index < count; ++index) {
        lua_pushlstring(state, arguments[index].data, arguments[index].length);
        lua_rawseti(state, -2, (int)index + 1);
    }
    lua_setfield(state, LUA_GLOBALSINDEX, "arg");
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

static int verify_compatibility(lua_State *state) {
    static const char check[] =
        "local major,minor,build=tostring(jit and jit.version or '')"
        ":match('^LuaJIT (%d+)%.(%d+)%.(%d+)$'); "
        "major,minor,build=tonumber(major),tonumber(minor),tonumber(build); "
        "assert(major and (major>2 or (major==2 and (minor>1 or "
        "(minor==1 and build>=1784535649)))), "
        "'nupp: attached state requires LuaJIT 2.1.1784535649 or newer')";
    ProtectedCall *call = (ProtectedCall *)lua_touserdata(state, 1);
    int status = luaL_loadbuffer(state, check, sizeof check - 1,
        "=nupp-compatibility");
    if (status == 0) status = lua_pcall(state, 0, 0, 0);
    if (status != 0) capture_error(state, call, status);
    return 0;
}

static int add_feature(lua_State *state) {
    FeatureCall *context = (FeatureCall *)lua_touserdata(state, 1);
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppHost");
    lua_getfield(state, -1, "hostFeatures");
    if (lua_type(state, -1) != LUA_TTABLE) {
        fail_call(&context->call, "the Nupp host feature table is missing");
        return 0;
    }
    lua_pushboolean(state, 1);
    lua_setfield(state, -2, context->name);
    return 0;
}

static int add_resource(lua_State *state) {
    ResourceCall *context = (ResourceCall *)lua_touserdata(state, 1);
    lua_getfield(state, LUA_GLOBALSINDEX, "__nuppHost");
    lua_getfield(state, -1, "resources");
    if (lua_type(state, -1) != LUA_TTABLE) {
        fail_call(&context->call, "the Nupp host resource table is missing");
        return 0;
    }
    lua_pushlstring(state, context->data, context->length);
    lua_setfield(state, -2, context->path);
    return 0;
}

static int install_component(lua_State *state) {
    ComponentCall *context = (ComponentCall *)lua_touserdata(state, 1);
    int status;
    lua_Integer format;
    lua_Integer host_abi;
    char problem[160];

    status = luaL_loadbuffer(state, context->chunk, context->chunk_length,
        context->name);
    if (status == 0) status = lua_pcall(state, 0, 1, 0);
    if (status != 0) {
        capture_error(state, &context->call, status);
        return 0;
    }
    if (lua_type(state, -1) != LUA_TTABLE) {
        fail_call(&context->call,
            "a Nupp component descriptor did not return a table");
        return 0;
    }
    lua_getfield(state, -1, "format");
    format = lua_tointeger(state, -1);
    lua_pop(state, 1);
    if (format != 1) {
        snprintf(problem, sizeof problem,
            "unsupported Nupp component format %d", (int)format);
        fail_call(&context->call, problem);
        return 0;
    }
    lua_getfield(state, -1, "hostAbi");
    host_abi = lua_tointeger(state, -1);
    lua_pop(state, 1);
    if (host_abi != 1) {
        snprintf(problem, sizeof problem,
            "Nupp component requires compiler host ABI %d, but this runtime provides ABI 1",
            (int)host_abi);
        fail_call(&context->call, problem);
        return 0;
    }
    lua_getfield(state, -1, "install");
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        fail_call(&context->call,
            "a Nupp component descriptor has no installer");
        return 0;
    }
    status = lua_pcall(state, 0, 1, 0);
    if (status != 0) {
        capture_error(state, &context->call, status);
        return 0;
    }
    if (lua_type(state, -1) != LUA_TTABLE) {
        fail_call(&context->call,
            "a Nupp component installer did not return a table");
        return 0;
    }
    context->reference = luaL_ref(state, LUA_REGISTRYINDEX);
    return 0;
}

static int start_component(lua_State *state) {
    ComponentStartCall *context =
        (ComponentStartCall *)lua_touserdata(state, 1);
    int status;
    push_arguments(state, context->arguments, context->count);
    lua_rawgeti(state, LUA_REGISTRYINDEX, context->reference);
    lua_getfield(state, -1, "start");
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        fail_call(&context->call, "the component has no callable start");
        return 0;
    }
    status = lua_pcall(state, 0, 0, 0);
    if (status != 0) capture_error(state, &context->call, status);
    return 0;
}

static int find_export(lua_State *state) {
    ExportCall *context = (ExportCall *)lua_touserdata(state, 1);
    lua_rawgeti(state, LUA_REGISTRYINDEX, context->component);
    lua_getfield(state, -1, "exports");
    if (lua_type(state, -1) != LUA_TTABLE) {
        fail_call(&context->call, "the component has no export table");
        return 0;
    }
    lua_getfield(state, -1, context->name);
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        fail_call(&context->call, "the component has no callable export");
        return 0;
    }
    context->reference = luaL_ref(state, LUA_REGISTRYINDEX);
    return 0;
}

static int release_reference(lua_State *state) {
    ReferenceCall *context = (ReferenceCall *)lua_touserdata(state, 1);
    luaL_unref(state, LUA_REGISTRYINDEX, context->reference);
    return 0;
}

static void push_value(lua_State *state, const NuppLuaValue *value) {
    switch (value->kind) {
        case 0: lua_pushnil(state); break;
        case 1: lua_pushboolean(state, value->boolean != 0); break;
        case 2: lua_pushnumber(state, value->number); break;
        case 3:
        case 4: lua_pushlstring(state, value->data, value->length); break;
        default: lua_rawgeti(state, LUA_REGISTRYINDEX, value->reference); break;
    }
}

static int call_values(lua_State *state) {
    ValuesCall *context = (ValuesCall *)lua_touserdata(state, 1);
    size_t index;
    int base = lua_gettop(state);
    int top;
    int table;
    int status;

    lua_rawgeti(state, LUA_REGISTRYINDEX, context->callable);
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        fail_call(&context->call, "the managed handle is not callable");
        return 0;
    }
    for (index = 0; index < context->argument_count; ++index) {
        push_value(state, &context->arguments[index]);
    }
    status = lua_pcall(state, (int)context->argument_count, LUA_MULTRET, 0);
    if (status != 0) {
        capture_error(state, &context->call, status);
        return 0;
    }
    top = lua_gettop(state);
    context->result_count = (size_t)(top - base);
    lua_createtable(state, (int)context->result_count, 0);
    table = lua_gettop(state);
    for (index = 0; index < context->result_count; ++index) {
        lua_pushvalue(state, base + 1 + (int)index);
        lua_rawseti(state, table, (int)index + 1);
    }
    context->results = luaL_ref(state, LUA_REGISTRYINDEX);
    return 0;
}

static int result_info(lua_State *state) {
    ResultCall *context = (ResultCall *)lua_touserdata(state, 1);
    int kind;
    lua_rawgeti(state, LUA_REGISTRYINDEX, context->results);
    lua_rawgeti(state, -1, (int)context->index + 1);
    kind = lua_type(state, -1);
    memset(&context->value, 0, sizeof context->value);
    switch (kind) {
        case LUA_TNIL: context->value.kind = 0; break;
        case LUA_TBOOLEAN:
            context->value.kind = 1;
            context->value.boolean = lua_toboolean(state, -1) != 0;
            break;
        case LUA_TNUMBER:
            context->value.kind = 2;
            context->value.number = lua_tonumber(state, -1);
            break;
        case LUA_TSTRING:
            context->value.kind = 4;
            lua_tolstring(state, -1, &context->value.length);
            break;
        default: context->value.kind = 5; break;
    }
    return 0;
}

static int take_result(lua_State *state) {
    ResultCall *context = (ResultCall *)lua_touserdata(state, 1);
    size_t length = 0;
    const char *text;
    lua_rawgeti(state, LUA_REGISTRYINDEX, context->results);
    lua_rawgeti(state, -1, (int)context->index + 1);
    if (context->value.kind == 4) {
        text = lua_tolstring(state, -1, &length);
        if (text == NULL || length > context->capacity) {
            fail_call(&context->call, "the managed result buffer is too small");
            return 0;
        }
        if (length != 0) memcpy(context->data, text, length);
        context->value.length = length;
    } else if (context->value.kind == 5) {
        lua_pushvalue(state, -1);
        context->value.reference = luaL_ref(state, LUA_REGISTRYINDEX);
    }
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

int nupp_lua_verify_compatibility(lua_State *state, char *error,
    size_t error_capacity) {
    ProtectedCall call = {error, error_capacity, 0};
    return protect(state, verify_compatibility, &call);
}

int nupp_lua_add_feature(lua_State *state, const char *name, char *error,
    size_t error_capacity) {
    FeatureCall context = {{error, error_capacity, 0}, name};
    return protect(state, add_feature, &context.call);
}

int nupp_lua_add_resource(lua_State *state, const char *path,
    const char *data, size_t length, char *error, size_t error_capacity) {
    ResourceCall context = {{error, error_capacity, 0}, path, data, length};
    return protect(state, add_resource, &context.call);
}

int nupp_lua_install_component(lua_State *state, const char *chunk,
    size_t chunk_length, const char *name, int *reference, char *error,
    size_t error_capacity) {
    ComponentCall context = {
        {error, error_capacity, 0}, chunk, chunk_length, name, 0
    };
    int status = protect(state, install_component, &context.call);
    if (status == 0) *reference = context.reference;
    return status;
}

int nupp_lua_start_component(lua_State *state, int reference,
    const NuppLuaBytes *arguments, size_t count, char *error,
    size_t error_capacity) {
    ComponentStartCall context = {
        {error, error_capacity, 0}, reference, arguments, count
    };
    if (count > INT_MAX) {
        fail_call(&context.call, "too many component arguments");
        return LUA_ERRRUN;
    }
    return protect(state, start_component, &context.call);
}

int nupp_lua_find_export(lua_State *state, int component, const char *name,
    int *reference, char *error, size_t error_capacity) {
    ExportCall context = {
        {error, error_capacity, 0}, component, name, 0
    };
    int status = protect(state, find_export, &context.call);
    if (status == 0) *reference = context.reference;
    return status;
}

int nupp_lua_release_reference(lua_State *state, int reference, char *error,
    size_t error_capacity) {
    ReferenceCall context = {{error, error_capacity, 0}, reference};
    return protect(state, release_reference, &context.call);
}

int nupp_lua_call(lua_State *state, int callable,
    const NuppLuaValue *arguments, size_t argument_count, int *results,
    size_t *result_count, char *error, size_t error_capacity) {
    ValuesCall context = {
        {error, error_capacity, 0}, callable, arguments, argument_count, 0, 0
    };
    int status;
    if (argument_count > INT_MAX) {
        fail_call(&context.call, "too many managed call arguments");
        return LUA_ERRRUN;
    }
    status = protect(state, call_values, &context.call);
    if (status == 0) {
        *results = context.results;
        *result_count = context.result_count;
    }
    return status;
}

int nupp_lua_result_info(lua_State *state, int results, size_t index,
    NuppLuaValue *value, char *error, size_t error_capacity) {
    ResultCall context = {
        {error, error_capacity, 0}, results, index, NULL, 0, {0}
    };
    int status = protect(state, result_info, &context.call);
    if (status == 0) *value = context.value;
    return status;
}

int nupp_lua_take_result(lua_State *state, int results, size_t index,
    char *data, size_t capacity, NuppLuaValue *value, char *error,
    size_t error_capacity) {
    ResultCall context = {
        {error, error_capacity, 0}, results, index, data, capacity, *value
    };
    int status = protect(state, take_result, &context.call);
    if (status == 0) *value = context.value;
    return status;
}
