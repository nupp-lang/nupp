#include "nupp_memory.h"

#include <math.h>
#include <stdint.h>
#include <string.h>

#include "lauxlib.h"

#define NUPP_ALLOCATION "nupp.wasm.allocation"
#define NUPP_POINTER "nupp.wasm.pointer"
#define NUPP_TRANSFER_LEASES 128

/* The header is a union with double so `bytes` sits eight-aligned: AOT
 * kernels cast the payload to double and wider element pointers, and a
 * payload at offset four would make every one of those accesses misaligned. */
struct nupp_allocation {
    union {
        size_t size;
        double aligned;
    } header;
    unsigned char bytes[1];
};

struct nupp_pointer {
    unsigned char *address;
    size_t remaining;
    size_t stride;
};

struct nupp_transfer_lease {
    uint32_t id;
    unsigned char *address;
    size_t bytes;
    lua_State *state;
    int anchor;
};

static struct nupp_transfer_lease transfer_leases[NUPP_TRANSFER_LEASES];
static uint32_t next_transfer_lease = 1;

static int checked_integer(lua_State *state, int index, size_t *out) {
    lua_Number value = luaL_checknumber(state, index);
    if (!(value >= 0.0) || value > (lua_Number)SIZE_MAX || floor(value) != value) {
        return luaL_error(state, "Wasm memory argument %d must be a nonnegative integer", index);
    }
    *out = (size_t)value;
    return 0;
}

static struct nupp_pointer *new_pointer(
    lua_State *state,
    unsigned char *address,
    size_t remaining,
    size_t stride,
    int anchor
) {
    struct nupp_pointer *pointer =
        (struct nupp_pointer *)lua_newuserdata(state, sizeof(*pointer));
    pointer->address = address;
    pointer->remaining = remaining;
    pointer->stride = stride;
    luaL_getmetatable(state, NUPP_POINTER);
    lua_setmetatable(state, -2);
    lua_createtable(state, 0, 1);
    lua_pushvalue(state, anchor < 0 ? anchor - 2 : anchor);
    lua_setfield(state, -2, "anchor");
    lua_setfenv(state, -2);
    return pointer;
}

static int memory_allocate(lua_State *state) {
    size_t size;
    struct nupp_allocation *allocation;
    if (checked_integer(state, 1, &size) != 0) {
        return 0;
    }
    if (size > SIZE_MAX - sizeof(*allocation)) {
        return luaL_error(state, "Wasm allocation size overflows");
    }
    allocation = (struct nupp_allocation *)lua_newuserdata(
        state,
        sizeof(*allocation) + (size == 0 ? 0 : size - 1)
    );
    allocation->header.size = size;
    if (size != 0) {
        memset(allocation->bytes, 0, size);
    }
    luaL_getmetatable(state, NUPP_ALLOCATION);
    lua_setmetatable(state, -2);
    return 1;
}

static int memory_pointer(lua_State *state) {
    struct nupp_allocation *allocation =
        (struct nupp_allocation *)luaL_checkudata(state, 1, NUPP_ALLOCATION);
    size_t offset;
    size_t stride;
    if (checked_integer(state, 2, &offset) != 0 ||
        checked_integer(state, 3, &stride) != 0) {
        return 0;
    }
    if (offset > allocation->header.size) {
        return luaL_error(state, "Wasm pointer offset is out of bounds");
    }
    if (stride == 0) {
        return luaL_error(state, "Wasm pointer stride must be positive");
    }
    new_pointer(
        state,
        allocation->bytes + offset,
        allocation->header.size - offset,
        stride,
        1
    );
    return 1;
}

static int memory_offset(lua_State *state) {
    struct nupp_pointer *pointer =
        (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t elements;
    size_t bytes;
    if (checked_integer(state, 2, &elements) != 0) {
        return 0;
    }
    if (elements > SIZE_MAX / pointer->stride) {
        return luaL_error(state, "Wasm pointer offset overflows");
    }
    bytes = elements * pointer->stride;
    if (bytes > pointer->remaining) {
        return luaL_error(state, "Wasm pointer offset is out of bounds");
    }
    new_pointer(
        state,
        pointer->address + bytes,
        pointer->remaining - bytes,
        pointer->stride,
        1
    );
    return 1;
}

void *nupp_wasm_pointer_address(lua_State *state, int index, size_t bytes) {
    struct nupp_pointer *pointer =
        (struct nupp_pointer *)luaL_checkudata(state, index, NUPP_POINTER);
    if (bytes > pointer->remaining) {
        luaL_error(state, "Wasm pointer range is out of bounds");
        return NULL;
    }
    return pointer->address;
}

static struct nupp_transfer_lease *find_transfer_lease(uint32_t id) {
    size_t index;
    for (index = 0; index < NUPP_TRANSFER_LEASES; index++) {
        if (transfer_leases[index].id == id) return &transfer_leases[index];
    }
    return NULL;
}

uintptr_t nupp_wasm_lease_address(uint32_t id) {
    struct nupp_transfer_lease *lease = find_transfer_lease(id);
    return lease == NULL ? 0 : (uintptr_t)lease->address;
}

uint32_t nupp_wasm_lease_size(uint32_t id) {
    struct nupp_transfer_lease *lease = find_transfer_lease(id);
    return lease == NULL || lease->bytes > UINT32_MAX ? 0 : (uint32_t)lease->bytes;
}

int nupp_wasm_release_lease(uint32_t id) {
    struct nupp_transfer_lease *lease = find_transfer_lease(id);
    if (id == 0 || lease == NULL) return 0;
    /* The anchor keeps both the pointer and this Lua thread alive until the
     * foreign consumer finishes. An address alone is not an ownership root. */
    luaL_unref(lease->state, LUA_REGISTRYINDEX, lease->anchor);
    lease->id = 0;
    lease->address = NULL;
    lease->bytes = 0;
    lease->state = NULL;
    lease->anchor = LUA_NOREF;
    return 1;
}

void nupp_wasm_release_all_leases(void) {
    size_t index;
    for (index = 0; index < NUPP_TRANSFER_LEASES; index++) {
        if (transfer_leases[index].id != 0) {
            nupp_wasm_release_lease(transfer_leases[index].id);
        }
    }
}

static int memory_lease(lua_State *state) {
    struct nupp_pointer *pointer =
        (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t bytes;
    size_t index;
    uint32_t id;
    if (checked_integer(state, 2, &bytes) != 0) return 0;
    if (bytes > pointer->remaining || bytes > UINT32_MAX) {
        return luaL_error(state, "Wasm transfer lease is out of bounds");
    }
    for (index = 0; index < NUPP_TRANSFER_LEASES; index++) {
        if (transfer_leases[index].id == 0) break;
    }
    if (index == NUPP_TRANSFER_LEASES) {
        return luaL_error(state, "Wasm transfer lease limit exceeded");
    }
    do {
        id = next_transfer_lease++;
    } while (id == 0 || find_transfer_lease(id) != NULL);
    /* Root the issuing coroutine too: the registry outlives a coroutine, but
     * using its lua_State to release the reference requires the thread to live. */
    lua_createtable(state, 2, 0);
    lua_pushvalue(state, 1);
    lua_rawseti(state, -2, 1);
    lua_pushthread(state);
    lua_rawseti(state, -2, 2);
    transfer_leases[index].anchor = luaL_ref(state, LUA_REGISTRYINDEX);
    transfer_leases[index].state = state;
    transfer_leases[index].id = id;
    transfer_leases[index].address = pointer->address;
    transfer_leases[index].bytes = bytes;
    lua_pushnumber(state, (lua_Number)id);
    return 1;
}

static int memory_release_lease(lua_State *state) {
    size_t raw;
    if (checked_integer(state, 1, &raw) != 0) return 0;
    lua_pushboolean(state, raw <= UINT32_MAX && nupp_wasm_release_lease((uint32_t)raw));
    return 1;
}

static size_t scalar_size(lua_State *state, const char *kind) {
    if (strcmp(kind, "boolean") == 0 || strcmp(kind, "int8") == 0 ||
        strcmp(kind, "uint8") == 0) return 1;
    if (strcmp(kind, "int16") == 0 || strcmp(kind, "uint16") == 0) return 2;
    if (strcmp(kind, "float") == 0 || strcmp(kind, "integer") == 0 ||
        strcmp(kind, "int32") == 0 || strcmp(kind, "uint32") == 0) return 4;
    if (strcmp(kind, "number") == 0) return 8;
    luaL_error(state, "unknown Wasm scalar kind %s", kind);
    return 0;
}

static unsigned char *checked_scalar(
    lua_State *state,
    int pointer_index,
    int offset_index,
    const char *kind
) {
    struct nupp_pointer *pointer =
        (struct nupp_pointer *)luaL_checkudata(state, pointer_index, NUPP_POINTER);
    size_t offset;
    size_t width = scalar_size(state, kind);
    if (checked_integer(state, offset_index, &offset) != 0) {
        return NULL;
    }
    if (offset > pointer->remaining || width > pointer->remaining - offset) {
        luaL_error(state, "Wasm scalar access is out of bounds");
        return NULL;
    }
    return pointer->address + offset;
}

static int memory_load(lua_State *state) {
    const char *kind = luaL_checkstring(state, 3);
    unsigned char *source = checked_scalar(state, 1, 2, kind);
    if (strcmp(kind, "boolean") == 0) {
        uint8_t value;
        memcpy(&value, source, sizeof(value));
        lua_pushboolean(state, value != 0);
    } else if (strcmp(kind, "float") == 0) {
        float value;
        memcpy(&value, source, sizeof(value));
        lua_pushnumber(state, value);
    } else if (strcmp(kind, "number") == 0) {
        double value;
        memcpy(&value, source, sizeof(value));
        lua_pushnumber(state, value);
    } else if (strcmp(kind, "int8") == 0) {
        int8_t value; memcpy(&value, source, sizeof(value)); lua_pushnumber(state, value);
    } else if (strcmp(kind, "uint8") == 0) {
        uint8_t value; memcpy(&value, source, sizeof(value)); lua_pushnumber(state, value);
    } else if (strcmp(kind, "int16") == 0) {
        int16_t value; memcpy(&value, source, sizeof(value)); lua_pushnumber(state, value);
    } else if (strcmp(kind, "uint16") == 0) {
        uint16_t value; memcpy(&value, source, sizeof(value)); lua_pushnumber(state, value);
    } else if (strcmp(kind, "integer") == 0 || strcmp(kind, "int32") == 0) {
        int32_t value; memcpy(&value, source, sizeof(value)); lua_pushnumber(state, value);
    } else {
        uint32_t value; memcpy(&value, source, sizeof(value)); lua_pushnumber(state, value);
    }
    return 1;
}

static double modulo(lua_State *state, lua_Number value, double modulus) {
    double wrapped;
    /* fmod of an infinity or NaN answers NaN, and casting NaN to an integer
     * type is undefined -- on wasm, a trap that takes the whole instance. */
    if (!isfinite(value)) {
        luaL_error(state, "Wasm integer store needs a finite number");
    }
    wrapped = fmod(value, modulus);
    return wrapped < 0.0 ? wrapped + modulus : wrapped;
}

static int memory_store(lua_State *state) {
    const char *kind = luaL_checkstring(state, 3);
    unsigned char *destination = checked_scalar(state, 1, 2, kind);
    if (strcmp(kind, "boolean") == 0) {
        uint8_t value = (uint8_t)(lua_toboolean(state, 4) != 0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "float") == 0) {
        float value = (float)luaL_checknumber(state, 4);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "number") == 0) {
        double value = (double)luaL_checknumber(state, 4);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "int8") == 0) {
        int8_t value = (int8_t)(uint8_t)modulo(state, luaL_checknumber(state, 4), 256.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "uint8") == 0) {
        uint8_t value = (uint8_t)modulo(state, luaL_checknumber(state, 4), 256.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "int16") == 0) {
        int16_t value = (int16_t)(uint16_t)modulo(state, luaL_checknumber(state, 4), 65536.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "uint16") == 0) {
        uint16_t value = (uint16_t)modulo(state, luaL_checknumber(state, 4), 65536.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "integer") == 0 || strcmp(kind, "int32") == 0) {
        int32_t value = (int32_t)(uint32_t)modulo(state, luaL_checknumber(state, 4), 4294967296.0);
        memcpy(destination, &value, sizeof(value));
    } else {
        uint32_t value = (uint32_t)modulo(state, luaL_checknumber(state, 4), 4294967296.0);
        memcpy(destination, &value, sizeof(value));
    }
    return 0;
}

static int memory_copy(lua_State *state) {
    size_t bytes;
    struct nupp_pointer *destination =
        (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    struct nupp_pointer *source =
        (struct nupp_pointer *)luaL_checkudata(state, 2, NUPP_POINTER);
    if (checked_integer(state, 3, &bytes) != 0) {
        return 0;
    }
    if (bytes > destination->remaining || bytes > source->remaining) {
        return luaL_error(state, "Wasm memory copy is out of bounds");
    }
    memmove(destination->address, source->address, bytes);
    return 0;
}

static const luaL_Reg memory_functions[] = {
    {"allocate", memory_allocate},
    {"pointer", memory_pointer},
    {"offset", memory_offset},
    {"load", memory_load},
    {"store", memory_store},
    {"copy", memory_copy},
    {"lease", memory_lease},
    {"releaseLease", memory_release_lease},
    {NULL, NULL},
};

static void push_memory(lua_State *state) {
    luaL_newmetatable(state, NUPP_ALLOCATION);
    lua_pop(state, 1);
    luaL_newmetatable(state, NUPP_POINTER);
    lua_pop(state, 1);
    lua_newtable(state);
    luaL_register(state, NULL, memory_functions);
}

void nupp_wasm_install_memory(lua_State *state) {
    push_memory(state);
    /* The host's raw service, which the checked storage provider wraps and adds
       `descriptor` to. `__nuppWasm` is the name the selected seam publishes that
       provider under, and it is what `nupp.wasm` reads; installing this table there
       both shadowed the provider and made the seam refuse a binding already set. */
    lua_setglobal(state, "__nuppWasmHost");

    lua_newtable(state);
    lua_setglobal(state, "__nuppWasmAot");
}
