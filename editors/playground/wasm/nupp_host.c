#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#ifndef NUPP_BUNDLE_SHA256
#error "NUPP_BUNDLE_SHA256 must name the tested compiler bundle digest"
#endif

#define RESPONSE_SLOTS 64
#define LAST_ERROR_SIZE 1024

struct response {
    uint8_t *data;
    uint32_t length;
};

static lua_State *nupp_state;
static int session_reference = LUA_NOREF;
static struct response responses[RESPONSE_SLOTS];
static char last_error[LAST_ERROR_SIZE];

static void clear_error(void) {
    last_error[0] = '\0';
}

static void set_error(const char *message) {
    snprintf(last_error, sizeof(last_error), "%s", message == NULL ? "unknown error" : message);
}

static void set_lua_error(lua_State *state, const char *operation) {
    const char *message = lua_tostring(state, -1);
    snprintf(last_error, sizeof(last_error), "%s: %s", operation,
        message == NULL ? "Lua raised a non-string error" : message);
    lua_pop(state, 1);
}

static void open_library(lua_State *state, const char *name, lua_CFunction open) {
    lua_pushcfunction(state, open);
    lua_pushstring(state, name);
    lua_call(state, 1, 0);
}

static void open_portable_libraries(lua_State *state) {
    open_library(state, "", luaopen_base);
    open_library(state, LUA_LOADLIBNAME, luaopen_package);
    open_library(state, LUA_TABLIBNAME, luaopen_table);
    open_library(state, LUA_STRLIBNAME, luaopen_string);
    open_library(state, LUA_MATHLIBNAME, luaopen_math);
}

/* The bundle's digest is checked by `src/wasm-runtime.js` before it calls
 * this, against the constant `nupp_bundle_sha256` publishes below. It used to
 * be checked here, over a SHA-256 carried in this host for that one call; the
 * caller is what decides which bytes arrive, so the check is no weaker for
 * being written where the bytes already are, and this host no longer carries a
 * digest implementation at all. */
int32_t nupp_boot(const uint8_t *bundle, uint32_t length) {
    lua_State *state;

    clear_error();
    if (nupp_state != NULL) {
        set_error("the compiler is already booted");
        return -1;
    }
    if (bundle == NULL || length == 0) {
        set_error("the compiler bundle is empty");
        return -2;
    }
    state = luaL_newstate();
    if (state == NULL) {
        set_error("cannot allocate the Lua state");
        return -4;
    }
    open_portable_libraries(state);
    if (luaL_loadbuffer(state, (const char *)bundle, length, "@nupp-compiler.lua") != 0) {
        set_lua_error(state, "loading the compiler bundle");
        lua_close(state);
        return -5;
    }
    if (lua_pcall(state, 0, 1, 0) != 0) {
        set_lua_error(state, "initializing the compiler bundle");
        lua_close(state);
        return -6;
    }
    if (!lua_istable(state, -1)) {
        set_error("the compiler bundle returned no browser API");
        lua_close(state);
        return -7;
    }
    lua_getfield(state, -1, "new");
    if (!lua_isfunction(state, -1)) {
        set_error("the browser API has no new function");
        lua_close(state);
        return -8;
    }
    if (lua_pcall(state, 0, 1, 0) != 0) {
        set_lua_error(state, "creating the browser compiler session");
        lua_close(state);
        return -9;
    }
    if (!lua_istable(state, -1)) {
        set_error("the browser API returned no session");
        lua_close(state);
        return -10;
    }
    session_reference = luaL_ref(state, LUA_REGISTRYINDEX);
    lua_pop(state, 1);
    nupp_state = state;
    return 0;
}

uint32_t nupp_request(const uint8_t *data, uint32_t length) {
    uint32_t slot;
    const char *text;
    size_t response_length;
    uint8_t *copy;

    clear_error();
    if (nupp_state == NULL || session_reference == LUA_NOREF) {
        set_error("the compiler is not booted");
        return 0;
    }
    if (data == NULL) {
        set_error("the request buffer is null");
        return 0;
    }
    for (slot = 0; slot < RESPONSE_SLOTS; ++slot) {
        if (responses[slot].data == NULL) {
            break;
        }
    }
    if (slot == RESPONSE_SLOTS) {
        set_error("too many live response handles");
        return 0;
    }

    lua_rawgeti(nupp_state, LUA_REGISTRYINDEX, session_reference);
    lua_getfield(nupp_state, -1, "request");
    if (!lua_isfunction(nupp_state, -1)) {
        lua_pop(nupp_state, 2);
        set_error("the browser session has no request method");
        return 0;
    }
    lua_pushvalue(nupp_state, -2);
    lua_pushlstring(nupp_state, (const char *)data, length);
    if (lua_pcall(nupp_state, 2, 1, 0) != 0) {
        set_lua_error(nupp_state, "handling the compiler request");
        lua_pop(nupp_state, 1);
        return 0;
    }
    text = lua_tolstring(nupp_state, -1, &response_length);
    if (text == NULL || response_length > UINT32_MAX) {
        lua_pop(nupp_state, 2);
        set_error("the browser session returned an invalid response");
        return 0;
    }
    copy = (uint8_t *)malloc(response_length == 0 ? 1 : response_length);
    if (copy == NULL) {
        lua_pop(nupp_state, 2);
        set_error("cannot allocate the compiler response");
        return 0;
    }
    if (response_length > 0) {
        memcpy(copy, text, response_length);
    }
    lua_pop(nupp_state, 2);
    responses[slot].data = copy;
    responses[slot].length = (uint32_t)response_length;
    return slot + 1;
}

const uint8_t *nupp_response_data(uint32_t handle) {
    if (handle == 0 || handle > RESPONSE_SLOTS) {
        return NULL;
    }
    return responses[handle - 1].data;
}

uint32_t nupp_response_size(uint32_t handle) {
    if (handle == 0 || handle > RESPONSE_SLOTS || responses[handle - 1].data == NULL) {
        return 0;
    }
    return responses[handle - 1].length;
}

void nupp_response_free(uint32_t handle) {
    if (handle == 0 || handle > RESPONSE_SLOTS) {
        return;
    }
    free(responses[handle - 1].data);
    responses[handle - 1].data = NULL;
    responses[handle - 1].length = 0;
}

const char *nupp_last_error(void) {
    return last_error;
}

const char *nupp_bundle_sha256(void) {
    return NUPP_BUNDLE_SHA256;
}
