#ifndef NUPP_WASM_MEMORY_H
#define NUPP_WASM_MEMORY_H

#include <stddef.h>
#include <stdint.h>

#include "lua.h"

void nupp_wasm_install_memory(lua_State *state);
void *nupp_wasm_pointer_address(lua_State *state, int index, size_t bytes);
uintptr_t nupp_wasm_lease_address(uint32_t id);
uint32_t nupp_wasm_lease_size(uint32_t id);
int nupp_wasm_release_lease(uint32_t id);
void nupp_wasm_release_all_leases(void);

#endif
