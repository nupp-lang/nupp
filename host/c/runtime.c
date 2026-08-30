/* The reusable Nupp runtime.
 *
 * The standalone stub and an embedding application use this same state,
 * feature, payload and error boundary. Process arguments, payload discovery,
 * terminal output and exit status remain policies of the standalone binary.
 *
 * Calls are thread-affine. An owned runtime closes its LuaJIT state during
 * shutdown; an attached runtime removes its Nupp roots and leaves the state
 * open for its host.
 */

#include "nupp_host.h"

#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* LuaJIT's own `jit.vmdef`, compiled in beside the interpreter. A host that
 * carries an interpreter has to carry what its `jit` library reads, because
 * there is no directory beside a single-file program to find it in. */
extern const unsigned char nupp_host_vmdef[];
extern const unsigned int nupp_host_vmdef_length;
extern const unsigned char nupp_host_zone[];
extern const unsigned int nupp_host_zone_length;

#if NUPP_FEATURE_LPEG
extern int luaopen_lpeg(lua_State *state);
#endif
#if NUPP_FEATURE_LUA_UTF8
extern int luaopen_utf8(lua_State *state);
#endif

/* --- the runtime -------------------------------------------------------- */

typedef struct {
    uint64_t id;
    int reference;
    bool started;
} Component;

typedef struct {
    uint64_t id;
    int reference;
} Handle;

struct nupp_runtime {
    lua_State *state;
    bool owned;
    bool closed;
    pthread_t owner;
    uint64_t id;

    Component *components;
    size_t componentCount;
    size_t componentCapacity;
    uint64_t nextComponent;

    Handle *handles;
    size_t handleCount;
    size_t handleCapacity;
    uint64_t nextHandle;

    /* Features, modules and resources describe the host a component is loaded
     * into, so they stop being answerable once one has been. */
    bool frozen;
};

/* Worker threads create runtimes of their own, so the counter is guarded: two
 * runtimes sharing an id would defeat the cross-runtime handle check. */
static uint64_t nextRuntimeId = 1;
static pthread_mutex_t runtimeIdGuard = PTHREAD_MUTEX_INITIALIZER;

static uint64_t claim_runtime_id(void) {
    uint64_t id;
    pthread_mutex_lock(&runtimeIdGuard);
    id = nextRuntimeId++;
    pthread_mutex_unlock(&runtimeIdGuard);
    return id;
}

static char *say(const char *format, ...) {
    char scratch[512];
    va_list arguments;
    char *copy;
    va_start(arguments, format);
    vsnprintf(scratch, sizeof scratch, format, arguments);
    va_end(arguments);
    copy = malloc(strlen(scratch) + 1);
    if (copy != NULL) {
        strcpy(copy, scratch);
    }
    return copy;
}

/* Whatever Lua said, taken off the stack. It is already the most useful thing
 * anybody could print. */
static char *take_error(lua_State *state) {
    size_t length = 0;
    const char *text = lua_tolstring(state, -1, &length);
    char *copy;
    if (text == NULL) {
        lua_settop(state, -2);
        return say("unknown error");
    }
    copy = malloc(length + 1);
    if (copy != NULL) {
        memcpy(copy, text, length);
        copy[length] = '\0';
    }
    lua_settop(state, -2);
    return copy;
}

static char *check_thread(NuppRuntime *runtime) {
    if (!pthread_equal(pthread_self(), runtime->owner)) {
        return say("the Nupp runtime was called from a different thread");
    }
    if (runtime->closed || runtime->state == NULL) {
        return say("the Nupp runtime has shut down");
    }
    return NULL;
}

/* --- the host record ---------------------------------------------------- */

/* One entry in the feature table, recorded when the host was built with it.
 * The condition is an argument rather than a guard around the call because
 * every name here is a literal: nothing is being compiled out, only skipped,
 * and the call sites read as the list they are. */
static void set_flag(lua_State *state, const char *name, bool present) {
    if (!present) {
        return;
    }
    lua_pushboolean(state, 1);
    lua_setfield(state, -2, name);
}

/* The private payload and host handshake, published before any payload code
 * runs. The keys are wire names shared with the compiler. */
static void install_host_record(lua_State *state) {
    lua_createtable(state, 0, 3);
    lua_pushinteger(state, 1);
    lua_setfield(state, -2, "hostAbi");
    lua_createtable(state, 0, 8);
    set_flag(state, "lpeg", NUPP_FEATURE_LPEG);
    set_flag(state, "lua-utf8", NUPP_FEATURE_LUA_UTF8);
    set_flag(state, "native-files", NUPP_FEATURE_NATIVE_FILES);
    set_flag(state, "native-net", NUPP_FEATURE_NATIVE_NET);
    set_flag(state, "native-tls", NUPP_FEATURE_NATIVE_TLS);
    set_flag(state, "native-process", NUPP_FEATURE_NATIVE_PROCESS);
    set_flag(state, "workers", NUPP_FEATURE_WORKERS);
    lua_setfield(state, -2, "hostFeatures");
    lua_createtable(state, 0, 0);
    lua_setfield(state, -2, "resources");
    lua_setfield(state, LUA_GLOBALSINDEX, "__nuppHost");
}

/* Puts a C module in `package.preload`, so `require` finds it without a search
 * path and without a shared library on disk. */
static void preload_opener(lua_State *state, const char *name, lua_CFunction opener) {
    lua_getfield(state, LUA_GLOBALSINDEX, "package");
    lua_getfield(state, -1, "preload");
    lua_pushcclosure(state, opener, 0);
    lua_setfield(state, -2, name);
    lua_settop(state, -3);
}

static char *preload_lua(lua_State *state, const char *name, const unsigned char *source,
    size_t length) {
    char chunkName[128];
    snprintf(chunkName, sizeof chunkName, "@embedded/%s.lua", name);
    if (luaL_loadbuffer(state, (const char *)source, length, chunkName) != 0) {
        return take_error(state);
    }
    lua_getfield(state, LUA_GLOBALSINDEX, "package");
    lua_getfield(state, -1, "preload");
    lua_pushvalue(state, -3);
    lua_setfield(state, -2, name);
    lua_settop(state, -4);
    return NULL;
}

static void open_libraries(lua_State *state) {
    luaL_openlibs(state);
    free(preload_lua(state, "jit.vmdef", nupp_host_vmdef, nupp_host_vmdef_length));
    /* `nupp.profile.zone` requires this outright, and a stamped binary has no
     * directory beside it to find the interpreter's own copy in. */
    free(preload_lua(state, "jit.zone", nupp_host_zone, nupp_host_zone_length));
#if NUPP_FEATURE_LPEG
    preload_opener(state, "lpeg", luaopen_lpeg);
#endif
    /* Under the name luautf8 installs it as, since that is the name lunamark
     * asks for; LuaJIT has no utf8 of its own to collide with. */
#if NUPP_FEATURE_LUA_UTF8
    preload_opener(state, "lua-utf8", luaopen_utf8);
#endif
#if NUPP_FEATURE_WORKERS
    preload_opener(state, "nupp.workers.native", nupp_host_workers_open);
    preload_opener(state, "nupp.mem.sharedbytes.native", nupp_host_sharedbytes_open);
#endif
}

/* --- creating ----------------------------------------------------------- */

static NuppRuntime *make(lua_State *state, bool owned) {
    NuppRuntime *runtime = calloc(1, sizeof *runtime);
    if (runtime == NULL) {
        return NULL;
    }
    runtime->state = state;
    runtime->owned = owned;
    runtime->owner = pthread_self();
    runtime->id = claim_runtime_id();
    runtime->nextComponent = 1;
    runtime->nextHandle = 1;
    return runtime;
}

NuppRuntime *nupp_host_runtime_new(bool openLibraries, char **problem) {
    lua_State *state = luaL_newstate();
    NuppRuntime *runtime;
    *problem = NULL;
    if (state == NULL) {
        *problem = say("cannot create a LuaJIT state");
        return NULL;
    }
    if (openLibraries) {
        open_libraries(state);
    }
    install_host_record(state);
    runtime = make(state, true);
    if (runtime == NULL) {
        lua_close(state);
        *problem = say("out of memory");
    }
    return runtime;
}

/* Generated Nupp is written in the LuaJIT 3.0 syntax that 2.1 backported, so an
 * attached state older than that cannot load what it is about to be handed. */
static char *verify_compatibility(lua_State *state) {
    static const char *CHECK =
        "local major,minor,build=tostring(jit and jit.version or '')"
        ":match('^LuaJIT (%d+)%.(%d+)%.(%d+)$'); "
        "major,minor,build=tonumber(major),tonumber(minor),tonumber(build); "
        "assert(major and (major>2 or (major==2 and (minor>1 or "
        "(minor==1 and build>=1784535649)))), "
        "'nupp: attached state requires LuaJIT 2.1.1784535649 or newer')";
    if (luaL_loadbuffer(state, CHECK, strlen(CHECK), "=nupp-compatibility") != 0) {
        return take_error(state);
    }
    if (lua_pcall(state, 0, 0, 0) != 0) {
        return take_error(state);
    }
    return NULL;
}

NuppRuntime *nupp_host_runtime_attach(lua_State *state, bool openLibraries, char **problem) {
    NuppRuntime *runtime;
    *problem = NULL;
    if (state == NULL) {
        *problem = say("cannot attach to a null LuaJIT state");
        return NULL;
    }
    if (openLibraries) {
        open_libraries(state);
    }
    *problem = verify_compatibility(state);
    if (*problem != NULL) {
        return NULL;
    }
    install_host_record(state);
    runtime = make(state, false);
    if (runtime == NULL) {
        *problem = say("out of memory");
    }
    return runtime;
}

lua_State *nupp_host_runtime_state(NuppRuntime *runtime) {
    if (runtime == NULL || !pthread_equal(pthread_self(), runtime->owner)) {
        return NULL;
    }
    return runtime->closed ? NULL : runtime->state;
}

uint64_t nupp_host_runtime_id(const NuppRuntime *runtime) {
    return runtime != NULL ? runtime->id : 0;
}

/* --- running ------------------------------------------------------------ */

char *nupp_host_run(
    NuppRuntime *runtime, const uint8_t *chunk, size_t length, const char *name
) {
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    if (luaL_loadbuffer(runtime->state, (const char *)chunk, length, name) != 0) {
        return take_error(runtime->state);
    }
    if (lua_pcall(runtime->state, 0, 0, 0) != 0) {
        return take_error(runtime->state);
    }
    return NULL;
}

/* Sets the global `arg` the way a standalone interpreter does: the script's own
 * arguments from 1 upward. A program reading `arg` should not be able to tell
 * whether it was run from a bundle or from a file. */
static void set_arg(lua_State *state, int count, const char *const *arguments) {
    int index;
    lua_createtable(state, count, 0);
    for (index = 0; index < count; index++) {
        lua_pushstring(state, arguments[index]);
        lua_rawseti(state, -2, index + 1);
    }
    lua_setfield(state, LUA_GLOBALSINDEX, "arg");
}

char *nupp_host_set_arguments(
    NuppRuntime *runtime, int count, const char *const *arguments
) {
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    set_arg(runtime->state, count, arguments);
    return NULL;
}

/* --- describing the host ------------------------------------------------ */

char *nupp_host_add_feature(NuppRuntime *runtime, const char *feature) {
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    if (runtime->frozen) {
        return say("Nupp host features freeze when the first component loads");
    }
    lua_getfield(runtime->state, LUA_GLOBALSINDEX, "__nuppHost");
    lua_getfield(runtime->state, -1, "hostFeatures");
    lua_pushboolean(runtime->state, 1);
    lua_setfield(runtime->state, -2, feature);
    lua_settop(runtime->state, -3);
    return NULL;
}

char *nupp_host_add_resource(
    NuppRuntime *runtime, const char *path, const void *bytes, size_t length
) {
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    if (runtime->frozen) {
        return say("Nupp host resources freeze when the first component loads");
    }
    lua_getfield(runtime->state, LUA_GLOBALSINDEX, "__nuppHost");
    lua_getfield(runtime->state, -1, "resources");
    lua_pushlstring(runtime->state, (const char *)bytes, length);
    lua_setfield(runtime->state, -2, path);
    lua_settop(runtime->state, -3);
    return NULL;
}

char *nupp_host_preload(NuppRuntime *runtime, const char *module, lua_CFunction opener) {
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    if (runtime->frozen) {
        return say("Nupp host modules freeze when the first component loads");
    }
    preload_opener(runtime->state, module, opener);
    return NULL;
}

/* --- components --------------------------------------------------------- */

static Component *find_component(NuppRuntime *runtime, uint64_t id) {
    size_t at;
    for (at = 0; at < runtime->componentCount; at++) {
        if (runtime->components[at].id == id) {
            return &runtime->components[at];
        }
    }
    return NULL;
}

static Handle *find_handle(NuppRuntime *runtime, uint64_t id) {
    size_t at;
    for (at = 0; at < runtime->handleCount; at++) {
        if (runtime->handles[at].id == id) {
            return &runtime->handles[at];
        }
    }
    return NULL;
}

static uint64_t remember_handle(NuppRuntime *runtime, int reference) {
    if (runtime->handleCount == runtime->handleCapacity) {
        size_t next = runtime->handleCapacity < 8 ? 8 : runtime->handleCapacity * 2;
        Handle *grown = realloc(runtime->handles, next * sizeof *grown);
        if (grown == NULL) {
            return 0;
        }
        runtime->handles = grown;
        runtime->handleCapacity = next;
    }
    runtime->handles[runtime->handleCount].id = runtime->nextHandle;
    runtime->handles[runtime->handleCount].reference = reference;
    runtime->handleCount++;
    return runtime->nextHandle++;
}

/* Evaluates a compiler-produced component descriptor, then invokes its
 * installer and roots the inert component table it returns. Module top levels
 * remain behind `package.preload` until start or an export call. */
char *nupp_host_load_component(
    NuppRuntime *runtime, const uint8_t *bytes, size_t length, const char *name,
    uint64_t *component
) {
    static const char *MAGIC = "-- NUPP-COMPONENT 1\n";
    lua_State *state;
    lua_Integer format, hostAbi;
    int installed;
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    state = runtime->state;
    if (length < strlen(MAGIC) || memcmp(bytes, MAGIC, strlen(MAGIC)) != 0) {
        return say("not a Nupp component artifact (expected component format 1)");
    }
    if (luaL_loadbuffer(state, (const char *)bytes, length, name) != 0) {
        return take_error(state);
    }
    if (lua_pcall(state, 0, 1, 0) != 0) {
        return take_error(state);
    }
    if (lua_type(state, -1) != LUA_TTABLE) {
        lua_settop(state, -2);
        return say("a Nupp component descriptor did not return a table");
    }
    lua_getfield(state, -1, "format");
    format = lua_tointeger(state, -1);
    lua_settop(state, -2);
    if (format != 1) {
        lua_settop(state, -2);
        return say("unsupported Nupp component format %d", (int)format);
    }
    lua_getfield(state, -1, "hostAbi");
    hostAbi = lua_tointeger(state, -1);
    lua_settop(state, -2);
    if (hostAbi != 1) {
        lua_settop(state, -2);
        return say(
            "Nupp component requires compiler host ABI %d, but this runtime provides ABI 1",
            (int)hostAbi);
    }
    lua_getfield(state, -1, "install");
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        lua_settop(state, -3);
        return say("a Nupp component descriptor has no installer");
    }
    if (lua_pcall(state, 0, 1, 0) != 0) {
        char *error = take_error(state);
        lua_settop(state, -2);
        return error;
    }
    if (lua_type(state, -1) != LUA_TTABLE) {
        lua_settop(state, -3);
        return say("a Nupp component installer did not return a table");
    }
    installed = luaL_ref(state, LUA_REGISTRYINDEX);
    lua_settop(state, -2);

    if (runtime->componentCount == runtime->componentCapacity) {
        size_t next = runtime->componentCapacity < 4 ? 4 : runtime->componentCapacity * 2;
        Component *grown = realloc(runtime->components, next * sizeof *grown);
        if (grown == NULL) {
            luaL_unref(state, LUA_REGISTRYINDEX, installed);
            return say("out of memory");
        }
        runtime->components = grown;
        runtime->componentCapacity = next;
    }
    runtime->components[runtime->componentCount].id = runtime->nextComponent;
    runtime->components[runtime->componentCount].reference = installed;
    runtime->components[runtime->componentCount].started = false;
    runtime->componentCount++;
    *component = runtime->nextComponent++;
    runtime->frozen = true;
    return NULL;
}

char *nupp_host_start_component(
    NuppRuntime *runtime, uint64_t id, int count, const char *const *arguments
) {
    lua_State *state;
    Component *component;
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    state = runtime->state;
    component = find_component(runtime, id);
    if (component == NULL) {
        return say("the component is not loaded in this Nupp runtime");
    }
    if (component->started) {
        return say("the component has already started");
    }
    component->started = true;
    set_arg(state, count, arguments);
    lua_rawgeti(state, LUA_REGISTRYINDEX, component->reference);
    lua_getfield(state, -1, "start");
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        lua_settop(state, -3);
        return say("the component has no callable start");
    }
    if (lua_pcall(state, 0, 0, 0) != 0) {
        char *error = take_error(state);
        lua_settop(state, -2);
        return error;
    }
    lua_settop(state, -2);
    return NULL;
}

char *nupp_host_find_export(
    NuppRuntime *runtime, uint64_t id, const char *name, uint64_t *handle
) {
    lua_State *state;
    Component *component;
    int rooted;
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    state = runtime->state;
    component = find_component(runtime, id);
    if (component == NULL) {
        return say("the component is not loaded in this Nupp runtime");
    }
    lua_rawgeti(state, LUA_REGISTRYINDEX, component->reference);
    lua_getfield(state, -1, "exports");
    if (lua_type(state, -1) != LUA_TTABLE) {
        lua_settop(state, -3);
        return say("the component has no export table");
    }
    lua_getfield(state, -1, name);
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        lua_settop(state, -4);
        return say("the component has no callable export \"%s\"", name);
    }
    rooted = luaL_ref(state, LUA_REGISTRYINDEX);
    lua_settop(state, -3);
    *handle = remember_handle(runtime, rooted);
    if (*handle == 0) {
        luaL_unref(state, LUA_REGISTRYINDEX, rooted);
        return say("out of memory");
    }
    return NULL;
}

/* --- calling ------------------------------------------------------------ */

/* Takes back results marshalled before a later one failed: their copied bytes,
 * their registry roots, and the array itself, so an error returns nothing the
 * caller would have to guess at freeing. */
static void discard_results(NuppRuntime *runtime, NuppHostValue *values, size_t count) {
    size_t at;
    for (at = 0; at < count; at++) {
        free(values[at].data);
        if (values[at].kind == NUPP_HOST_HANDLE && values[at].handle != 0) {
            free(nupp_host_release_handle(runtime, values[at].handle));
        }
    }
    free(values);
}

char *nupp_host_call(
    NuppRuntime *runtime, uint64_t callable,
    const NuppHostValue *arguments, size_t argumentCount,
    NuppHostValue **results, size_t *resultCount
) {
    lua_State *state;
    Handle *handle;
    int base, top, index;
    size_t at;
    char *problem = check_thread(runtime);

    *results = NULL;
    *resultCount = 0;
    if (problem != NULL) {
        return problem;
    }
    state = runtime->state;
    handle = find_handle(runtime, callable);
    if (handle == NULL) {
        return say("the managed handle has been released");
    }
    base = lua_gettop(state);
    lua_rawgeti(state, LUA_REGISTRYINDEX, handle->reference);
    if (lua_type(state, -1) != LUA_TFUNCTION) {
        lua_settop(state, base);
        return say("the managed handle is not callable");
    }
    for (at = 0; at < argumentCount; at++) {
        const NuppHostValue *value = &arguments[at];
        switch (value->kind) {
            case NUPP_HOST_NIL: lua_pushnil(state); break;
            case NUPP_HOST_BOOLEAN: lua_pushboolean(state, value->boolean ? 1 : 0); break;
            case NUPP_HOST_NUMBER: lua_pushnumber(state, value->number); break;
            case NUPP_HOST_STRING:
            case NUPP_HOST_BYTES:
                lua_pushlstring(state, (const char *)value->data, value->length);
                break;
            default: {
                Handle *passed = find_handle(runtime, value->handle);
                if (passed == NULL) {
                    lua_settop(state, base);
                    return say("the managed handle has been released");
                }
                lua_rawgeti(state, LUA_REGISTRYINDEX, passed->reference);
                break;
            }
        }
    }
    if (lua_pcall(state, (int)argumentCount, LUA_MULTRET, 0) != 0) {
        char *error = take_error(state);
        lua_settop(state, base);
        return error;
    }
    top = lua_gettop(state);
    if (top > base) {
        *results = calloc((size_t)(top - base), sizeof **results);
        if (*results == NULL) {
            lua_settop(state, base);
            return say("out of memory");
        }
    }
    for (index = base + 1; index <= top; index++) {
        NuppHostValue *value = &(*results)[index - base - 1];
        switch (lua_type(state, index)) {
            case LUA_TNIL: value->kind = NUPP_HOST_NIL; break;
            case LUA_TBOOLEAN:
                value->kind = NUPP_HOST_BOOLEAN;
                value->boolean = lua_toboolean(state, index) != 0;
                break;
            case LUA_TNUMBER:
                value->kind = NUPP_HOST_NUMBER;
                value->number = lua_tonumber(state, index);
                break;
            case LUA_TSTRING: {
                size_t length = 0;
                const char *text = lua_tolstring(state, index, &length);
                value->kind = NUPP_HOST_BYTES;
                value->data = malloc(length + 1);
                if (value->data == NULL) {
                    discard_results(runtime, *results, (size_t)(index - base - 1));
                    *results = NULL;
                    lua_settop(state, base);
                    return say("out of memory");
                }
                memcpy(value->data, text, length);
                value->data[length] = 0;
                value->length = length;
                break;
            }
            default: {
                /* Anything the host cannot copy stays in the runtime and is
                 * named by a handle, rooted until the caller releases it. */
                int rooted;
                lua_pushvalue(state, index);
                rooted = luaL_ref(state, LUA_REGISTRYINDEX);
                value->kind = NUPP_HOST_HANDLE;
                value->handle = remember_handle(runtime, rooted);
                if (value->handle == 0) {
                    luaL_unref(state, LUA_REGISTRYINDEX, rooted);
                    discard_results(runtime, *results, (size_t)(index - base - 1));
                    *results = NULL;
                    lua_settop(state, base);
                    return say("out of memory");
                }
                break;
            }
        }
    }
    *resultCount = (size_t)(top - base);
    lua_settop(state, base);
    return NULL;
}

char *nupp_host_release_handle(NuppRuntime *runtime, uint64_t id) {
    Handle *handle;
    char *problem = check_thread(runtime);
    if (problem != NULL) {
        return problem;
    }
    handle = find_handle(runtime, id);
    if (handle == NULL) {
        return say("the managed handle has already been released");
    }
    luaL_unref(runtime->state, LUA_REGISTRYINDEX, handle->reference);
    *handle = runtime->handles[--runtime->handleCount];
    return NULL;
}

/* An explicit host boundary. Scheduler providers may add work here; the core
 * uses it for lifecycle and thread-affinity validation. */
char *nupp_host_poll(NuppRuntime *runtime) {
    return check_thread(runtime);
}

/* --- ending ------------------------------------------------------------- */

char *nupp_host_runtime_shutdown(NuppRuntime *runtime) {
    size_t at;
    if (runtime == NULL) {
        return NULL;
    }
    if (!pthread_equal(pthread_self(), runtime->owner)) {
        return say("the Nupp runtime was called from a different thread");
    }
    if (runtime->closed || runtime->state == NULL) {
        return NULL;
    }
    for (at = 0; at < runtime->componentCount; at++) {
        luaL_unref(runtime->state, LUA_REGISTRYINDEX, runtime->components[at].reference);
    }
    for (at = 0; at < runtime->handleCount; at++) {
        luaL_unref(runtime->state, LUA_REGISTRYINDEX, runtime->handles[at].reference);
    }
    runtime->componentCount = 0;
    runtime->handleCount = 0;
    if (runtime->owned) {
        lua_close(runtime->state);
    }
    runtime->state = NULL;
    runtime->closed = true;
    return NULL;
}

void nupp_host_runtime_free(NuppRuntime *runtime) {
    if (runtime == NULL) {
        return;
    }
    /* A wrong-thread free cannot report anything, and entering LuaJIT from a
     * thread that does not own it is worse than leaking the state. An explicit
     * shutdown is where that mistake is reported. */
    if (pthread_equal(pthread_self(), runtime->owner)) {
        free(nupp_host_runtime_shutdown(runtime));
    }
    free(runtime->components);
    free(runtime->handles);
    free(runtime);
}
