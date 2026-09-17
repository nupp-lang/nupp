/* The stock Lua 5.1 host binding a Wasm kernel unit registers through.
 *
 * Appended after the kernels of a wasm32 unit: the Lua C API entry points
 * the closures call, the host's pointer and wide-integer bridges, and the
 * span-count check every closure shares. The closures themselves and the
 * registrar that installs them follow, written per program. */
typedef struct lua_State lua_State;
typedef int (*lua_CFunction)(lua_State *L);
extern double luaL_checknumber(lua_State *L, int narg);
extern int luaL_error(lua_State *L, const char *format, ...);
extern int lua_type(lua_State *L, int index);
extern int lua_toboolean(lua_State *L, int index);
extern void lua_getfield(lua_State *L, int index, const char *key);
extern void lua_setfield(lua_State *L, int index, const char *key);
extern void lua_createtable(lua_State *L, int narr, int nrec);
extern void lua_pushnumber(lua_State *L, double value);
extern void lua_pushboolean(lua_State *L, int value);
extern void lua_pushcclosure(lua_State *L, lua_CFunction function, int upvalues);
extern void lua_settop(lua_State *L, int index);
extern uint64_t nupp_wasm_wide_bits(lua_State *L, int index);
extern int nupp_wasm_push_wide(lua_State *L, uint64_t bits, int unsign);
extern void *nupp_wasm_write_pointer_address(lua_State *L, int index, size_t bytes);
extern void *nupp_wasm_pointer_address(lua_State *L, int index, size_t bytes);
#define KS_LUA_GLOBALSINDEX (-10002)
#define KS_LUA_TTABLE 5
static KS_UNUSED size_t ks_wasm_count(lua_State *L, int index, const char *name) {
    double value = luaL_checknumber(L, index);
    if (!(value >= 0.0) || value >= (double)SIZE_MAX || floor(value) != value)
        luaL_error(L, "Wasm AOT span count for %s is invalid", name);
    return (size_t)value;
}
