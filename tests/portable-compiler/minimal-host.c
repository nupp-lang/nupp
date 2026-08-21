/*
 * A stock Lua 5.1 host for the portable compiler acceptance test.
 *
 * It deliberately opens no filesystem, operating-system, debug, or native
 * extension library. The host reads both tracked source files before creating
 * the VM, then gives Lua only base (which owns coroutine), package, table,
 * string, and math.
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

struct bytes {
    char *data;
    size_t length;
};

static int require_reference;

static int read_file(const char *path, struct bytes *out) {
    FILE *file = fopen(path, "rb");
    long length;
    size_t read_length;

    if (file == NULL) {
        fprintf(stderr, "%s: %s\n", path, strerror(errno));
        return 0;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (length = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fprintf(stderr, "%s: cannot determine file size\n", path);
        fclose(file);
        return 0;
    }
    out->data = (char *)malloc((size_t)length + 1);
    if (out->data == NULL) {
        fprintf(stderr, "%s: allocation failed\n", path);
        fclose(file);
        return 0;
    }
    read_length = fread(out->data, 1, (size_t)length, file);
    fclose(file);
    if (read_length != (size_t)length) {
        fprintf(stderr, "%s: short read\n", path);
        free(out->data);
        return 0;
    }
    out->data[length] = '\0';
    out->length = (size_t)length;
    return 1;
}

static void open_library(lua_State *state, const char *name, lua_CFunction open) {
    lua_pushcfunction(state, open);
    lua_pushstring(state, name);
    lua_call(state, 1, 0);
}

static int traced_require(lua_State *state) {
    lua_Integer length;
    luaL_checkstring(state, 1);
    lua_getglobal(state, "NUPP_REQUIRED");
    length = (lua_Integer)lua_objlen(state, -1);
    lua_pushvalue(state, 1);
    lua_rawseti(state, -2, length + 1);
    lua_pop(state, 1);

    lua_rawgeti(state, LUA_REGISTRYINDEX, require_reference);
    lua_pushvalue(state, 1);
    lua_call(state, 1, 1);
    return 1;
}

static void install_require_trace(lua_State *state) {
    lua_getglobal(state, "require");
    require_reference = luaL_ref(state, LUA_REGISTRYINDEX);
    lua_newtable(state);
    lua_setglobal(state, "NUPP_REQUIRED");
    lua_pushcfunction(state, traced_require);
    lua_setglobal(state, "require");
}

static int load(lua_State *state, const struct bytes *source, const char *name) {
    if (luaL_loadbuffer(state, source->data, source->length, name) != 0) {
        fprintf(stderr, "%s\n", lua_tostring(state, -1));
        return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    struct bytes bundle = {0};
    struct bytes suite = {0};
    struct bytes expected = {0};
    lua_State *state;
    int ok = 0;

    if (argc != 3 && argc != 4) {
        fprintf(stderr, "usage: %s BUNDLE TEST_SUITE [EXPECTED_JSON]\n", argv[0]);
        return 2;
    }
    if (!read_file(argv[1], &bundle) || !read_file(argv[2], &suite) ||
        (argc == 4 && !read_file(argv[3], &expected))) {
        goto done;
    }
    state = luaL_newstate();
    if (state == NULL) {
        fprintf(stderr, "cannot create Lua state\n");
        goto done;
    }
    open_library(state, "", luaopen_base);
    open_library(state, LUA_LOADLIBNAME, luaopen_package);
    open_library(state, LUA_TABLIBNAME, luaopen_table);
    open_library(state, LUA_STRLIBNAME, luaopen_string);
    open_library(state, LUA_MATHLIBNAME, luaopen_math);
    install_require_trace(state);
    if (expected.data != NULL) {
        lua_pushlstring(state, expected.data, expected.length);
        lua_setglobal(state, "NUPP_EXPECTED");
    }

    if (!load(state, &bundle, "@nupp-compiler.lua") || lua_pcall(state, 0, 1, 0) != 0) {
        fprintf(stderr, "%s\n", lua_tostring(state, -1));
        lua_close(state);
        goto done;
    }
    if (!load(state, &suite, "@portable-compiler-smoke.lua") ||
        lua_pcall(state, 0, 1, 0) != 0) {
        fprintf(stderr, "%s\n", lua_tostring(state, -1));
        lua_close(state);
        goto done;
    }
    lua_pushvalue(state, -2);
    if (lua_pcall(state, 1, 0, 0) != 0) {
        fprintf(stderr, "%s\n", lua_tostring(state, -1));
        lua_close(state);
        goto done;
    }
    lua_close(state);
    ok = 1;

done:
    free(bundle.data);
    free(suite.data);
    free(expected.data);
    return ok ? 0 : 1;
}
