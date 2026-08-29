#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "nupp_memory.h"

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
    nupp_wasm_install_memory(app_state);
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
            return app_status;
        }
        app_payload = lua_tolstring(app_thread, -1, &app_payload_size);
        app_status = NUPP_APP_SUSPENDED;
        return app_status;
    }
    if (code != 0) {
        set_lua_error(app_thread, operation);
        app_status = NUPP_APP_FAILED;
        return app_status;
    }

    values = lua_gettop(app_thread);
    if (values > 1 || (values == 1 && !lua_isstring(app_thread, -1))) {
        snprintf(last_error, sizeof(last_error),
            "%s returned %d values; zero values or one structured-result string is required",
            operation, values);
        app_status = NUPP_APP_FAILED;
        return app_status;
    }
    if (values == 1) {
        app_payload = lua_tolstring(app_thread, -1, &app_payload_size);
    }
    app_status = NUPP_APP_COMPLETE;
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
