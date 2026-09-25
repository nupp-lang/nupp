/* The AOT runtime: what LLVM-compiled Lua-builder entries call.
 *
 * Generated code reaches the runtime through one table of pointers rather
 * than through symbols, so nothing has to be exported from the process that
 * loads it or resolved by the loader: the provider hands the table's address
 * to a compiled module's registrar, which keeps it. Slot 0 is the ABI version
 * and slots 1-4 the sizes of the blocks generated code allocates; the
 * registrar refuses a table that disagrees with what it was compiled for.
 *
 * Slots 5-10 are where generated code finds a value stream's depth and its
 * current frame's kind and count, which it reads itself rather than paying a
 * call for three loads; the registrar refuses a table whose layout differs.
 *
 * The code is `ks_lua.h`'s, the C lowering's own prelude, included whole so
 * both backends run the same builder while both exist. What this file adds is
 * the ABI those functions are called through: every argument a pointer or a
 * 64-bit scalar (narrow values widened by the caller), no aggregate by value,
 * and every raise through a function that does not return.
 *
 * The slot order is the ABI. `nupp.compiler.aot.llvm.lua.runtime` lists the
 * same slots, and a test holds the two lists to one another. */
#define KS_JSON_WIDE 1
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE 1
#endif
#include <stddef.h>

/* The provider is loaded by processes that carry the Lua API and by ones that
 * do not export it (an embedding host that links LuaJIT privately), and on
 * Windows every import names its module, which the VM's differs by process.
 * So the runtime imports none of the API: it calls it through pointers, filled
 * from the process the first time the table is asked for. Each name below
 * turns the header's declaration of that function into one of a pointer. */
#define luaL_addlstring (*ks_lua_ptr_luaL_addlstring)
#define luaL_addvalue (*ks_lua_ptr_luaL_addvalue)
#define luaL_buffinit (*ks_lua_ptr_luaL_buffinit)
#define luaL_checklstring (*ks_lua_ptr_luaL_checklstring)
#define luaL_checknumber (*ks_lua_ptr_luaL_checknumber)
#define luaL_error (*ks_lua_ptr_luaL_error)
#define luaL_pushresult (*ks_lua_ptr_luaL_pushresult)
#define lua_call (*ks_lua_ptr_lua_call)
#define lua_checkstack (*ks_lua_ptr_lua_checkstack)
#define lua_concat (*ks_lua_ptr_lua_concat)
#define lua_createtable (*ks_lua_ptr_lua_createtable)
#define lua_equal (*ks_lua_ptr_lua_equal)
#define lua_getfield (*ks_lua_ptr_lua_getfield)
#define lua_getmetatable (*ks_lua_ptr_lua_getmetatable)
#define lua_gettop (*ks_lua_ptr_lua_gettop)
#define lua_insert (*ks_lua_ptr_lua_insert)
#define lua_newuserdata (*ks_lua_ptr_lua_newuserdata)
#define lua_next (*ks_lua_ptr_lua_next)
#define lua_objlen (*ks_lua_ptr_lua_objlen)
#define lua_pushboolean (*ks_lua_ptr_lua_pushboolean)
#define lua_pushcclosure (*ks_lua_ptr_lua_pushcclosure)
#define lua_pushlightuserdata (*ks_lua_ptr_lua_pushlightuserdata)
#define lua_pushlstring (*ks_lua_ptr_lua_pushlstring)
#define lua_pushnil (*ks_lua_ptr_lua_pushnil)
#define lua_pushnumber (*ks_lua_ptr_lua_pushnumber)
#define lua_pushvalue (*ks_lua_ptr_lua_pushvalue)
#define lua_rawequal (*ks_lua_ptr_lua_rawequal)
#define lua_rawget (*ks_lua_ptr_lua_rawget)
#define lua_rawgeti (*ks_lua_ptr_lua_rawgeti)
#define lua_rawset (*ks_lua_ptr_lua_rawset)
#define lua_rawseti (*ks_lua_ptr_lua_rawseti)
#define lua_remove (*ks_lua_ptr_lua_remove)
#define lua_replace (*ks_lua_ptr_lua_replace)
#define lua_setmetatable (*ks_lua_ptr_lua_setmetatable)
#define lua_settop (*ks_lua_ptr_lua_settop)
#define lua_toboolean (*ks_lua_ptr_lua_toboolean)
#define lua_tolstring (*ks_lua_ptr_lua_tolstring)
#define lua_tonumber (*ks_lua_ptr_lua_tonumber)
#define lua_topointer (*ks_lua_ptr_lua_topointer)
#define lua_touserdata (*ks_lua_ptr_lua_touserdata)
#define lua_type (*ks_lua_ptr_lua_type)

#include "ks_prelude.h"
#include "ks_lua.h"

#define KS_RT_ABI_VERSION 1u

extern void luaL_addvalue(KsLuaStringBuffer *buffer);

#define KS_RT_LUA_API(X) \
    X(luaL_addlstring) \
    X(luaL_addvalue) \
    X(luaL_buffinit) \
    X(luaL_checklstring) \
    X(luaL_checknumber) \
    X(luaL_error) \
    X(luaL_pushresult) \
    X(lua_call) \
    X(lua_checkstack) \
    X(lua_concat) \
    X(lua_createtable) \
    X(lua_equal) \
    X(lua_getfield) \
    X(lua_getmetatable) \
    X(lua_gettop) \
    X(lua_insert) \
    X(lua_newuserdata) \
    X(lua_next) \
    X(lua_objlen) \
    X(lua_pushboolean) \
    X(lua_pushcclosure) \
    X(lua_pushlightuserdata) \
    X(lua_pushlstring) \
    X(lua_pushnil) \
    X(lua_pushnumber) \
    X(lua_pushvalue) \
    X(lua_rawequal) \
    X(lua_rawget) \
    X(lua_rawgeti) \
    X(lua_rawset) \
    X(lua_rawseti) \
    X(lua_remove) \
    X(lua_replace) \
    X(lua_setmetatable) \
    X(lua_settop) \
    X(lua_toboolean) \
    X(lua_tolstring) \
    X(lua_tonumber) \
    X(lua_topointer) \
    X(lua_touserdata) \
    X(lua_type)

#define KS_RT_POINTER(name) __typeof__(ks_lua_ptr_##name) ks_lua_ptr_##name;
KS_RT_LUA_API(KS_RT_POINTER)
#undef KS_RT_POINTER

#if defined(_WIN32)
__declspec(dllimport) void *__stdcall GetModuleHandleA(const char *name);
__declspec(dllimport) void *__stdcall GetProcAddress(void *module, const char *name);
/* The program's own exports first: LuaJIT linked in exports its API. */
static void *ks_rt_lua_module(void) {
    void *module = GetModuleHandleA(NULL);
    if (!module || !GetProcAddress(module, "lua_gettop")) module = GetModuleHandleA("lua51.dll");
    return module;
}
#define KS_RT_LOOKUP(module, name) GetProcAddress((module), (name))
#else
#include <dlfcn.h>
static void *ks_rt_lua_module(void) { return RTLD_DEFAULT; }
#define KS_RT_LOOKUP(module, name) dlsym((module), (name))
#endif

/* 1 once every pointer is filled, 0 when the process exports no Lua API. */
int ks_rt_bind(void) {
    static int bound;
    void *module;
    if (bound) return 1;
    module = ks_rt_lua_module();
    if (!module) return 0;
#define KS_RT_RESOLVE(name) \
    ks_lua_ptr_##name = (__typeof__(ks_lua_ptr_##name))KS_RT_LOOKUP(module, #name); \
    if (!ks_lua_ptr_##name) return 0;
    KS_RT_LUA_API(KS_RT_RESOLVE)
#undef KS_RT_RESOLVE
    bound = 1;
    return 1;
}

#if defined(__GNUC__) || defined(__clang__)
#define KS_RT_NORETURN __attribute__((noreturn, noinline, cold))
#else
#define KS_RT_NORETURN
#endif

/* The fixed messages a check in generated code raises, by id. */
static const char *const ks_rt_messages[] = {
    "AOT runtime message out of range",
    "AOT builder Lua stack exhausted",
    "AOT builder string exceeds uint32 range",
    "AOT builder byte is out of bounds",
    "AOT builder word index overflows",
    "AOT builder word is out of bounds",
    "AOT string.byte index is out of bounds",
    "AOT scratch read is out of bounds",
    "AOT scratch write is out of bounds",
    "AOT escape scratch read is out of bounds",
    "AOT byte scratch read is out of bounds",
    "AOT byte scratch write is out of bounds",
    "AOT byte scratch write straddles the length",
    "AOT fresh table entry is not numeric",
    "AOT string.sub bounds must be integers",
    "AOT runtime is not the one this module was compiled for",
    "AOT value stream has no current container",
};

static KS_RT_NORETURN void ks_rt_raise(lua_State *L, uint64_t message) {
    size_t count = sizeof(ks_rt_messages) / sizeof(ks_rt_messages[0]);
    luaL_error(L, "%s", ks_rt_messages[message < count ? message : 0]);
    for (;;) {}
}

static KS_RT_NORETURN void ks_rt_raise_count(lua_State *L, const char *what) {
    luaL_error(L, "AOT builder %s must be a nonnegative integer in C API range", what);
    for (;;) {}
}

static KS_RT_NORETURN void ks_rt_raise_index(lua_State *L, const char *site) {
    luaL_error(L, "AOT builder array index at %s must be a positive integer in C API range", site);
    for (;;) {}
}

static const unsigned char *ks_rt_bytes(lua_State *L, int64_t index, size_t *length) {
    return ks_lua_bytes(L, (int)index, length);
}

static uint64_t ks_rt_count(lua_State *L, double value, const char *what) {
    return (uint64_t)ks_lua_count(L, value, what);
}

static uint64_t ks_rt_index(lua_State *L, double value, const char *site) {
    return (uint64_t)ks_lua_index(L, value, site);
}

static uint64_t ks_rt_string_match(lua_State *L, int64_t index, const char *literal, size_t length) {
    return ks_lua_string_match(L, (int)index, literal, length) ? 1u : 0u;
}

static uint64_t ks_rt_string_length(lua_State *L, size_t length) {
    return ks_lua_string_length(L, length);
}

static uint64_t ks_rt_string_byte(lua_State *L, const unsigned char *bytes, size_t length, uint64_t offset) {
    return ks_lua_string_byte(L, bytes, length, (uint32_t)offset);
}

static double ks_rt_string_byte_lua(lua_State *L, const unsigned char *bytes, size_t length, double index) {
    return ks_lua_string_byte_lua(L, bytes, length, index);
}

static uint64_t ks_rt_string_u32(lua_State *L, const unsigned char *bytes, size_t length, uint64_t index) {
    return ks_lua_string_u32(L, bytes, length, (uint32_t)index);
}

static void ks_rt_substring(lua_State *L, const unsigned char *bytes, size_t length, double first, double last) {
    ks_lua_substring(L, bytes, length, first, last);
}

static double ks_rt_table_number(lua_State *L, int64_t table, double key, const char *site) {
    return ks_lua_table_number(L, (int)table, key, site);
}

static void ks_rt_string_buffer_init(lua_State *L, void *buffer) {
    ks_lua_string_buffer_init(L, (KsLuaStringBuffer *)buffer);
}

static void ks_rt_string_buffer_append(lua_State *L, void *buffer, const unsigned char *bytes, size_t length) {
    ks_lua_string_buffer_append(L, (KsLuaStringBuffer *)buffer, bytes, length);
}

static void ks_rt_string_buffer_append_slice(
    lua_State *L, void *buffer, const unsigned char *bytes, size_t length, double first, double last
) {
    ks_lua_string_buffer_append_slice(L, (KsLuaStringBuffer *)buffer, bytes, length, first, last);
}

/* The string on top of the stack, appended and popped as luaL_addvalue does,
 * which keeps the buffer's own stack slots balanced when it spills. */
static void ks_rt_string_buffer_append_top(lua_State *L, void *buffer) {
    (void)L;
    luaL_addvalue((KsLuaStringBuffer *)buffer);
}

static void ks_rt_string_buffer_finish(lua_State *L, void *buffer) {
    ks_lua_string_buffer_finish(L, (KsLuaStringBuffer *)buffer);
}

static void ks_rt_scratch_u32(lua_State *L, void *scratch, uint64_t capacity, const void *key) {
    ks_lua_scratch_u32(L, (KsLuaScratchU32 *)scratch, (uint32_t)capacity, key);
}

static void ks_rt_scratch_u32_fixed(lua_State *L, void *scratch, uint64_t capacity, const void *key) {
    ks_lua_scratch_u32_fixed(L, (KsLuaScratchU32 *)scratch, (uint32_t)capacity, key);
}

static void ks_rt_scratch_u32_stack(void *scratch, uint32_t *storage, uint64_t capacity) {
    ks_lua_scratch_u32_stack((KsLuaScratchU32 *)scratch, storage, (uint32_t)capacity);
}

static uint64_t ks_rt_scratch_u32_get(lua_State *L, void *scratch, uint64_t index) {
    return ks_lua_scratch_u32_get(L, (KsLuaScratchU32 *)scratch, (uint32_t)index);
}

static uint64_t ks_rt_scratch_u32_get_fixed(lua_State *L, void *scratch, uint64_t index, uint64_t bound) {
    return ks_lua_scratch_u32_get_fixed(L, (KsLuaScratchU32 *)scratch, (uint32_t)index, (uint32_t)bound);
}

static uint64_t ks_rt_scratch_u32_escape_get(lua_State *L, void *scratch, uint64_t index) {
    return ks_lua_scratch_u32_escape_get(L, (KsLuaScratchU32 *)scratch, (uint32_t)index);
}

static void ks_rt_scratch_u32_set(lua_State *L, void *scratch, uint64_t index, uint64_t value) {
    ks_lua_scratch_u32_set(L, (KsLuaScratchU32 *)scratch, (uint32_t)index, (uint32_t)value);
}

static void ks_rt_scratch_u32_set_fixed(lua_State *L, void *scratch, uint64_t index, uint64_t value, uint64_t bound) {
    ks_lua_scratch_u32_set_fixed(L, (KsLuaScratchU32 *)scratch, (uint32_t)index, (uint32_t)value, (uint32_t)bound);
}

static void ks_rt_scratch_u8(lua_State *L, void *scratch, uint64_t capacity) {
    *(KsLuaScratchU8 *)scratch = ks_lua_scratch_u8(L, (uint32_t)capacity);
}

static void ks_rt_scratch_u8_cached(lua_State *L, void *scratch, uint64_t capacity) {
    *(KsLuaScratchU8 *)scratch = ks_lua_scratch_u8_cached(L, (uint32_t)capacity);
}

static void ks_rt_scratch_u8_stack(void *scratch, unsigned char *storage, uint64_t capacity) {
    *(KsLuaScratchU8 *)scratch = ks_lua_scratch_u8_stack(storage, (uint32_t)capacity);
}

static uint64_t ks_rt_scratch_u8_get(lua_State *L, void *scratch, uint64_t index) {
    return ks_lua_scratch_u8_get(L, (KsLuaScratchU8 *)scratch, (uint32_t)index);
}

static uint64_t ks_rt_scratch_u8_get_fixed(lua_State *L, void *scratch, uint64_t index, uint64_t bound) {
    return ks_lua_scratch_u8_get_fixed(L, (KsLuaScratchU8 *)scratch, (uint32_t)index, (uint32_t)bound);
}

static void ks_rt_scratch_u8_set(lua_State *L, void *scratch, uint64_t index, uint64_t value) {
    ks_lua_scratch_u8_set(L, (KsLuaScratchU8 *)scratch, (uint32_t)index, (uint32_t)value);
}

static void ks_rt_scratch_u8_set_fixed(lua_State *L, void *scratch, uint64_t index, uint64_t value, uint64_t bound) {
    ks_lua_scratch_u8_set_fixed(L, (KsLuaScratchU8 *)scratch, (uint32_t)index, (uint32_t)value, (uint32_t)bound);
}

static void ks_rt_scratch_u8_set4(lua_State *L, void *scratch, uint64_t index, uint64_t value) {
    ks_lua_scratch_u8_set4(L, (KsLuaScratchU8 *)scratch, (uint32_t)index, (uint32_t)value);
}

static void ks_rt_scratch_u8_set4_fixed(lua_State *L, void *scratch, uint64_t index, uint64_t value, uint64_t bound) {
    ks_lua_scratch_u8_set4_fixed(L, (KsLuaScratchU8 *)scratch, (uint32_t)index, (uint32_t)value, (uint32_t)bound);
}

static void ks_rt_scratch_u8_push(lua_State *L, void *scratch, uint64_t start, uint64_t length) {
    ks_lua_scratch_u8_push(L, (KsLuaScratchU8 *)scratch, (uint32_t)start, (uint32_t)length);
}

static void ks_rt_builder_init(
    lua_State *L,
    void *builder,
    int64_t null_index,
    int64_t array_marker,
    int64_t object_marker,
    uint64_t max_depth,
    uint64_t byte_capacity,
    int64_t selection_shape,
    int64_t array_shape_marker,
    int64_t serde_markers,
    uint64_t eager
) {
    /* An eager stream takes no selection shape and no serde markers. */
    ks_lua_builder_init(
        L,
        (KsLuaBuilder *)builder,
        (int)null_index,
        (int)array_marker,
        (int)object_marker,
        (uint32_t)max_depth,
        (uint32_t)byte_capacity,
        eager ? 0 : (int)selection_shape,
        eager ? 0 : (int)array_shape_marker,
        eager ? 0 : (int)serde_markers
    );
}

static void ks_rt_builder_open(lua_State *L, void *builder, uint64_t kind, uint64_t capacity, uint64_t eager) {
    ks_lua_builder_open(L, (KsLuaBuilder *)builder, (uint32_t)kind, (uint32_t)capacity, (int)eager);
}

static void ks_rt_builder_string(
    lua_State *L,
    void *builder,
    const unsigned char *source,
    size_t length_of_source,
    uint64_t start,
    uint64_t length,
    uint64_t escaped,
    uint64_t key,
    uint64_t eager
) {
    ks_lua_builder_string(
        L, (KsLuaBuilder *)builder, source, length_of_source, (uint32_t)start, (uint32_t)length, (int)escaped,
        (int)key, (int)eager
    );
}

static void ks_rt_builder_string_escapes(
    lua_State *L,
    void *builder,
    const unsigned char *source,
    size_t length_of_source,
    uint64_t start,
    uint64_t length,
    void *escapes,
    uint64_t escape_index,
    uint64_t escape_count,
    uint64_t key,
    uint64_t eager
) {
    ks_lua_builder_string_escapes(
        L, (KsLuaBuilder *)builder, source, length_of_source, (uint32_t)start, (uint32_t)length,
        (KsLuaScratchU32 *)escapes, (uint32_t)escape_index, (uint32_t)escape_count, (int)key, (int)eager
    );
}

static void ks_rt_builder_number_slice(
    lua_State *L, void *builder, const unsigned char *source, size_t length_of_source, uint64_t start, uint64_t length,
    uint64_t eager
) {
    ks_lua_builder_number_slice(
        L, (KsLuaBuilder *)builder, source, length_of_source, (uint32_t)start, (uint32_t)length, (int)eager
    );
}

static void ks_rt_builder_integer_slice(
    lua_State *L, void *builder, const unsigned char *source, size_t length_of_source, uint64_t start, uint64_t length,
    uint64_t eager
) {
    ks_lua_builder_integer_slice(
        L, (KsLuaBuilder *)builder, source, length_of_source, (uint32_t)start, (uint32_t)length, (int)eager
    );
}

static void ks_rt_builder_number(lua_State *L, void *builder, double value, uint64_t eager) {
    ks_lua_builder_number(L, (KsLuaBuilder *)builder, value, (int)eager);
}

static void ks_rt_builder_integer64(lua_State *L, void *builder, uint64_t magnitude, uint64_t negative, uint64_t eager) {
    ks_lua_builder_integer64(L, (KsLuaBuilder *)builder, magnitude, (int)negative, (int)eager);
}

static void ks_rt_builder_decimal64(
    lua_State *L,
    void *builder,
    const unsigned char *source,
    size_t length_of_source,
    uint64_t start,
    uint64_t length,
    uint64_t magnitude,
    int64_t exponent,
    uint64_t negative,
    uint64_t exact,
    uint64_t eager
) {
    ks_lua_builder_decimal64(
        L, (KsLuaBuilder *)builder, source, length_of_source, (uint32_t)start, (uint32_t)length, magnitude,
        (int32_t)exponent, (int)negative, (int)exact, (int)eager
    );
}

static void ks_rt_builder_boolean(lua_State *L, void *builder, uint64_t value, uint64_t eager) {
    ks_lua_builder_boolean(L, (KsLuaBuilder *)builder, (int)value, (int)eager);
}

static void ks_rt_builder_null(lua_State *L, void *builder, uint64_t eager) {
    ks_lua_builder_null(L, (KsLuaBuilder *)builder, (int)eager);
}

static void ks_rt_builder_close(lua_State *L, void *builder, uint64_t eager) {
    ks_lua_builder_close(L, (KsLuaBuilder *)builder, (int)eager);
}

static void ks_rt_builder_key_scratch(lua_State *L, void *builder, void *scratch, uint64_t start, uint64_t length) {
    ks_lua_scratch_u8_push(L, (KsLuaScratchU8 *)scratch, (uint32_t)start, (uint32_t)length);
    ks_lua_builder_key(L, (KsLuaBuilder *)builder);
}

static void ks_rt_builder_string_scratch(
    lua_State *L, void *builder, void *scratch, uint64_t start, uint64_t length, uint64_t eager
) {
    ks_lua_scratch_u8_push(L, (KsLuaScratchU8 *)scratch, (uint32_t)start, (uint32_t)length);
    ks_lua_builder_pushed_scalar(L, (KsLuaBuilder *)builder, (int)eager);
}

static void ks_rt_builder_pushed_scalar(lua_State *L, void *builder, uint64_t eager) {
    ks_lua_builder_pushed_scalar(L, (KsLuaBuilder *)builder, (int)eager);
}

static void ks_rt_builder_key(lua_State *L, void *builder) {
    ks_lua_builder_key(L, (KsLuaBuilder *)builder);
}

static uint64_t ks_rt_builder_query(lua_State *L, void *builder, uint64_t which) {
    return ks_lua_builder_query(L, (KsLuaBuilder *)builder, (uint32_t)which);
}

static uint64_t ks_rt_builder_number_token(
    lua_State *L, void *builder, const unsigned char *source, size_t length_of_source, uint64_t start, uint64_t limit,
    uint64_t eager
) {
    return ks_lua_builder_number_token(
        L, (KsLuaBuilder *)builder, source, length_of_source, (uint32_t)start, (uint32_t)limit, (int)eager
    );
}

static void ks_rt_builder_finish(lua_State *L, void *builder) {
    ks_lua_builder_finish(L, (KsLuaBuilder *)builder);
}

/* The ABI, slot by slot. Sizes and offsets first so a registrar can check
 * its blocks and the fields it reads. */
const void *const ks_rt_table[] = {
    (const void *)(uintptr_t)KS_RT_ABI_VERSION,
    (const void *)(uintptr_t)sizeof(KsLuaBuilder),
    (const void *)(uintptr_t)sizeof(KsLuaStringBuffer),
    (const void *)(uintptr_t)sizeof(KsLuaScratchU32),
    (const void *)(uintptr_t)sizeof(KsLuaScratchU8),
    (const void *)(uintptr_t)offsetof(KsLuaBuilder, depth),
    (const void *)(uintptr_t)offsetof(KsLuaBuilder, frames),
    (const void *)(uintptr_t)offsetof(KsLuaBuilder, inline_frames),
    (const void *)(uintptr_t)sizeof(KsLuaBuildFrame),
    (const void *)(uintptr_t)offsetof(KsLuaBuildFrame, kind),
    (const void *)(uintptr_t)offsetof(KsLuaBuildFrame, count),
    (const void *)ks_rt_raise,
    (const void *)ks_rt_raise_count,
    (const void *)ks_rt_raise_index,
    (const void *)ks_rt_bytes,
    (const void *)ks_rt_count,
    (const void *)ks_rt_index,
    (const void *)ks_rt_string_match,
    (const void *)ks_rt_string_length,
    (const void *)ks_rt_string_byte,
    (const void *)ks_rt_string_byte_lua,
    (const void *)ks_rt_string_u32,
    (const void *)ks_rt_substring,
    (const void *)ks_rt_table_number,
    (const void *)ks_rt_string_buffer_init,
    (const void *)ks_rt_string_buffer_append,
    (const void *)ks_rt_string_buffer_append_slice,
    (const void *)ks_rt_string_buffer_append_top,
    (const void *)ks_rt_string_buffer_finish,
    (const void *)ks_rt_scratch_u32,
    (const void *)ks_rt_scratch_u32_fixed,
    (const void *)ks_rt_scratch_u32_stack,
    (const void *)ks_rt_scratch_u32_get,
    (const void *)ks_rt_scratch_u32_get_fixed,
    (const void *)ks_rt_scratch_u32_escape_get,
    (const void *)ks_rt_scratch_u32_set,
    (const void *)ks_rt_scratch_u32_set_fixed,
    (const void *)ks_rt_scratch_u8,
    (const void *)ks_rt_scratch_u8_cached,
    (const void *)ks_rt_scratch_u8_stack,
    (const void *)ks_rt_scratch_u8_get,
    (const void *)ks_rt_scratch_u8_get_fixed,
    (const void *)ks_rt_scratch_u8_set,
    (const void *)ks_rt_scratch_u8_set_fixed,
    (const void *)ks_rt_scratch_u8_set4,
    (const void *)ks_rt_scratch_u8_set4_fixed,
    (const void *)ks_rt_scratch_u8_push,
    (const void *)ks_rt_builder_init,
    (const void *)ks_rt_builder_open,
    (const void *)ks_rt_builder_string,
    (const void *)ks_rt_builder_string_escapes,
    (const void *)ks_rt_builder_number_slice,
    (const void *)ks_rt_builder_integer_slice,
    (const void *)ks_rt_builder_number,
    (const void *)ks_rt_builder_integer64,
    (const void *)ks_rt_builder_decimal64,
    (const void *)ks_rt_builder_boolean,
    (const void *)ks_rt_builder_null,
    (const void *)ks_rt_builder_close,
    (const void *)ks_rt_builder_key_scratch,
    (const void *)ks_rt_builder_string_scratch,
    (const void *)ks_rt_builder_pushed_scalar,
    (const void *)ks_rt_builder_key,
    (const void *)ks_rt_builder_query,
    (const void *)ks_rt_builder_number_token,
    (const void *)ks_rt_builder_finish,
};
