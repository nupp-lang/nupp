#include <stdint.h>
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "nupp_memory.h"

#define LAST_ERROR_SIZE 1024

static lua_State *app_state;
static char last_error[LAST_ERROR_SIZE];

static void set_lua_error(const char *operation) {
    const char *message = lua_tostring(app_state, -1);
    snprintf(last_error, sizeof(last_error), "%s: %s", operation,
        message == NULL ? "Lua raised a non-string error" : message);
    lua_pop(app_state, 1);
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

int32_t nupp_app_run(const uint8_t *source, uint32_t length) {
    if (app_state == NULL) {
        snprintf(last_error, sizeof(last_error), "the app host is not booted");
        return -1;
    }
    if (luaL_loadbuffer(app_state, (const char *)source, length, "@nupp-app.lua") != 0) {
        set_lua_error("loading the app");
        return -2;
    }
    if (lua_pcall(app_state, 0, 0, 0) != 0) {
        set_lua_error("running the app");
        return -3;
    }
    return 0;
}

const char *nupp_app_last_error(void) {
    return last_error;
}
