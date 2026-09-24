/* The host runtime stand-in the LLVM spike used (direct-backend/src/
   luaphase.rs): restricted-signature wrappers around the C backend's
   ks_lua_* helpers, appended to the generated C. */
/* Host runtime stand-in: restricted-signature wrappers, no struct by value. */
int ks_rt_count(lua_State *L, double v, const char *site) { return ks_lua_count(L, v, site); }
int ks_rt_index(lua_State *L, double v, const char *site) { return ks_lua_index(L, v, site); }
int ks_rt_stack_error(lua_State *L) { return luaL_error(L, "AOT builder Lua stack exhausted"); }
size_t ks_rt_builder_size(void) { return sizeof(KsLuaBuilder); }
void ks_rt_eager_builder_new(KsLuaBuilder *out, lua_State *L, int null_index, int array_marker, int object_marker, uint32_t max_depth, uint32_t capacity) {
    *out = ks_lua_eager_builder_new(L, null_index, array_marker, object_marker, max_depth, capacity);
}
int ks_rt_builder_open(lua_State *L, KsLuaBuilder *b, uint32_t kind, uint32_t capacity, int eager) { return ks_lua_builder_open(L, b, kind, capacity, eager); }
int ks_rt_builder_string(lua_State *L, KsLuaBuilder *b, const unsigned char *s, size_t n, uint32_t start, uint32_t length, int escaped, int key, int eager) { return ks_lua_builder_string(L, b, s, n, start, length, escaped, key, eager); }
int ks_rt_builder_number_slice(lua_State *L, KsLuaBuilder *b, const unsigned char *s, size_t n, uint32_t start, uint32_t length, int eager) { return ks_lua_builder_number_slice(L, b, s, n, start, length, eager); }
int ks_rt_builder_boolean(lua_State *L, KsLuaBuilder *b, int value, int eager) { return ks_lua_builder_boolean(L, b, value, eager); }
int ks_rt_builder_close(lua_State *L, KsLuaBuilder *b, int eager) { return ks_lua_builder_close(L, b, eager); }
int ks_rt_builder_finish(lua_State *L, KsLuaBuilder *b) { return ks_lua_builder_finish(L, b); }
uint32_t ks_rt_string_byte(lua_State *L, const unsigned char *s, size_t n, uint32_t i) { return ks_lua_string_byte(L, s, n, i); }
uint32_t ks_rt_string_u32(lua_State *L, const unsigned char *s, size_t n, uint32_t i) { return ks_lua_string_u32(L, s, n, i); }
double ks_rt_sin(double x) { return nupp_sin(x); }
