#ifndef NUPP_WASM_MEMORY_H
#define NUPP_WASM_MEMORY_H

#include <stddef.h>

#include "lua.h"

int luaopen_nupp_wasm_memory(lua_State *state);
void nupp_wasm_install_memory(lua_State *state);
void *nupp_wasm_pointer_address(lua_State *state, int index, size_t bytes);

#endif
