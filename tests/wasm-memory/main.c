#include <stdio.h>
#include <stdint.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "nupp_memory.h"

static int lease_byte(lua_State *state) {
    uint32_t id = (uint32_t)luaL_checknumber(state, 1);
    uintptr_t address = nupp_wasm_lease_address(id);
    if (!address || nupp_wasm_lease_size(id) == 0) {
        return luaL_error(state, "lease is not live");
    }
    lua_pushnumber(state, *(unsigned char *)address);
    return 1;
}

static int release_all(lua_State *state) {
    (void)state;
    nupp_wasm_release_all_leases();
    return 0;
}

int main(int argc, char **argv) {
    lua_State *state = luaL_newstate();
    int failed;
    if (state == NULL || argc != 2) return 2;
    luaL_openlibs(state);
    nupp_wasm_install_memory(state);
    lua_pushcfunction(state, lease_byte);
    lua_setglobal(state, "leaseByte");
    lua_pushcfunction(state, release_all);
    lua_setglobal(state, "releaseAll");
    failed = luaL_dofile(state, argv[1]);
    if (failed) fprintf(stderr, "%s\n", lua_tostring(state, -1));
    nupp_wasm_release_all_leases();
    lua_close(state);
    return failed ? 1 : 0;
}
