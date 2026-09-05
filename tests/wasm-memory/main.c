#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "nupp_memory.h"

static int reject_large_allocations;
static void *checked_alloc(void *context, void *pointer, size_t old_size, size_t size) {
    (void)context; (void)old_size;
    if (size == 0) { free(pointer); return NULL; }
    if (reject_large_allocations && size >= 1024) return NULL;
    return realloc(pointer, size);
}
static int allocation_failure(lua_State *state) {
    reject_large_allocations = lua_toboolean(state, 1);
    return 0;
}

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

static int lease_writable(lua_State *state) {
    lua_pushboolean(state, nupp_wasm_lease_writable((uint32_t)luaL_checknumber(state, 1)));
    return 1;
}

int main(int argc, char **argv) {
    lua_State *state = lua_newstate(checked_alloc, NULL);
    int failed;
    if (state == NULL || argc != 2) return 2;
    luaL_openlibs(state);
    lua_pushcfunction(state, allocation_failure);
    lua_setglobal(state, "failLargeAllocations");
    nupp_wasm_install_memory(state);
    lua_pushcfunction(state, lease_byte);
    lua_setglobal(state, "leaseByte");
    lua_pushcfunction(state, lease_writable);
    lua_setglobal(state, "leaseWritable");
    lua_pushcfunction(state, release_all);
    lua_setglobal(state, "releaseAll");
    failed = luaL_dofile(state, argv[1]);
    if (failed) fprintf(stderr, "%s\n", lua_tostring(state, -1));
    nupp_wasm_release_all_leases();
    lua_close(state);
    return failed ? 1 : 0;
}
