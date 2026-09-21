#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <emscripten/emscripten.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "nupp_memory.h"

/* LPeg is compiled into this host rather than loaded from a file. Declared here
 * because LPeg's headers are its own internals; the opener is the whole of the
 * surface a host needs. */
int luaopen_lpeg(lua_State *state);

#define LAST_ERROR_SIZE 1024

enum {
    NUPP_APP_IDLE = 0,
    NUPP_APP_SUSPENDED = 1,
    NUPP_APP_COMPLETE = 2,
    NUPP_APP_FAILED = 3,
    NUPP_APP_CANCELLED = 4
};

static lua_State *app_state;
static lua_State *app_thread;
static int app_thread_ref = LUA_NOREF;
static int32_t app_status = NUPP_APP_IDLE;
static const char *app_payload;
static size_t app_payload_size;
static char last_error[LAST_ERROR_SIZE];

EM_JS(int, browser_files_available, (), {
    return Module.__nuppFiles?.available ? 1 : 0;
});

EM_JS(int, browser_files_persistent_available, (), {
    return Module.__nuppFiles?.persistentAvailable ? 1 : 0;
});

EM_JS(int, browser_files_read, (uint32_t handle, uintptr_t pointer, uint32_t count), {
    try {
        const entry = Module.__nuppFiles?.handles?.get(handle);
        if (!entry) throw new Error("file handle is closed");
        if (!entry.readable) throw new Error("file is not open for reading");
        const output = Module.HEAPU8.subarray(pointer, pointer + count);
        const read = entry.access.read(output, {at: entry.cursor});
        entry.cursor += read;
        return read;
    } catch (error) {
        if (Module.__nuppFiles) Module.__nuppFiles.lastError = String(error?.message || error);
        return -1;
    }
});

EM_JS(int, browser_files_write, (uint32_t handle, uintptr_t pointer, uint32_t count), {
    try {
        const entry = Module.__nuppFiles?.handles?.get(handle);
        if (!entry) throw new Error("file handle is closed");
        if (!entry.writable) throw new Error("file is not open for writing");
        let written = 0;
        while (written < count) {
            const at = entry.appending ? entry.access.getSize() : entry.cursor;
            const input = Module.HEAPU8.subarray(pointer + written, pointer + count);
            const countWritten = entry.access.write(input, {at});
            if (!Number.isInteger(countWritten) || countWritten < 1) throw new Error("file write made no progress");
            written += countWritten;
            entry.cursor = at + countWritten;
        }
        return written;
    } catch (error) {
        if (Module.__nuppFiles) Module.__nuppFiles.lastError = String(error?.message || error);
        return -1;
    }
});

EM_JS(double, browser_files_size, (uint32_t handle), {
    try {
        const entry = Module.__nuppFiles?.handles?.get(handle);
        if (!entry) throw new Error("file handle is closed");
        return entry.access.getSize();
    } catch (error) {
        if (Module.__nuppFiles) Module.__nuppFiles.lastError = String(error?.message || error);
        return -1;
    }
});

EM_JS(double, browser_files_seek, (uint32_t handle, double offset, uint32_t origin), {
    try {
        const entry = Module.__nuppFiles?.handles?.get(handle);
        if (!entry) throw new Error("file handle is closed");
        const base = origin === 0 ? 0 : origin === 1 ? entry.cursor : origin === 2 ? entry.access.getSize() : NaN;
        if (!Number.isFinite(base) || !Number.isSafeInteger(offset)) throw new Error("invalid file seek");
        entry.cursor = Math.max(0, base + offset);
        return entry.cursor;
    } catch (error) {
        if (Module.__nuppFiles) Module.__nuppFiles.lastError = String(error?.message || error);
        return -1;
    }
});

EM_JS(int, browser_files_flush, (uint32_t handle), {
    try {
        const entry = Module.__nuppFiles?.handles?.get(handle);
        if (!entry) throw new Error("file handle is closed");
        entry.access.flush();
        return 1;
    } catch (error) {
        if (Module.__nuppFiles) Module.__nuppFiles.lastError = String(error?.message || error);
        return 0;
    }
});

EM_JS(int, browser_files_close, (uint32_t handle), {
    try {
        const files = Module.__nuppFiles;
        const entry = files?.handles?.get(handle);
        if (!entry) return 1;
        entry.access.close();
        files.handles.delete(handle);
        return 1;
    } catch (error) {
        if (Module.__nuppFiles) Module.__nuppFiles.lastError = String(error?.message || error);
        return 0;
    }
});

EM_JS(char *, browser_files_last_error, (), {
    const text = Module.__nuppFiles?.lastError || "browser file operation failed";
    const bytes = lengthBytesUTF8(text) + 1;
    const pointer = _malloc(bytes);
    stringToUTF8(text, pointer, bytes);
    return pointer;
});

static int files_failure(lua_State *state) {
    char *message = browser_files_last_error();
    lua_pushnil(state);
    lua_pushstring(state, message == NULL ? "browser file operation failed" : message);
    free(message);
    return 2;
}

static int files_available(lua_State *state) {
    lua_pushboolean(state, browser_files_available());
    return 1;
}

static int files_persistent_available(lua_State *state) {
    lua_pushboolean(state, browser_files_persistent_available());
    return 1;
}

static int files_read(lua_State *state) {
    uint32_t handle = (uint32_t)luaL_checknumber(state, 1);
    uint32_t count = (uint32_t)luaL_checknumber(state, 2);
    char *buffer = count == 0 ? NULL : (char *)malloc(count);
    int read;
    if (count != 0 && buffer == NULL) return luaL_error(state, "cannot allocate browser file read buffer");
    read = browser_files_read(handle, (uintptr_t)buffer, count);
    if (read < 0) { free(buffer); return files_failure(state); }
    lua_pushlstring(state, buffer == NULL ? "" : buffer, (size_t)read);
    free(buffer);
    lua_pushnil(state);
    return 2;
}

static int files_read_lease(lua_State *state) {
    uint32_t handle = (uint32_t)luaL_checknumber(state, 1);
    uint32_t lease = (uint32_t)luaL_checknumber(state, 2);
    uint32_t count = (uint32_t)luaL_checknumber(state, 3);
    uintptr_t address = nupp_wasm_lease_address(lease);
    if (address == 0 || !nupp_wasm_lease_writable(lease) || count > nupp_wasm_lease_size(lease))
        return luaL_error(state, "browser file read lease is invalid");
    int read = browser_files_read(handle, address, count);
    if (read < 0) return files_failure(state);
    lua_pushnumber(state, (lua_Number)read); lua_pushnil(state); return 2;
}

static int files_write(lua_State *state) {
    uint32_t handle = (uint32_t)luaL_checknumber(state, 1);
    size_t count;
    const char *bytes = luaL_checklstring(state, 2, &count);
    int written = browser_files_write(handle, (uintptr_t)bytes, (uint32_t)count);
    if (written < 0) return files_failure(state);
    lua_pushnumber(state, (lua_Number)written); lua_pushnil(state); return 2;
}

static int files_write_lease(lua_State *state) {
    uint32_t handle = (uint32_t)luaL_checknumber(state, 1);
    uint32_t lease = (uint32_t)luaL_checknumber(state, 2);
    uint32_t count = (uint32_t)luaL_checknumber(state, 3);
    uintptr_t address = nupp_wasm_lease_address(lease);
    if (address == 0 || count > nupp_wasm_lease_size(lease))
        return luaL_error(state, "browser file write lease is invalid");
    int written = browser_files_write(handle, address, count);
    if (written < 0) return files_failure(state);
    lua_pushnumber(state, (lua_Number)written); lua_pushnil(state); return 2;
}

static int files_size(lua_State *state) {
    double size = browser_files_size((uint32_t)luaL_checknumber(state, 1));
    if (size < 0) return files_failure(state);
    lua_pushnumber(state, size); lua_pushnil(state); return 2;
}

static int files_seek(lua_State *state) {
    double value = browser_files_seek((uint32_t)luaL_checknumber(state, 1), luaL_checknumber(state, 2),
        (uint32_t)luaL_checknumber(state, 3));
    if (value < 0) return files_failure(state);
    lua_pushnumber(state, value); lua_pushnil(state); return 2;
}

static int files_flush(lua_State *state) {
    if (!browser_files_flush((uint32_t)luaL_checknumber(state, 1))) return files_failure(state);
    lua_pushboolean(state, 1); lua_pushnil(state); return 2;
}

static int files_close(lua_State *state) {
    if (!browser_files_close((uint32_t)luaL_checknumber(state, 1))) return files_failure(state);
    lua_pushboolean(state, 1); lua_pushnil(state); return 2;
}

static const luaL_Reg files_functions[] = {
    {"available", files_available}, {"persistentAvailable", files_persistent_available},
    {"read", files_read}, {"readLease", files_read_lease},
    {"write", files_write}, {"writeLease", files_write_lease},
    {"size", files_size}, {"seek", files_seek}, {"flush", files_flush}, {"close", files_close},
    {NULL, NULL},
};

static void install_files(lua_State *state) {
    lua_newtable(state);
    luaL_register(state, NULL, files_functions);
    lua_setglobal(state, "__nuppWasmFilesHost");
}

/* Where the failure was, appended to the message it carried.
 *
 * A resumed coroutine keeps its stack when it fails, so the frames are still there
 * to walk. Without this a browser application reports what went wrong and nothing
 * about where, which for anything raised inside the runtime is most of the answer. */
static void append_traceback(lua_State *thread) {
    size_t used = strlen(last_error);
    lua_Debug frame;
    int level;

    for (level = 0; level < 12; level++) {
        int written;

        if (lua_getstack(thread, level, &frame) == 0) {
            return;
        }
        lua_getinfo(thread, "Sln", &frame);
        if (used + 2 >= sizeof(last_error)) {
            return;
        }
        written = snprintf(last_error + used, sizeof(last_error) - used,
            "\n  %s:%d%s%s", frame.short_src, frame.currentline,
            frame.name == NULL ? "" : " in ", frame.name == NULL ? "" : frame.name);
        if (written < 0 || (size_t)written >= sizeof(last_error) - used) {
            return;
        }
        used += (size_t)written;
    }
}

static void set_lua_error(lua_State *state, const char *operation) {
    const char *message = lua_tostring(state, -1);
    snprintf(last_error, sizeof(last_error), "%s: %s", operation,
        message == NULL ? "Lua raised a non-string error" : message);
    lua_pop(state, 1);
    append_traceback(state);
}

static void open_library(const char *name, lua_CFunction open) {
    lua_pushcfunction(app_state, open);
    lua_pushstring(app_state, name);
    lua_call(app_state, 1, 0);
}

/* A C module the application requires by name.
 *
 * There is no filesystem and no dynamic loader here, so a binary module cannot
 * arrive the way it does on a machine: it is linked into this host and handed to
 * `require` through `package.preload`. Preload rather than `package.loaded`, so a
 * program that never mentions it never pays for opening it. */
static void preload_library(const char *name, lua_CFunction open) {
    lua_getglobal(app_state, "package");
    lua_getfield(app_state, -1, "preload");
    lua_pushcfunction(app_state, open);
    lua_setfield(app_state, -2, name);
    lua_pop(app_state, 2);
}

uintptr_t nupp_app_boot(void) {
    if (app_state != NULL) {
        snprintf(last_error, sizeof(last_error), "the app host is already booted");
        return 0;
    }
    app_state = luaL_newstate();
    if (app_state == NULL) {
        snprintf(last_error, sizeof(last_error), "cannot allocate the Lua state");
        return 0;
    }
    open_library("", luaopen_base);
    open_library(LUA_LOADLIBNAME, luaopen_package);
    open_library(LUA_TABLIBNAME, luaopen_table);
    open_library(LUA_STRLIBNAME, luaopen_string);
    open_library(LUA_MATHLIBNAME, luaopen_math);
    preload_library("lpeg", luaopen_lpeg);
    nupp_wasm_install_memory(app_state);
    install_files(app_state);
    last_error[0] = '\0';
    return (uintptr_t)app_state;
}

int32_t nupp_app_initialize(const uint8_t *source, uint32_t length) {
    if (app_state == NULL) {
        snprintf(last_error, sizeof(last_error), "the app host is not booted");
        return 0;
    }
    if (app_status != NUPP_APP_IDLE) {
        snprintf(last_error, sizeof(last_error), "the app host already started an application");
        return 0;
    }
    if (luaL_loadbuffer(app_state, (const char *)source, length,
            "@nupp-app-runtime.lua") != 0) {
        set_lua_error(app_state, "loading the app runtime");
        return 0;
    }
    if (lua_pcall(app_state, 0, 0, 0) != 0) {
        set_lua_error(app_state, "initializing the app runtime");
        return 0;
    }
    last_error[0] = '\0';
    return 1;
}

static int32_t finish_resume(int code, const char *operation) {
    int values;

    app_payload = NULL;
    app_payload_size = 0;
    if (code == LUA_YIELD) {
        values = lua_gettop(app_thread);
        if (values != 1 || !lua_isstring(app_thread, -1)) {
            snprintf(last_error, sizeof(last_error),
                "%s yielded %d values; exactly one protocol string is required",
                operation, values);
            app_status = NUPP_APP_FAILED;
            nupp_wasm_release_all_leases();
            return app_status;
        }
        app_payload = lua_tolstring(app_thread, -1, &app_payload_size);
        app_status = NUPP_APP_SUSPENDED;
        return app_status;
    }
    if (code != 0) {
        set_lua_error(app_thread, operation);
        app_status = NUPP_APP_FAILED;
        nupp_wasm_release_all_leases();
        return app_status;
    }

    values = lua_gettop(app_thread);
    if (values > 1 || (values == 1 && !lua_isstring(app_thread, -1))) {
        snprintf(last_error, sizeof(last_error),
            "%s returned %d values; zero values or one structured-result string is required",
            operation, values);
        app_status = NUPP_APP_FAILED;
        nupp_wasm_release_all_leases();
        return app_status;
    }
    if (values == 1) {
        app_payload = lua_tolstring(app_thread, -1, &app_payload_size);
    }
    app_status = NUPP_APP_COMPLETE;
    nupp_wasm_release_all_leases();
    return app_status;
}

int32_t nupp_app_start(const uint8_t *source, uint32_t length) {
    if (app_state == NULL) {
        snprintf(last_error, sizeof(last_error), "the app host is not booted");
        return NUPP_APP_FAILED;
    }
    if (app_status != NUPP_APP_IDLE) {
        snprintf(last_error, sizeof(last_error), "the app host already started an application");
        return NUPP_APP_FAILED;
    }
    app_thread = lua_newthread(app_state);
    app_thread_ref = luaL_ref(app_state, LUA_REGISTRYINDEX);
    if (luaL_loadbuffer(app_thread, (const char *)source, length, "@nupp-app.lua") != 0) {
        set_lua_error(app_thread, "loading the app");
        app_status = NUPP_APP_FAILED;
        return app_status;
    }
    last_error[0] = '\0';
    return finish_resume(lua_resume(app_thread, 0), "running the app");
}

int32_t nupp_app_start_managed(const uint8_t *source, uint32_t length) {
    if (app_state == NULL) {
        snprintf(last_error, sizeof(last_error), "the app host is not booted");
        return NUPP_APP_FAILED;
    }
    if (app_status != NUPP_APP_IDLE) {
        snprintf(last_error, sizeof(last_error), "the app host already started an application");
        return NUPP_APP_FAILED;
    }
    app_thread = lua_newthread(app_state);
    app_thread_ref = luaL_ref(app_state, LUA_REGISTRYINDEX);
    lua_getglobal(app_thread, "__nuppPlaygroundRun");
    if (!lua_isfunction(app_thread, -1)) {
        lua_pop(app_thread, 1);
        snprintf(last_error, sizeof(last_error), "the managed app runner is not installed");
        app_status = NUPP_APP_FAILED;
        return app_status;
    }
    lua_pushlstring(app_thread, (const char *)source, length);
    last_error[0] = '\0';
    return finish_resume(lua_resume(app_thread, 1), "running the managed app");
}

int32_t nupp_app_resume(const uint8_t *data, uint32_t length) {
    if (app_status != NUPP_APP_SUSPENDED) {
        snprintf(last_error, sizeof(last_error), "the app is not suspended");
        return NUPP_APP_FAILED;
    }
    lua_settop(app_thread, 0);
    lua_pushlstring(app_thread, (const char *)data, length);
    return finish_resume(lua_resume(app_thread, 1), "resuming the app");
}

int32_t nupp_app_cancel(void) {
    static const char cancellation[] = "{\"cancelled\":true}";
    int32_t resumed;

    if (app_status != NUPP_APP_SUSPENDED) {
        snprintf(last_error, sizeof(last_error), "the app is not suspended");
        return NUPP_APP_FAILED;
    }
    lua_settop(app_thread, 0);
    lua_pushlstring(app_thread, cancellation, sizeof(cancellation) - 1);
    resumed = finish_resume(lua_resume(app_thread, 1), "cancelling the app");
    if (resumed == NUPP_APP_SUSPENDED) {
        snprintf(last_error, sizeof(last_error), "the app suspended again while cancellation was unwinding");
        app_status = NUPP_APP_FAILED;
        return app_status;
    }
    app_status = NUPP_APP_CANCELLED;
    nupp_wasm_release_all_leases();
    app_payload = NULL;
    app_payload_size = 0;
    return app_status;
}

int32_t nupp_app_status(void) {
    return app_status;
}

const uint8_t *nupp_app_payload_data(void) {
    return (const uint8_t *)app_payload;
}

uint32_t nupp_app_payload_size(void) {
    return (uint32_t)app_payload_size;
}

const char *nupp_app_last_error(void) {
    return last_error;
}
