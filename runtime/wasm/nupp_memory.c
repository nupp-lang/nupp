#include "nupp_memory.h"

#include <math.h>
#include <stdint.h>
#include <stddef.h>
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
        struct { size_t size; unsigned int references; } state;
        double aligned;
    } header;
    unsigned char bytes[1];
};

struct nupp_pointer {
    unsigned char *address;
    size_t remaining;
    size_t stride;
    unsigned char *base;
    size_t extent;
    int readonly;
    size_t empty_count;
    size_t empty_position;
};

struct nupp_transfer_lease {
    uint32_t id;
    unsigned char *address;
    size_t bytes;
    lua_State *state;
    int anchor;
    int writable;
};

static struct nupp_transfer_lease transfer_leases[NUPP_TRANSFER_LEASES];
static uint32_t next_transfer_lease = 1;

static int checked_integer(lua_State *state, int index, size_t *out) {
    lua_Number value = luaL_checknumber(state, index);
    if (!(value >= 0.0) || value >= (lua_Number)SIZE_MAX || floor(value) != value) {
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
    pointer->base = address;
    pointer->extent = remaining;
    pointer->readonly = 0;
    pointer->empty_count = pointer->empty_position = 0;
    luaL_getmetatable(state, NUPP_POINTER);
    lua_setmetatable(state, -2);
    lua_createtable(state, 0, 1);
    lua_pushvalue(state, anchor < 0 ? anchor - 2 : anchor);
    lua_setfield(state, -2, "anchor");
    if (lua_getmetatable(state, anchor < 0 ? anchor - 2 : anchor)) {
        luaL_getmetatable(state, NUPP_POINTER);
        int inherited = lua_rawequal(state, -1, -2);
        lua_pop(state, 2);
        if (inherited) {
            int at = anchor < 0 ? anchor - 2 : anchor;
            struct nupp_pointer *parent = (struct nupp_pointer *)lua_touserdata(state, at);
            pointer->base = parent->base;
            pointer->extent = parent->extent;
            pointer->readonly = parent->readonly;
            pointer->empty_count = parent->empty_count;
            pointer->empty_position = parent->empty_position;
            lua_getfenv(state, at);
            lua_getfield(state, -1, "anchor");
            lua_setfield(state, -3, "anchor");
            lua_getfield(state, -1, "element");
            lua_setfield(state, -3, "element");
            lua_pop(state, 1);
        }
    }
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
    allocation->header.state.size = size;
    allocation->header.state.references = 0;
    if (size != 0) {
        memset(allocation->bytes, 0, size);
    }
    luaL_getmetatable(state, NUPP_ALLOCATION);
    lua_setmetatable(state, -2);
    lua_newtable(state);
    lua_setfenv(state, -2);
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
    if (offset > allocation->header.state.size) {
        return luaL_error(state, "Wasm pointer offset is out of bounds");
    }
    if (stride == 0) {
        return luaL_error(state, "Wasm pointer stride must be positive");
    }
    struct nupp_pointer *pointer = new_pointer(
        state,
        allocation->bytes + offset,
        allocation->header.state.size - offset,
        stride,
        1
    );
    pointer->base = allocation->bytes;
    pointer->extent = allocation->header.state.size;
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
    if (pointer->stride == 0) {
        if (elements > pointer->empty_count - pointer->empty_position) return luaL_error(state, "Wasm pointer offset is out of bounds");
        struct nupp_pointer *out = new_pointer(state, pointer->address, pointer->remaining, 0, 1);
        out->empty_position += elements;
        return 1;
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

int nupp_wasm_lease_writable(uint32_t id) {
    struct nupp_transfer_lease *lease = id == 0 ? NULL : find_transfer_lease(id);
    return lease != NULL && lease->writable;
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
    lease->writable = 0;
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

void *nupp_wasm_write_pointer_address(lua_State *state, int index, size_t bytes) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, index, NUPP_POINTER);
    if (pointer->readonly) luaL_error(state, "Wasm string storage is read-only");
    return nupp_wasm_pointer_address(state, index, bytes);
}

static int memory_lease(lua_State *state) {
    struct nupp_pointer *pointer =
        (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t bytes;
    size_t index;
    uint32_t id;
    if (checked_integer(state, 2, &bytes) != 0) return 0;
    if (lua_toboolean(state, 3) && pointer->readonly) return luaL_error(state, "Wasm string storage is read-only");
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
    transfer_leases[index].writable = lua_toboolean(state, 3);
    lua_pushnumber(state, (lua_Number)id);
    return 1;
}

static int memory_release_lease(lua_State *state) {
    size_t raw;
    if (checked_integer(state, 1, &raw) != 0) return 0;
    lua_pushboolean(state, raw <= UINT32_MAX && nupp_wasm_release_lease((uint32_t)raw));
    return 1;
}

#define NUPP_WIDE "nupp.storage.int64"
struct nupp_wide { uint64_t bits; int unsign; };

static struct nupp_wide *test_wide(lua_State *state, int index) {
    if (!lua_isuserdata(state, index) || !lua_getmetatable(state, index)) return NULL;
    luaL_getmetatable(state, NUPP_WIDE);
    int same = lua_rawequal(state, -1, -2);
    lua_pop(state, 2);
    return same ? (struct nupp_wide *)lua_touserdata(state, index) : NULL;
}

static int memory_is_wide(lua_State *state) {
    struct nupp_wide *value = test_wide(state, 1);
    lua_pushboolean(state, value != NULL && (lua_isnoneornil(state, 2) || value->unsign == lua_toboolean(state, 2)));
    return 1;
}

static struct nupp_wide wide_value(lua_State *state, int index) {
    struct nupp_wide *existing = test_wide(state, index);
    if (existing) return *existing;
    struct nupp_wide value = {0, 0};
    if (lua_type(state, index) == LUA_TSTRING) {
        size_t length, at = 0;
        const char *text = lua_tolstring(state, index, &length);
        int negative = 0, base = 10;
        if (at < length && (text[at] == '-' || text[at] == '+')) negative = text[at++] == '-';
        if (at + 2 <= length && text[at] == '0' && (text[at + 1] == 'x' || text[at + 1] == 'X')) {
            base = 16; at += 2;
        }
        if (at == length) luaL_error(state, "wide integer needs digits");
        for (; at < length; at++) {
            unsigned char c = (unsigned char)text[at];
            unsigned digit = c >= '0' && c <= '9' ? c - '0' :
                c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : 255;
            if (digit >= (unsigned)base) luaL_error(state, "invalid wide integer digit");
            value.bits = value.bits * (unsigned)base + digit;
        }
        if (negative) value.bits = 0 - value.bits;
    } else {
        lua_Number number = luaL_checknumber(state, index);
        if (!isfinite(number)) luaL_error(state, "wide integer needs a finite number");
        double magnitude = fmod(fabs(trunc(number)), 18446744073709551616.0);
        value.bits = (uint64_t)magnitude;
        if (number < 0) value.bits = 0 - value.bits;
    }
    return value;
}

static int push_wide(lua_State *state, uint64_t bits, int unsign) {
    struct nupp_wide *value = (struct nupp_wide *)lua_newuserdata(state, sizeof(*value));
    value->bits = bits;
    value->unsign = unsign;
    luaL_getmetatable(state, NUPP_WIDE);
    lua_setmetatable(state, -2);
    return 1;
}

uint64_t nupp_wasm_wide_bits(lua_State *state, int index) {
    return wide_value(state, index).bits;
}

int nupp_wasm_push_wide(lua_State *state, uint64_t bits, int unsign) {
    return push_wide(state, bits, unsign);
}

static int wide_signed(lua_State *state) { return push_wide(state, wide_value(state, 1).bits, 0); }
static int wide_unsigned(lua_State *state) { return push_wide(state, wide_value(state, 1).bits, 1); }
static int wide_string(lua_State *state) {
    struct nupp_wide value = wide_value(state, 1);
    char text[32];
    uint64_t magnitude = value.bits;
    int negative = !value.unsign && (magnitude >> 63);
    if (negative) magnitude = 0 - magnitude;
    char *end = text + sizeof(text), *at = end;
    do { *--at = (char)('0' + magnitude % 10); magnitude /= 10; } while (magnitude);
    if (negative) *--at = '-';
    lua_pushlstring(state, at, (size_t)(end - at));
    return 1;
}
static int wide_number(lua_State *state) {
    struct nupp_wide value = wide_value(state, 1);
    lua_pushnumber(state, !value.unsign && (value.bits >> 63) ? -(lua_Number)(0 - value.bits) : (lua_Number)value.bits);
    return 1;
}
static int wide_compare_value(lua_State *state) {
    struct nupp_wide left = wide_value(state, 1), right = wide_value(state, 2);
    if (!left.unsign && (left.bits >> 63) && right.unsign) return -1;
    if (!right.unsign && (right.bits >> 63) && left.unsign) return 1;
    uint64_t a = left.bits, b = right.bits;
    if (!left.unsign && !right.unsign) { a ^= UINT64_C(1) << 63; b ^= UINT64_C(1) << 63; }
    return a < b ? -1 : a > b ? 1 : 0;
}
static int wide_compare(lua_State *state) { lua_pushnumber(state, wide_compare_value(state)); return 1; }
static int wide_equal(lua_State *state) { lua_pushboolean(state, wide_compare_value(state) == 0); return 1; }
static int wide_less(lua_State *state) { lua_pushboolean(state, wide_compare_value(state) < 0); return 1; }
static int wide_less_equal(lua_State *state) { lua_pushboolean(state, wide_compare_value(state) <= 0); return 1; }
static int wide_binary(lua_State *state) {
    struct nupp_wide a = wide_value(state, 1), b = wide_value(state, 2);
    int operation = (int)lua_tointeger(state, lua_upvalueindex(1));
    int unsign = a.unsign || b.unsign;
    uint64_t out = 0;
    switch (operation) {
        case 0: out = a.bits + b.bits; break;
        case 1: out = a.bits - b.bits; break;
        case 2: out = a.bits * b.bits; break;
        case 3: case 4: {
            if (b.bits == 0) return luaL_error(state, "wide integer division by zero");
            int aneg = !unsign && (a.bits >> 63), bneg = !unsign && (b.bits >> 63);
            uint64_t left = aneg ? 0 - a.bits : a.bits, right = bneg ? 0 - b.bits : b.bits;
            out = operation == 3 ? left / right : left % right;
            if (operation == 3 ? aneg != bneg : aneg) out = 0 - out;
            break;
        }
        case 5: {
            if (!b.unsign && (b.bits >> 63)) {
                out = a.bits == 1 ? 1 : a.bits == UINT64_MAX ? ((b.bits & 1) ? UINT64_MAX : 1) : 0;
            } else {
                out = 1;
                while (b.bits) { if (b.bits & 1) out *= a.bits; a.bits *= a.bits; b.bits >>= 1; }
            }
            break;
        }
        case 6: out = a.bits & b.bits; break;
        case 7: out = a.bits | b.bits; break;
        case 8: out = a.bits ^ b.bits; break;
    }
    return push_wide(state, out, unsign);
}
static int wide_neg(lua_State *state) {
    struct nupp_wide value = wide_value(state, 1);
    return push_wide(state, 0 - value.bits, value.unsign);
}
static int wide_not(lua_State *state) {
    struct nupp_wide value = wide_value(state, 1);
    return push_wide(state, ~value.bits, value.unsign);
}
static int wide_shift(lua_State *state) {
    struct nupp_wide value = wide_value(state, 1);
    lua_Number count = luaL_checknumber(state, 2);
    if (!isfinite(count)) return luaL_error(state, "wide shift count must be finite");
    int operation = (int)lua_tointeger(state, lua_upvalueindex(1));
    int signed_count = (int)fmod(trunc(count), 64.0);
    unsigned shift = (unsigned)(signed_count < 0 ? signed_count + 64 : signed_count);
    uint64_t out = operation == 0 ? value.bits << shift : value.bits >> shift;
    if (operation == 2 && shift && (value.bits >> 63)) out |= UINT64_MAX << (64 - shift);
    return push_wide(state, out, value.unsign);
}
static void push_wide_provider(lua_State *state) {
    static const char *binary[] = {"add", "sub", "mul", "div", "mod", "pow", "band", "bor", "bxor"};
    static const char *metamethod[] = {"__add", "__sub", "__mul", "__div", "__mod", "__pow"};
    static const char *shifts[] = {"lshift", "rshift", "arshift"};
    luaL_newmetatable(state, NUPP_WIDE);
    lua_pushcfunction(state, wide_string); lua_setfield(state, -2, "__tostring");
    lua_pushcfunction(state, wide_equal); lua_setfield(state, -2, "__eq");
    lua_pushcfunction(state, wide_less); lua_setfield(state, -2, "__lt");
    lua_pushcfunction(state, wide_less_equal); lua_setfield(state, -2, "__le");
    lua_pushcfunction(state, wide_neg); lua_setfield(state, -2, "__unm");
    for (int i = 0; i < 6; i++) { lua_pushinteger(state, i); lua_pushcclosure(state, wide_binary, 1); lua_setfield(state, -2, metamethod[i]); }
    lua_pop(state, 1);
    lua_newtable(state);
    lua_pushcfunction(state, wide_signed); lua_setfield(state, -2, "int64");
    lua_pushcfunction(state, wide_unsigned); lua_setfield(state, -2, "uint64");
    lua_pushcfunction(state, wide_string); lua_setfield(state, -2, "toString");
    lua_pushcfunction(state, wide_number); lua_setfield(state, -2, "toNumber");
    lua_pushcfunction(state, wide_compare); lua_setfield(state, -2, "compare");
    lua_pushcfunction(state, wide_neg); lua_setfield(state, -2, "neg");
    lua_pushcfunction(state, wide_not); lua_setfield(state, -2, "bnot");
    for (int i = 0; i < 9; i++) { lua_pushinteger(state, i); lua_pushcclosure(state, wide_binary, 1); lua_setfield(state, -2, binary[i]); }
    for (int i = 0; i < 3; i++) { lua_pushinteger(state, i); lua_pushcclosure(state, wide_shift, 1); lua_setfield(state, -2, shifts[i]); }
}

static size_t scalar_size(lua_State *state, const char *kind) {
    if (strcmp(kind, "boolean") == 0 || strcmp(kind, "int8") == 0 ||
        strcmp(kind, "uint8") == 0) return 1;
    if (strcmp(kind, "int16") == 0 || strcmp(kind, "uint16") == 0) return 2;
    if (strcmp(kind, "float") == 0 || strcmp(kind, "integer") == 0 ||
        strcmp(kind, "int32") == 0 || strcmp(kind, "uint32") == 0) return 4;
    if (strcmp(kind, "number") == 0 || strcmp(kind, "int64") == 0 || strcmp(kind, "uint64") == 0) return 8;
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

static int push_scalar(lua_State *state, const char *kind, unsigned char *source) {
    if (strcmp(kind, "int64") == 0 || strcmp(kind, "uint64") == 0) {
        uint64_t value; memcpy(&value, source, sizeof(value));
        return push_wide(state, value, strcmp(kind, "uint64") == 0);
    } else if (strcmp(kind, "boolean") == 0) {
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

static int memory_load(lua_State *state) {
    const char *kind = luaL_checkstring(state, 3);
    return push_scalar(state, kind, checked_scalar(state, 1, 2, kind));
}

static double modulo(lua_State *state, lua_Number value, double modulus) {
    double wrapped;
    /* fmod of an infinity or NaN answers NaN, and casting NaN to an integer
     * type is undefined -- on wasm, a trap that takes the whole instance. */
    if (!isfinite(value)) {
        luaL_error(state, "Wasm integer store needs a finite number");
    }
    value = trunc(value);
    if (value >= 0.0 && value < modulus) return value;
    wrapped = fmod(value, modulus);
    return wrapped < 0.0 ? wrapped + modulus : wrapped;
}

static int store_scalar(lua_State *state, const char *kind, unsigned char *destination, int value_index) {
    if (strcmp(kind, "int64") == 0 || strcmp(kind, "uint64") == 0) {
        struct nupp_wide value = wide_value(state, value_index);
        memcpy(destination, &value.bits, sizeof(value.bits));
    } else if (strcmp(kind, "boolean") == 0) {
        uint8_t value = (uint8_t)(lua_toboolean(state, value_index) != 0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "float") == 0) {
        float value = (float)luaL_checknumber(state, value_index);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "number") == 0) {
        double value = (double)luaL_checknumber(state, value_index);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "int8") == 0) {
        int8_t value = (int8_t)(uint8_t)modulo(state, luaL_checknumber(state, value_index), 256.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "uint8") == 0) {
        uint8_t value = (uint8_t)modulo(state, luaL_checknumber(state, value_index), 256.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "int16") == 0) {
        int16_t value = (int16_t)(uint16_t)modulo(state, luaL_checknumber(state, value_index), 65536.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "uint16") == 0) {
        uint16_t value = (uint16_t)modulo(state, luaL_checknumber(state, value_index), 65536.0);
        memcpy(destination, &value, sizeof(value));
    } else if (strcmp(kind, "integer") == 0 || strcmp(kind, "int32") == 0) {
        int32_t value = (int32_t)(uint32_t)modulo(state, luaL_checknumber(state, value_index), 4294967296.0);
        memcpy(destination, &value, sizeof(value));
    } else {
        uint32_t value = (uint32_t)modulo(state, luaL_checknumber(state, value_index), 4294967296.0);
        memcpy(destination, &value, sizeof(value));
    }
    return 0;
}

static void clear_references(lua_State *state, int pointer_index, size_t offset, size_t bytes, size_t except);

static int memory_store(lua_State *state) {
    const char *kind = luaL_checkstring(state, 3);
    unsigned char *destination = checked_scalar(state, 1, 2, kind);
    struct nupp_pointer *target = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    if (target->readonly) return luaL_error(state, "Wasm string storage is read-only");
    int result = store_scalar(state, kind, destination, 4);
    clear_references(state, 1, (size_t)(destination - target->address), scalar_size(state, kind), SIZE_MAX);
    return result;
}

static int memory_decode(lua_State *state) {
    const char *kind = luaL_checkstring(state, 1);
    size_t length, width = scalar_size(state, kind);
    luaL_checktype(state, 2, LUA_TSTRING);
    const char *bytes = lua_tolstring(state, 2, &length);
    if (length != width) return luaL_error(state, "scalar bytes have the wrong width");
    return push_scalar(state, kind, (unsigned char *)bytes);
}

static int memory_encode(lua_State *state) {
    const char *kind = luaL_checkstring(state, 1);
    size_t width = scalar_size(state, kind);
    unsigned char bytes[8];
    store_scalar(state, kind, bytes, 2);
    lua_pushlstring(state, (const char *)bytes, width);
    return 1;
}

/* Reference slots are rooted in the allocation environment, never in a global
 * address map. Copying bytes copies complete reference slots with their owners. */
static void push_roots(lua_State *state, int index) {
    lua_getfenv(state, index);
    lua_getfield(state, -1, "anchor");
    lua_remove(state, -2);
    if (lua_type(state, -1) == LUA_TUSERDATA) lua_getfenv(state, -1);
    else lua_pushnil(state);
    lua_remove(state, -2);
}

/* Every mutable pointer roots one allocation and carries its payload base.
 * Strings are the only non-allocation pointers and can never contain roots.
 * The conservative flag shares the allocation header, so independent pointer
 * projections observe reference stores without allocating per-pointer state. */
static struct nupp_allocation *pointer_allocation(struct nupp_pointer *pointer) {
    return pointer->readonly ? NULL : (struct nupp_allocation *)(pointer->base - offsetof(struct nupp_allocation, bytes));
}

static int has_references(struct nupp_pointer *pointer) {
    struct nupp_allocation *allocation = pointer_allocation(pointer);
    return allocation != NULL && allocation->header.state.references != 0;
}

static void clear_references(lua_State *state, int pointer_index, size_t offset, size_t bytes, size_t except) {
    if (bytes == 0) return;
    struct nupp_pointer *pointer = (struct nupp_pointer *)lua_touserdata(state, pointer_index);
    if (!has_references(pointer)) return;
    size_t first = (size_t)(pointer->address - pointer->base) + offset;
    push_roots(state, pointer_index);
    if (lua_istable(state, -1)) {
        lua_pushnil(state);
        while (lua_next(state, -2)) {
            size_t at = (size_t)lua_tonumber(state, -2);
            lua_pop(state, 1);
            if (at != except && at < first + bytes && at + 4 > first) {
                lua_pushvalue(state, -1);
                lua_pushnil(state);
                lua_rawset(state, -4);
            }
        }
    }
    lua_pop(state, 1);
}

static void copy_reference_roots(lua_State *state, int dest_index, size_t dest_offset, int source_index, size_t source_offset, size_t bytes, struct nupp_pointer *destination, struct nupp_pointer *source) {
    size_t first = (size_t)(destination->address - destination->base) + dest_offset;
    size_t from = (size_t)(source->address - source->base) + source_offset;
    int base = lua_gettop(state);
    push_roots(state, dest_index);
    push_roots(state, source_index);
    int populated = 0;
    for (int map = base + 1; map <= base + 2; map++) {
        if (lua_istable(state, map)) {
            lua_pushnil(state);
            if (lua_next(state, map)) { populated = 1; lua_pop(state, 2); }
        }
    }
    if (populated) {
        /* Prepare the complete replacement before publishing it: an allocation
         * failure must not leave copied addresses without their ownership roots. */
        lua_newtable(state);
        int replacement = lua_gettop(state);
        for (int map = base + 1; map <= base + 2; map++) {
            if (!lua_istable(state, map)) continue;
            lua_pushnil(state);
            while (lua_next(state, map)) {
                size_t at = (size_t)lua_tonumber(state, -2);
                int retained = map == base + 1 ? !(at < first + bytes && at + 4 > first) :
                    at >= from && at - from <= bytes && 4 <= bytes - (at - from);
                if (retained) {
                    size_t to = map == base + 1 ? at : first + (at - from);
                    lua_pushnumber(state, (lua_Number)to);
                    lua_pushvalue(state, -2);
                    lua_rawset(state, replacement);
                }
                lua_pop(state, 1);
            }
        }
        lua_getfenv(state, dest_index);
        lua_getfield(state, -1, "anchor");
        lua_pushvalue(state, replacement);
        lua_setfenv(state, -2);
        pointer_allocation(destination)->header.state.references = 1;
    }
    lua_settop(state, base);
}

static void copy_bytes(lua_State *state, int dest_index, size_t dest_offset, int source_index, size_t source_offset, size_t bytes) {
    struct nupp_pointer *destination = (struct nupp_pointer *)luaL_checkudata(state, dest_index, NUPP_POINTER);
    struct nupp_pointer *source = (struct nupp_pointer *)luaL_checkudata(state, source_index, NUPP_POINTER);
    if (destination->readonly) luaL_error(state, "Wasm string storage is read-only");
    if (dest_offset > destination->remaining || bytes > destination->remaining - dest_offset ||
        source_offset > source->remaining || bytes > source->remaining - source_offset) {
        luaL_error(state, "Wasm memory copy is out of bounds");
    }
    if (bytes == 0) return;
    if (has_references(destination) || has_references(source)) {
        copy_reference_roots(state, dest_index, dest_offset, source_index, source_offset, bytes, destination, source);
    }
    memmove(destination->address + dest_offset, source->address + source_offset, bytes);
}

static int memory_copy(lua_State *state) {
    size_t bytes;
    checked_integer(state, 3, &bytes);
    copy_bytes(state, 1, 0, 2, 0, bytes);
    return 0;
}

static int memory_copy_at(lua_State *state) {
    size_t destination, source, bytes;
    checked_integer(state, 2, &destination);
    checked_integer(state, 4, &source);
    checked_integer(state, 5, &bytes);
    copy_bytes(state, 1, destination, 3, source, bytes);
    return 0;
}

static int memory_store_reference(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    unsigned char *destination = checked_scalar(state, 1, 2, "uint32");
    if (pointer->readonly) return luaL_error(state, "Wasm string storage is read-only");
    uint32_t address = 0;
    if (!lua_isnil(state, 3)) {
        struct nupp_pointer *value = (struct nupp_pointer *)luaL_checkudata(state, 3, NUPP_POINTER);
        address = (uint32_t)(uintptr_t)value->address;
    }
    size_t at = (size_t)(destination - pointer->base);
    if (!lua_isnil(state, 3)) pointer_allocation(pointer)->header.state.references = 1;
    push_roots(state, 1);
    lua_pushnumber(state, (lua_Number)at);
    lua_pushvalue(state, 3);
    lua_rawset(state, -3);
    lua_pop(state, 1);
    clear_references(state, 1, (size_t)(destination - pointer->address), 4, at);
    memcpy(destination, &address, sizeof(address));
    return 0;
}

static int memory_load_reference(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    unsigned char *source = checked_scalar(state, 1, 2, "uint32");
    uint32_t address;
    memcpy(&address, source, sizeof(address));
    if (address == 0) { lua_pushnil(state); return 1; }
    push_roots(state, 1);
    lua_pushnumber(state, (lua_Number)(source - pointer->base));
    lua_rawget(state, -2);
    struct nupp_pointer *value = (struct nupp_pointer *)luaL_checkudata(state, -1, NUPP_POINTER);
    if ((uint32_t)(uintptr_t)value->address != address) return luaL_error(state, "Wasm reference has no matching ownership root");
    return 1;
}

static int memory_borrow_string(lua_State *state) {
    size_t length;
    luaL_checktype(state, 1, LUA_TSTRING);
    const char *bytes = lua_tolstring(state, 1, &length);
    struct nupp_pointer *pointer = new_pointer(state, (unsigned char *)bytes, length, 1, 1);
    pointer->readonly = 1;
    return 1;
}

static int memory_string(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t count;
    checked_integer(state, 2, &count);
    if (count > pointer->remaining) return luaL_error(state, "Wasm string range is out of bounds");
    lua_pushlstring(state, (const char *)pointer->address, count);
    return 1;
}

static int memory_fill(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t count, value;
    checked_integer(state, 2, &count);
    checked_integer(state, 3, &value);
    if (pointer->readonly) return luaL_error(state, "Wasm string storage is read-only");
    if (count > pointer->remaining || value > 255) return luaL_error(state, "Wasm fill range or byte is out of bounds");
    clear_references(state, 1, 0, count, SIZE_MAX);
    memset(pointer->address, (int)value, count);
    return 0;
}

static int memory_typed(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t width;
    luaL_checktype(state, 2, LUA_TTABLE);
    lua_getfield(state, 2, "size");
    checked_integer(state, -1, &width);
    lua_pop(state, 1);
    struct nupp_pointer *typed = new_pointer(state, pointer->address, pointer->remaining, width, 1);
    if (width == 0 && !lua_isnoneornil(state, 3)) {
        checked_integer(state, 3, &typed->empty_count);
        typed->empty_position = 0;
    }
    lua_getfenv(state, -1);
    lua_pushvalue(state, 2);
    lua_setfield(state, -2, "element");
    lua_pop(state, 1);
    return 1;
}

static int pointer_add(lua_State *state) {
    int at = lua_isnumber(state, 1) ? 2 : 1;
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, at, NUPP_POINTER);
    lua_Number elements = luaL_checknumber(state, at == 1 ? 2 : 1);
    if (pointer->stride == 0) {
        if (!isfinite(elements) || floor(elements) != elements || elements < -(lua_Number)pointer->empty_position || elements > (lua_Number)(pointer->empty_count - pointer->empty_position))
            return luaL_error(state, "Wasm pointer offset is out of bounds");
        struct nupp_pointer *out = new_pointer(state, pointer->address, pointer->remaining, 0, at);
        out->empty_position = elements < 0 ? pointer->empty_position - (size_t)(-elements) : pointer->empty_position + (size_t)elements;
        return 1;
    }
    size_t displacement = (size_t)(pointer->address - pointer->base);
    if (!isfinite(elements) || floor(elements) != elements ||
        elements < -(lua_Number)(displacement / pointer->stride) ||
        elements > (lua_Number)(pointer->stride == 0 ? pointer->empty_count - pointer->empty_position : pointer->remaining / pointer->stride)) {
        return luaL_error(state, "Wasm pointer offset is out of bounds");
    }
    size_t offset = elements < 0 ? displacement - (size_t)(-elements) * pointer->stride :
        displacement + (size_t)elements * pointer->stride;
    new_pointer(state, pointer->base + offset, pointer->extent - offset, pointer->stride, at);
    return 1;
}

static int pointer_subtract(lua_State *state) {
    struct nupp_pointer *left = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    if (lua_isnumber(state, 2)) {
        lua_pushnumber(state, -lua_tonumber(state, 2));
        lua_replace(state, 2);
        return pointer_add(state);
    }
    struct nupp_pointer *right = (struct nupp_pointer *)luaL_checkudata(state, 2, NUPP_POINTER);
    if (left->base != right->base || left->extent != right->extent || left->stride != right->stride)
        return luaL_error(state, "Wasm pointer difference needs one allocation and element layout");
    lua_pushnumber(state, left->stride == 0 ? (lua_Number)left->empty_position - (lua_Number)right->empty_position :
        ((lua_Number)(left->address - left->base) - (lua_Number)(right->address - right->base)) / (lua_Number)left->stride);
    return 1;
}

static int pointer_compare(lua_State *state) {
    struct nupp_pointer *left = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    struct nupp_pointer *right = (struct nupp_pointer *)luaL_checkudata(state, 2, NUPP_POINTER);
    if (left->base != right->base || left->extent != right->extent || left->stride != right->stride)
        return luaL_error(state, "Wasm pointer ordering needs one allocation and element layout");
    size_t a = left->stride == 0 ? left->empty_position : (size_t)(left->address - left->base);
    size_t b = right->stride == 0 ? right->empty_position : (size_t)(right->address - right->base);
    lua_pushboolean(state, lua_toboolean(state, lua_upvalueindex(1)) ? a <= b : a < b);
    return 1;
}

static int pointer_length(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    lua_pushnumber(state, (lua_Number)(pointer->stride == 0 ? pointer->empty_count - pointer->empty_position : pointer->remaining / pointer->stride));
    return 1;
}

static int pointer_index(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t index = 0;
    int field = lua_type(state, 2) == LUA_TSTRING;
    if (!field) checked_integer(state, 2, &index);
    if (index >= (pointer->stride == 0 ? pointer->empty_count - pointer->empty_position : pointer->remaining / pointer->stride)) return luaL_error(state, "Wasm array index out of bounds");
    lua_getfenv(state, 1);
    lua_getfield(state, -1, "element");
    if (!lua_istable(state, -1)) return luaL_error(state, "Wasm pointer has no element representation");
    lua_getfield(state, -1, "read");
    lua_pushvalue(state, -2);
    lua_pushvalue(state, 1);
    lua_pushnumber(state, (lua_Number)(index * pointer->stride));
    lua_call(state, 3, 1);
    if (field) { lua_pushvalue(state, 2); lua_gettable(state, -2); }
    return 1;
}

static int pointer_store(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t index = 0;
    int field = lua_type(state, 2) == LUA_TSTRING;
    if (!field) checked_integer(state, 2, &index);
    if (pointer->readonly) return luaL_error(state, "Wasm string storage is read-only");
    if (index >= (pointer->stride == 0 ? pointer->empty_count - pointer->empty_position : pointer->remaining / pointer->stride)) return luaL_error(state, "Wasm array index out of bounds");
    lua_getfenv(state, 1);
    lua_getfield(state, -1, "element");
    if (!lua_istable(state, -1)) return luaL_error(state, "Wasm pointer has no element representation");
    lua_getfield(state, -1, field ? "read" : "write");
    lua_pushvalue(state, -2);
    lua_pushvalue(state, 1);
    lua_pushnumber(state, (lua_Number)(index * pointer->stride));
    if (field) {
        lua_call(state, 3, 1);
        lua_pushvalue(state, 2); lua_pushvalue(state, 3); lua_settable(state, -3);
    } else {
        lua_pushvalue(state, 3);
        lua_call(state, 4, 0);
    }
    return 0;
}

static int pointer_equal(lua_State *state) {
    struct nupp_pointer *left = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    struct nupp_pointer *right = (struct nupp_pointer *)luaL_checkudata(state, 2, NUPP_POINTER);
    lua_pushboolean(state, left->address == right->address);
    return 1;
}

/* wasm32 C bitfields occupy increasing low bits, possibly across bytes.
 * Walk the at-most-64 field bits without reading padding beyond the allocation. */
static int memory_bits(lua_State *state) {
    struct nupp_pointer *pointer = (struct nupp_pointer *)luaL_checkudata(state, 1, NUPP_POINTER);
    size_t offset, shift, width;
    checked_integer(state, 2, &offset); checked_integer(state, 3, &shift); checked_integer(state, 4, &width);
    const char *kind = luaL_checkstring(state, 5);
    if (shift > 7 || width == 0 || width > 64 || offset > pointer->remaining || (shift + width + 7) / 8 > pointer->remaining - offset)
        return luaL_error(state, "Wasm bitfield access is out of bounds");
    int writing = lua_gettop(state) >= 6;
    uint64_t value = 0;
    if (writing) {
        if (pointer->readonly) return luaL_error(state, "Wasm string storage is read-only");
        unsigned char bytes[8] = {0};
        store_scalar(state, kind, bytes, 6);
        memcpy(&value, bytes, scalar_size(state, kind));
        clear_references(state, 1, offset, (shift + width + 7) / 8, SIZE_MAX);
    }
    for (size_t bit = 0; bit < width; bit++) {
        size_t at = shift + bit;
        unsigned char mask = (unsigned char)(1u << (at % 8));
        if (writing) {
            unsigned char *byte = &pointer->address[offset + at / 8];
            *byte = (unsigned char)((*byte & ~mask) | (((value >> bit) & 1) ? mask : 0));
        } else if (pointer->address[offset + at / 8] & mask) value |= UINT64_C(1) << bit;
    }
    if (writing) return 0;
    if (strncmp(kind, "int", 3) == 0 && width < 64 && (value & (UINT64_C(1) << (width - 1)))) value |= UINT64_MAX << width;
    unsigned char bytes[8]; memcpy(bytes, &value, 8);
    return push_scalar(state, kind, bytes);
}

static const luaL_Reg memory_functions[] = {
    {"isWide", memory_is_wide},
    {"bits", memory_bits},
    {"allocate", memory_allocate},
    {"borrowString", memory_borrow_string},
    {"string", memory_string},
    {"fill", memory_fill},
    {"typed", memory_typed},
    {"decode", memory_decode},
    {"encode", memory_encode},
    {"pointer", memory_pointer},
    {"offset", memory_offset},
    {"load", memory_load},
    {"store", memory_store},
    {"copy", memory_copy},
    {"copyAt", memory_copy_at},
    {"storeReference", memory_store_reference},
    {"loadReference", memory_load_reference},
    {"lease", memory_lease},
    {"releaseLease", memory_release_lease},
    {NULL, NULL},
};

static void push_memory(lua_State *state) {
    luaL_newmetatable(state, NUPP_ALLOCATION);
    lua_pop(state, 1);
    luaL_newmetatable(state, NUPP_POINTER);
    lua_pushcfunction(state, pointer_add); lua_setfield(state, -2, "__add");
    lua_pushcfunction(state, pointer_subtract); lua_setfield(state, -2, "__sub");
    lua_pushboolean(state, 0); lua_pushcclosure(state, pointer_compare, 1); lua_setfield(state, -2, "__lt");
    lua_pushboolean(state, 1); lua_pushcclosure(state, pointer_compare, 1); lua_setfield(state, -2, "__le");
    lua_pushcfunction(state, pointer_length); lua_setfield(state, -2, "__len");
    lua_pushcfunction(state, pointer_index); lua_setfield(state, -2, "__index");
    lua_pushcfunction(state, pointer_store); lua_setfield(state, -2, "__newindex");
    lua_pushcfunction(state, pointer_equal); lua_setfield(state, -2, "__eq");
    lua_pop(state, 1);
    lua_newtable(state);
    luaL_register(state, NULL, memory_functions);
    push_wide_provider(state);
    lua_setfield(state, -2, "int64");
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
