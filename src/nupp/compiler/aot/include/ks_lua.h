/* The Lua 5.1 interop prelude: what a Lua-callable AOT entry needs from the
 * host VM, and the value-stream builder that assembles Lua tables from a
 * compiled body's stream.
 *
 * Appended verbatim to generated C after ks_prelude.h. The Lua API surface is
 * declared here rather than taken from lua.h so `emit-c` output compiles without
 * locating development headers; these are the public ABI declarations, not
 * LuaJIT object layouts, and the artifact fingerprint names the ABI family.
 *
 * KS_JSON_WIDE, when defined, adds the 128-bit power-of-five table and the exact
 * decimal-to-binary64 path that uses it; a body that parses no wide decimal
 * leaves both out. */
#include <limits.h>
typedef struct lua_State lua_State;
typedef int (*lua_CFunction)(lua_State *L);
typedef struct { char *p; int level; lua_State *L; char bytes[BUFSIZ > 16384 ? 8192 : BUFSIZ]; } KsLuaStringBuffer;
extern int lua_checkstack(lua_State *L, int extra);
extern int lua_gettop(lua_State *L);
extern double luaL_checknumber(lua_State *L, int narg);
extern const char *luaL_checklstring(lua_State *L, int narg, size_t *length);
extern void luaL_buffinit(lua_State *L, KsLuaStringBuffer *buffer);
extern void luaL_addlstring(KsLuaStringBuffer *buffer, const char *bytes, size_t length);
extern void luaL_pushresult(KsLuaStringBuffer *buffer);
extern int lua_toboolean(lua_State *L, int index);
extern double lua_tonumber(lua_State *L, int index);
extern const char *lua_tolstring(lua_State *L, int index, size_t *length);
extern size_t lua_objlen(lua_State *L, int index);
extern const void *lua_topointer(lua_State *L, int index);
extern int lua_rawequal(lua_State *L, int first, int second);
extern int lua_getmetatable(lua_State *L, int index);
extern void lua_createtable(lua_State *L, int narr, int nrec);
extern void lua_pushnumber(lua_State *L, double value);
extern void lua_pushboolean(lua_State *L, int value);
extern void lua_pushnil(lua_State *L);
extern void lua_pushlightuserdata(lua_State *L, void *value);
extern void lua_pushlstring(lua_State *L, const char *value, size_t length);
extern void *lua_newuserdata(lua_State *L, size_t size);
extern void *lua_touserdata(lua_State *L, int index);
extern void lua_pushvalue(lua_State *L, int index);
extern void lua_concat(lua_State *L, int count);
extern void lua_replace(lua_State *L, int index);
extern void lua_insert(lua_State *L, int index);
extern void lua_remove(lua_State *L, int index);
extern void lua_settop(lua_State *L, int index);
extern int lua_setmetatable(lua_State *L, int index);
extern int lua_type(lua_State *L, int index);
extern void lua_pushcclosure(lua_State *L, lua_CFunction function, int upvalues);
extern void lua_rawseti(lua_State *L, int index, int key);
extern void lua_rawgeti(lua_State *L, int index, int key);
extern void lua_rawget(lua_State *L, int index);
extern void lua_rawset(lua_State *L, int index);
extern int lua_next(lua_State *L, int index);
extern void lua_getfield(lua_State *L, int index, const char *key);
extern void lua_call(lua_State *L, int arguments, int results);
extern int lua_equal(lua_State *L, int index1, int index2);
extern int luaL_error(lua_State *L, const char *format, ...);

static KS_UNUSED const unsigned char *ks_lua_bytes(lua_State *L, int index, size_t *length) {
    if (lua_type(L, index) == 4) { return (const unsigned char *)luaL_checklstring(L, index, length); }
    if (lua_type(L, index) != 5 && lua_type(L, index) != 7) { return (const unsigned char *)(uintptr_t)luaL_error(L, "string or nupp.text.Buffer expected"); }
    lua_getfield(L, index, "tostring"); if (lua_type(L, -1) != 6) { return (const unsigned char *)(uintptr_t)luaL_error(L, "buffer tostring method expected"); }
    lua_pushvalue(L, index); lua_call(L, 1, 1);
    if (lua_type(L, -1) != 4) { return (const unsigned char *)(uintptr_t)luaL_error(L, "buffer tostring must return a string"); }
    return (const unsigned char *)lua_tolstring(L, -1, length);
}

static KS_UNUSED int ks_lua_count(lua_State *L, double value, const char *what) {
    if (!(value >= 0.0) || value > (double)INT_MAX || floor(value) != value)
        return luaL_error(L, "AOT builder %s must be a nonnegative integer in C API range", what);
    return (int)value;
}
static int ks_lua_index(lua_State *L, double value, const char *site) {
    if (!(value >= 1.0) || value > (double)INT_MAX || floor(value) != value)
        return luaL_error(L, "AOT builder array index at %s must be a positive integer in C API range", site);
    return (int)value;
}
static KS_UNUSED double ks_lua_number_slice(lua_State *L, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, const char *what) {
    size_t first = (size_t)start, count = (size_t)length;
    if (first > source_length || count > source_length - first) { luaL_error(L, "AOT %s number range is out of bounds", what); return 0.0; }
    char *end = NULL; double value = strtod((const char *)(source + first), &end);
    if (end != (char *)(source + first + count)) { luaL_error(L, "AOT %s number is invalid", what); return 0.0; }
    return value;
}
static KS_UNUSED double ks_lua_integer_slice(lua_State *L, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length) {
    size_t first = (size_t)start, count = (size_t)length;
    if (first > source_length || count > source_length - first) { luaL_error(L, "AOT value stream integer range is out of bounds"); return 0.0; }
    size_t at = 0u; int negative = 0; uint64_t integer = 0u;
    if (at < count && source[first + at] == '-') { negative = 1; at += 1u; }
    size_t digits = at; while (at < count && source[first + at] >= '0' && source[first + at] <= '9' && at - digits < 15u) { integer = integer * 10u + (uint64_t)(source[first + at] - '0'); at += 1u; }
    if (at == count && at > digits) { double value = (double)integer; return negative ? -value : value; }
    return ks_lua_number_slice(L, source, source_length, start, length, "value stream integer");
}
#if defined(KS_JSON_WIDE)
/* Generated 128-bit significands for powers 5^-342 through 5^308. */
typedef struct { uint64_t low, high; } KsJsonU128;
static const uint64_t ks_json_power_of_five_128[1302] = {
0xeef453d6923bd65a,0x113faa2906a13b3f,
0x9558b4661b6565f8,0x4ac7ca59a424c507,
0xbaaee17fa23ebf76,0x5d79bcf00d2df649,
0xe95a99df8ace6f53,0xf4d82c2c107973dc,
0x91d8a02bb6c10594,0x79071b9b8a4be869,
0xb64ec836a47146f9,0x9748e2826cdee284,
0xe3e27a444d8d98b7,0xfd1b1b2308169b25,
0x8e6d8c6ab0787f72,0xfe30f0f5e50e20f7,
0xb208ef855c969f4f,0xbdbd2d335e51a935,
0xde8b2b66b3bc4723,0xad2c788035e61382,
0x8b16fb203055ac76,0x4c3bcb5021afcc31,
0xaddcb9e83c6b1793,0xdf4abe242a1bbf3d,
0xd953e8624b85dd78,0xd71d6dad34a2af0d,
0x87d4713d6f33aa6b,0x8672648c40e5ad68,
0xa9c98d8ccb009506,0x680efdaf511f18c2,
0xd43bf0effdc0ba48,0x212bd1b2566def2,
0x84a57695fe98746d,0x14bb630f7604b57,
0xa5ced43b7e3e9188,0x419ea3bd35385e2d,
0xcf42894a5dce35ea,0x52064cac828675b9,
0x818995ce7aa0e1b2,0x7343efebd1940993,
0xa1ebfb4219491a1f,0x1014ebe6c5f90bf8,
0xca66fa129f9b60a6,0xd41a26e077774ef6,
0xfd00b897478238d0,0x8920b098955522b4,
0x9e20735e8cb16382,0x55b46e5f5d5535b0,
0xc5a890362fddbc62,0xeb2189f734aa831d,
0xf712b443bbd52b7b,0xa5e9ec7501d523e4,
0x9a6bb0aa55653b2d,0x47b233c92125366e,
0xc1069cd4eabe89f8,0x999ec0bb696e840a,
0xf148440a256e2c76,0xc00670ea43ca250d,
0x96cd2a865764dbca,0x380406926a5e5728,
0xbc807527ed3e12bc,0xc605083704f5ecf2,
0xeba09271e88d976b,0xf7864a44c633682e,
0x93445b8731587ea3,0x7ab3ee6afbe0211d,
0xb8157268fdae9e4c,0x5960ea05bad82964,
0xe61acf033d1a45df,0x6fb92487298e33bd,
0x8fd0c16206306bab,0xa5d3b6d479f8e056,
0xb3c4f1ba87bc8696,0x8f48a4899877186c,
0xe0b62e2929aba83c,0x331acdabfe94de87,
0x8c71dcd9ba0b4925,0x9ff0c08b7f1d0b14,
0xaf8e5410288e1b6f,0x7ecf0ae5ee44dd9,
0xdb71e91432b1a24a,0xc9e82cd9f69d6150,
0x892731ac9faf056e,0xbe311c083a225cd2,
0xab70fe17c79ac6ca,0x6dbd630a48aaf406,
0xd64d3d9db981787d,0x92cbbccdad5b108,
0x85f0468293f0eb4e,0x25bbf56008c58ea5,
0xa76c582338ed2621,0xaf2af2b80af6f24e,
0xd1476e2c07286faa,0x1af5af660db4aee1,
0x82cca4db847945ca,0x50d98d9fc890ed4d,
0xa37fce126597973c,0xe50ff107bab528a0,
0xcc5fc196fefd7d0c,0x1e53ed49a96272c8,
0xff77b1fcbebcdc4f,0x25e8e89c13bb0f7a,
0x9faacf3df73609b1,0x77b191618c54e9ac,
0xc795830d75038c1d,0xd59df5b9ef6a2417,
0xf97ae3d0d2446f25,0x4b0573286b44ad1d,
0x9becce62836ac577,0x4ee367f9430aec32,
0xc2e801fb244576d5,0x229c41f793cda73f,
0xf3a20279ed56d48a,0x6b43527578c1110f,
0x9845418c345644d6,0x830a13896b78aaa9,
0xbe5691ef416bd60c,0x23cc986bc656d553,
0xedec366b11c6cb8f,0x2cbfbe86b7ec8aa8,
0x94b3a202eb1c3f39,0x7bf7d71432f3d6a9,
0xb9e08a83a5e34f07,0xdaf5ccd93fb0cc53,
0xe858ad248f5c22c9,0xd1b3400f8f9cff68,
0x91376c36d99995be,0x23100809b9c21fa1,
0xb58547448ffffb2d,0xabd40a0c2832a78a,
0xe2e69915b3fff9f9,0x16c90c8f323f516c,
0x8dd01fad907ffc3b,0xae3da7d97f6792e3,
0xb1442798f49ffb4a,0x99cd11cfdf41779c,
0xdd95317f31c7fa1d,0x40405643d711d583,
0x8a7d3eef7f1cfc52,0x482835ea666b2572,
0xad1c8eab5ee43b66,0xda3243650005eecf,
0xd863b256369d4a40,0x90bed43e40076a82,
0x873e4f75e2224e68,0x5a7744a6e804a291,
0xa90de3535aaae202,0x711515d0a205cb36,
0xd3515c2831559a83,0xd5a5b44ca873e03,
0x8412d9991ed58091,0xe858790afe9486c2,
0xa5178fff668ae0b6,0x626e974dbe39a872,
0xce5d73ff402d98e3,0xfb0a3d212dc8128f,
0x80fa687f881c7f8e,0x7ce66634bc9d0b99,
0xa139029f6a239f72,0x1c1fffc1ebc44e80,
0xc987434744ac874e,0xa327ffb266b56220,
0xfbe9141915d7a922,0x4bf1ff9f0062baa8,
0x9d71ac8fada6c9b5,0x6f773fc3603db4a9,
0xc4ce17b399107c22,0xcb550fb4384d21d3,
0xf6019da07f549b2b,0x7e2a53a146606a48,
0x99c102844f94e0fb,0x2eda7444cbfc426d,
0xc0314325637a1939,0xfa911155fefb5308,
0xf03d93eebc589f88,0x793555ab7eba27ca,
0x96267c7535b763b5,0x4bc1558b2f3458de,
0xbbb01b9283253ca2,0x9eb1aaedfb016f16,
0xea9c227723ee8bcb,0x465e15a979c1cadc,
0x92a1958a7675175f,0xbfacd89ec191ec9,
0xb749faed14125d36,0xcef980ec671f667b,
0xe51c79a85916f484,0x82b7e12780e7401a,
0x8f31cc0937ae58d2,0xd1b2ecb8b0908810,
0xb2fe3f0b8599ef07,0x861fa7e6dcb4aa15,
0xdfbdcece67006ac9,0x67a791e093e1d49a,
0x8bd6a141006042bd,0xe0c8bb2c5c6d24e0,
0xaecc49914078536d,0x58fae9f773886e18,
0xda7f5bf590966848,0xaf39a475506a899e,
0x888f99797a5e012d,0x6d8406c952429603,
0xaab37fd7d8f58178,0xc8e5087ba6d33b83,
0xd5605fcdcf32e1d6,0xfb1e4a9a90880a64,
0x855c3be0a17fcd26,0x5cf2eea09a55067f,
0xa6b34ad8c9dfc06f,0xf42faa48c0ea481e,
0xd0601d8efc57b08b,0xf13b94daf124da26,
0x823c12795db6ce57,0x76c53d08d6b70858,
0xa2cb1717b52481ed,0x54768c4b0c64ca6e,
0xcb7ddcdda26da268,0xa9942f5dcf7dfd09,
0xfe5d54150b090b02,0xd3f93b35435d7c4c,
0x9efa548d26e5a6e1,0xc47bc5014a1a6daf,
0xc6b8e9b0709f109a,0x359ab6419ca1091b,
0xf867241c8cc6d4c0,0xc30163d203c94b62,
0x9b407691d7fc44f8,0x79e0de63425dcf1d,
0xc21094364dfb5636,0x985915fc12f542e4,
0xf294b943e17a2bc4,0x3e6f5b7b17b2939d,
0x979cf3ca6cec5b5a,0xa705992ceecf9c42,
0xbd8430bd08277231,0x50c6ff782a838353,
0xece53cec4a314ebd,0xa4f8bf5635246428,
0x940f4613ae5ed136,0x871b7795e136be99,
0xb913179899f68584,0x28e2557b59846e3f,
0xe757dd7ec07426e5,0x331aeada2fe589cf,
0x9096ea6f3848984f,0x3ff0d2c85def7621,
0xb4bca50b065abe63,0xfed077a756b53a9,
0xe1ebce4dc7f16dfb,0xd3e8495912c62894,
0x8d3360f09cf6e4bd,0x64712dd7abbbd95c,
0xb080392cc4349dec,0xbd8d794d96aacfb3,
0xdca04777f541c567,0xecf0d7a0fc5583a0,
0x89e42caaf9491b60,0xf41686c49db57244,
0xac5d37d5b79b6239,0x311c2875c522ced5,
0xd77485cb25823ac7,0x7d633293366b828b,
0x86a8d39ef77164bc,0xae5dff9c02033197,
0xa8530886b54dbdeb,0xd9f57f830283fdfc,
0xd267caa862a12d66,0xd072df63c324fd7b,
0x8380dea93da4bc60,0x4247cb9e59f71e6d,
0xa46116538d0deb78,0x52d9be85f074e608,
0xcd795be870516656,0x67902e276c921f8b,
0x806bd9714632dff6,0xba1cd8a3db53b6,
0xa086cfcd97bf97f3,0x80e8a40eccd228a4,
0xc8a883c0fdaf7df0,0x6122cd128006b2cd,
0xfad2a4b13d1b5d6c,0x796b805720085f81,
0x9cc3a6eec6311a63,0xcbe3303674053bb0,
0xc3f490aa77bd60fc,0xbedbfc4411068a9c,
0xf4f1b4d515acb93b,0xee92fb5515482d44,
0x991711052d8bf3c5,0x751bdd152d4d1c4a,
0xbf5cd54678eef0b6,0xd262d45a78a0635d,
0xef340a98172aace4,0x86fb897116c87c34,
0x9580869f0e7aac0e,0xd45d35e6ae3d4da0,
0xbae0a846d2195712,0x8974836059cca109,
0xe998d258869facd7,0x2bd1a438703fc94b,
0x91ff83775423cc06,0x7b6306a34627ddcf,
0xb67f6455292cbf08,0x1a3bc84c17b1d542,
0xe41f3d6a7377eeca,0x20caba5f1d9e4a93,
0x8e938662882af53e,0x547eb47b7282ee9c,
0xb23867fb2a35b28d,0xe99e619a4f23aa43,
0xdec681f9f4c31f31,0x6405fa00e2ec94d4,
0x8b3c113c38f9f37e,0xde83bc408dd3dd04,
0xae0b158b4738705e,0x9624ab50b148d445,
0xd98ddaee19068c76,0x3badd624dd9b0957,
0x87f8a8d4cfa417c9,0xe54ca5d70a80e5d6,
0xa9f6d30a038d1dbc,0x5e9fcf4ccd211f4c,
0xd47487cc8470652b,0x7647c3200069671f,
0x84c8d4dfd2c63f3b,0x29ecd9f40041e073,
0xa5fb0a17c777cf09,0xf468107100525890,
0xcf79cc9db955c2cc,0x7182148d4066eeb4,
0x81ac1fe293d599bf,0xc6f14cd848405530,
0xa21727db38cb002f,0xb8ada00e5a506a7c,
0xca9cf1d206fdc03b,0xa6d90811f0e4851c,
0xfd442e4688bd304a,0x908f4a166d1da663,
0x9e4a9cec15763e2e,0x9a598e4e043287fe,
0xc5dd44271ad3cdba,0x40eff1e1853f29fd,
0xf7549530e188c128,0xd12bee59e68ef47c,
0x9a94dd3e8cf578b9,0x82bb74f8301958ce,
0xc13a148e3032d6e7,0xe36a52363c1faf01,
0xf18899b1bc3f8ca1,0xdc44e6c3cb279ac1,
0x96f5600f15a7b7e5,0x29ab103a5ef8c0b9,
0xbcb2b812db11a5de,0x7415d448f6b6f0e7,
0xebdf661791d60f56,0x111b495b3464ad21,
0x936b9fcebb25c995,0xcab10dd900beec34,
0xb84687c269ef3bfb,0x3d5d514f40eea742,
0xe65829b3046b0afa,0xcb4a5a3112a5112,
0x8ff71a0fe2c2e6dc,0x47f0e785eaba72ab,
0xb3f4e093db73a093,0x59ed216765690f56,
0xe0f218b8d25088b8,0x306869c13ec3532c,
0x8c974f7383725573,0x1e414218c73a13fb,
0xafbd2350644eeacf,0xe5d1929ef90898fa,
0xdbac6c247d62a583,0xdf45f746b74abf39,
0x894bc396ce5da772,0x6b8bba8c328eb783,
0xab9eb47c81f5114f,0x66ea92f3f326564,
0xd686619ba27255a2,0xc80a537b0efefebd,
0x8613fd0145877585,0xbd06742ce95f5f36,
0xa798fc4196e952e7,0x2c48113823b73704,
0xd17f3b51fca3a7a0,0xf75a15862ca504c5,
0x82ef85133de648c4,0x9a984d73dbe722fb,
0xa3ab66580d5fdaf5,0xc13e60d0d2e0ebba,
0xcc963fee10b7d1b3,0x318df905079926a8,
0xffbbcfe994e5c61f,0xfdf17746497f7052,
0x9fd561f1fd0f9bd3,0xfeb6ea8bedefa633,
0xc7caba6e7c5382c8,0xfe64a52ee96b8fc0,
0xf9bd690a1b68637b,0x3dfdce7aa3c673b0,
0x9c1661a651213e2d,0x6bea10ca65c084e,
0xc31bfa0fe5698db8,0x486e494fcff30a62,
0xf3e2f893dec3f126,0x5a89dba3c3efccfa,
0x986ddb5c6b3a76b7,0xf89629465a75e01c,
0xbe89523386091465,0xf6bbb397f1135823,
0xee2ba6c0678b597f,0x746aa07ded582e2c,
0x94db483840b717ef,0xa8c2a44eb4571cdc,
0xba121a4650e4ddeb,0x92f34d62616ce413,
0xe896a0d7e51e1566,0x77b020baf9c81d17,
0x915e2486ef32cd60,0xace1474dc1d122e,
0xb5b5ada8aaff80b8,0xd819992132456ba,
0xe3231912d5bf60e6,0x10e1fff697ed6c69,
0x8df5efabc5979c8f,0xca8d3ffa1ef463c1,
0xb1736b96b6fd83b3,0xbd308ff8a6b17cb2,
0xddd0467c64bce4a0,0xac7cb3f6d05ddbde,
0x8aa22c0dbef60ee4,0x6bcdf07a423aa96b,
0xad4ab7112eb3929d,0x86c16c98d2c953c6,
0xd89d64d57a607744,0xe871c7bf077ba8b7,
0x87625f056c7c4a8b,0x11471cd764ad4972,
0xa93af6c6c79b5d2d,0xd598e40d3dd89bcf,
0xd389b47879823479,0x4aff1d108d4ec2c3,
0x843610cb4bf160cb,0xcedf722a585139ba,
0xa54394fe1eedb8fe,0xc2974eb4ee658828,
0xce947a3da6a9273e,0x733d226229feea32,
0x811ccc668829b887,0x806357d5a3f525f,
0xa163ff802a3426a8,0xca07c2dcb0cf26f7,
0xc9bcff6034c13052,0xfc89b393dd02f0b5,
0xfc2c3f3841f17c67,0xbbac2078d443ace2,
0x9d9ba7832936edc0,0xd54b944b84aa4c0d,
0xc5029163f384a931,0xa9e795e65d4df11,
0xf64335bcf065d37d,0x4d4617b5ff4a16d5,
0x99ea0196163fa42e,0x504bced1bf8e4e45,
0xc06481fb9bcf8d39,0xe45ec2862f71e1d6,
0xf07da27a82c37088,0x5d767327bb4e5a4c,
0x964e858c91ba2655,0x3a6a07f8d510f86f,
0xbbe226efb628afea,0x890489f70a55368b,
0xeadab0aba3b2dbe5,0x2b45ac74ccea842e,
0x92c8ae6b464fc96f,0x3b0b8bc90012929d,
0xb77ada0617e3bbcb,0x9ce6ebb40173744,
0xe55990879ddcaabd,0xcc420a6a101d0515,
0x8f57fa54c2a9eab6,0x9fa946824a12232d,
0xb32df8e9f3546564,0x47939822dc96abf9,
0xdff9772470297ebd,0x59787e2b93bc56f7,
0x8bfbea76c619ef36,0x57eb4edb3c55b65a,
0xaefae51477a06b03,0xede622920b6b23f1,
0xdab99e59958885c4,0xe95fab368e45eced,
0x88b402f7fd75539b,0x11dbcb0218ebb414,
0xaae103b5fcd2a881,0xd652bdc29f26a119,
0xd59944a37c0752a2,0x4be76d3346f0495f,
0x857fcae62d8493a5,0x6f70a4400c562ddb,
0xa6dfbd9fb8e5b88e,0xcb4ccd500f6bb952,
0xd097ad07a71f26b2,0x7e2000a41346a7a7,
0x825ecc24c873782f,0x8ed400668c0c28c8,
0xa2f67f2dfa90563b,0x728900802f0f32fa,
0xcbb41ef979346bca,0x4f2b40a03ad2ffb9,
0xfea126b7d78186bc,0xe2f610c84987bfa8,
0x9f24b832e6b0f436,0xdd9ca7d2df4d7c9,
0xc6ede63fa05d3143,0x91503d1c79720dbb,
0xf8a95fcf88747d94,0x75a44c6397ce912a,
0x9b69dbe1b548ce7c,0xc986afbe3ee11aba,
0xc24452da229b021b,0xfbe85badce996168,
0xf2d56790ab41c2a2,0xfae27299423fb9c3,
0x97c560ba6b0919a5,0xdccd879fc967d41a,
0xbdb6b8e905cb600f,0x5400e987bbc1c920,
0xed246723473e3813,0x290123e9aab23b68,
0x9436c0760c86e30b,0xf9a0b6720aaf6521,
0xb94470938fa89bce,0xf808e40e8d5b3e69,
0xe7958cb87392c2c2,0xb60b1d1230b20e04,
0x90bd77f3483bb9b9,0xb1c6f22b5e6f48c2,
0xb4ecd5f01a4aa828,0x1e38aeb6360b1af3,
0xe2280b6c20dd5232,0x25c6da63c38de1b0,
0x8d590723948a535f,0x579c487e5a38ad0e,
0xb0af48ec79ace837,0x2d835a9df0c6d851,
0xdcdb1b2798182244,0xf8e431456cf88e65,
0x8a08f0f8bf0f156b,0x1b8e9ecb641b58ff,
0xac8b2d36eed2dac5,0xe272467e3d222f3f,
0xd7adf884aa879177,0x5b0ed81dcc6abb0f,
0x86ccbb52ea94baea,0x98e947129fc2b4e9,
0xa87fea27a539e9a5,0x3f2398d747b36224,
0xd29fe4b18e88640e,0x8eec7f0d19a03aad,
0x83a3eeeef9153e89,0x1953cf68300424ac,
0xa48ceaaab75a8e2b,0x5fa8c3423c052dd7,
0xcdb02555653131b6,0x3792f412cb06794d,
0x808e17555f3ebf11,0xe2bbd88bbee40bd0,
0xa0b19d2ab70e6ed6,0x5b6aceaeae9d0ec4,
0xc8de047564d20a8b,0xf245825a5a445275,
0xfb158592be068d2e,0xeed6e2f0f0d56712,
0x9ced737bb6c4183d,0x55464dd69685606b,
0xc428d05aa4751e4c,0xaa97e14c3c26b886,
0xf53304714d9265df,0xd53dd99f4b3066a8,
0x993fe2c6d07b7fab,0xe546a8038efe4029,
0xbf8fdb78849a5f96,0xde98520472bdd033,
0xef73d256a5c0f77c,0x963e66858f6d4440,
0x95a8637627989aad,0xdde7001379a44aa8,
0xbb127c53b17ec159,0x5560c018580d5d52,
0xe9d71b689dde71af,0xaab8f01e6e10b4a6,
0x9226712162ab070d,0xcab3961304ca70e8,
0xb6b00d69bb55c8d1,0x3d607b97c5fd0d22,
0xe45c10c42a2b3b05,0x8cb89a7db77c506a,
0x8eb98a7a9a5b04e3,0x77f3608e92adb242,
0xb267ed1940f1c61c,0x55f038b237591ed3,
0xdf01e85f912e37a3,0x6b6c46dec52f6688,
0x8b61313bbabce2c6,0x2323ac4b3b3da015,
0xae397d8aa96c1b77,0xabec975e0a0d081a,
0xd9c7dced53c72255,0x96e7bd358c904a21,
0x881cea14545c7575,0x7e50d64177da2e54,
0xaa242499697392d2,0xdde50bd1d5d0b9e9,
0xd4ad2dbfc3d07787,0x955e4ec64b44e864,
0x84ec3c97da624ab4,0xbd5af13bef0b113e,
0xa6274bbdd0fadd61,0xecb1ad8aeacdd58e,
0xcfb11ead453994ba,0x67de18eda5814af2,
0x81ceb32c4b43fcf4,0x80eacf948770ced7,
0xa2425ff75e14fc31,0xa1258379a94d028d,
0xcad2f7f5359a3b3e,0x96ee45813a04330,
0xfd87b5f28300ca0d,0x8bca9d6e188853fc,
0x9e74d1b791e07e48,0x775ea264cf55347e,
0xc612062576589dda,0x95364afe032a81a0,
0xf79687aed3eec551,0x3a83ddbd83f52210,
0x9abe14cd44753b52,0xc4926a9672793580,
0xc16d9a0095928a27,0x75b7053c0f178400,
0xf1c90080baf72cb1,0x5324c68b12dd6800,
0x971da05074da7bee,0xd3f6fc16ebca8000,
0xbce5086492111aea,0x88f4bb1ca6bd0000,
0xec1e4a7db69561a5,0x2b31e9e3d0700000,
0x9392ee8e921d5d07,0x3aff322e62600000,
0xb877aa3236a4b449,0x9befeb9fad487c3,
0xe69594bec44de15b,0x4c2ebe687989a9b4,
0x901d7cf73ab0acd9,0xf9d37014bf60a11,
0xb424dc35095cd80f,0x538484c19ef38c95,
0xe12e13424bb40e13,0x2865a5f206b06fba,
0x8cbccc096f5088cb,0xf93f87b7442e45d4,
0xafebff0bcb24aafe,0xf78f69a51539d749,
0xdbe6fecebdedd5be,0xb573440e5a884d1c,
0x89705f4136b4a597,0x31680a88f8953031,
0xabcc77118461cefc,0xfdc20d2b36ba7c3e,
0xd6bf94d5e57a42bc,0x3d32907604691b4d,
0x8637bd05af6c69b5,0xa63f9a49c2c1b110,
0xa7c5ac471b478423,0xfcf80dc33721d54,
0xd1b71758e219652b,0xd3c36113404ea4a9,
0x83126e978d4fdf3b,0x645a1cac083126ea,
0xa3d70a3d70a3d70a,0x3d70a3d70a3d70a4,
0xcccccccccccccccc,0xcccccccccccccccd,
0x8000000000000000,0x0,
0xa000000000000000,0x0,
0xc800000000000000,0x0,
0xfa00000000000000,0x0,
0x9c40000000000000,0x0,
0xc350000000000000,0x0,
0xf424000000000000,0x0,
0x9896800000000000,0x0,
0xbebc200000000000,0x0,
0xee6b280000000000,0x0,
0x9502f90000000000,0x0,
0xba43b74000000000,0x0,
0xe8d4a51000000000,0x0,
0x9184e72a00000000,0x0,
0xb5e620f480000000,0x0,
0xe35fa931a0000000,0x0,
0x8e1bc9bf04000000,0x0,
0xb1a2bc2ec5000000,0x0,
0xde0b6b3a76400000,0x0,
0x8ac7230489e80000,0x0,
0xad78ebc5ac620000,0x0,
0xd8d726b7177a8000,0x0,
0x878678326eac9000,0x0,
0xa968163f0a57b400,0x0,
0xd3c21bcecceda100,0x0,
0x84595161401484a0,0x0,
0xa56fa5b99019a5c8,0x0,
0xcecb8f27f4200f3a,0x0,
0x813f3978f8940984,0x4000000000000000,
0xa18f07d736b90be5,0x5000000000000000,
0xc9f2c9cd04674ede,0xa400000000000000,
0xfc6f7c4045812296,0x4d00000000000000,
0x9dc5ada82b70b59d,0xf020000000000000,
0xc5371912364ce305,0x6c28000000000000,
0xf684df56c3e01bc6,0xc732000000000000,
0x9a130b963a6c115c,0x3c7f400000000000,
0xc097ce7bc90715b3,0x4b9f100000000000,
0xf0bdc21abb48db20,0x1e86d40000000000,
0x96769950b50d88f4,0x1314448000000000,
0xbc143fa4e250eb31,0x17d955a000000000,
0xeb194f8e1ae525fd,0x5dcfab0800000000,
0x92efd1b8d0cf37be,0x5aa1cae500000000,
0xb7abc627050305ad,0xf14a3d9e40000000,
0xe596b7b0c643c719,0x6d9ccd05d0000000,
0x8f7e32ce7bea5c6f,0xe4820023a2000000,
0xb35dbf821ae4f38b,0xdda2802c8a800000,
0xe0352f62a19e306e,0xd50b2037ad200000,
0x8c213d9da502de45,0x4526f422cc340000,
0xaf298d050e4395d6,0x9670b12b7f410000,
0xdaf3f04651d47b4c,0x3c0cdd765f114000,
0x88d8762bf324cd0f,0xa5880a69fb6ac800,
0xab0e93b6efee0053,0x8eea0d047a457a00,
0xd5d238a4abe98068,0x72a4904598d6d880,
0x85a36366eb71f041,0x47a6da2b7f864750,
0xa70c3c40a64e6c51,0x999090b65f67d924,
0xd0cf4b50cfe20765,0xfff4b4e3f741cf6d,
0x82818f1281ed449f,0xbff8f10e7a8921a4,
0xa321f2d7226895c7,0xaff72d52192b6a0d,
0xcbea6f8ceb02bb39,0x9bf4f8a69f764490,
0xfee50b7025c36a08,0x2f236d04753d5b4,
0x9f4f2726179a2245,0x1d762422c946590,
0xc722f0ef9d80aad6,0x424d3ad2b7b97ef5,
0xf8ebad2b84e0d58b,0xd2e0898765a7deb2,
0x9b934c3b330c8577,0x63cc55f49f88eb2f,
0xc2781f49ffcfa6d5,0x3cbf6b71c76b25fb,
0xf316271c7fc3908a,0x8bef464e3945ef7a,
0x97edd871cfda3a56,0x97758bf0e3cbb5ac,
0xbde94e8e43d0c8ec,0x3d52eeed1cbea317,
0xed63a231d4c4fb27,0x4ca7aaa863ee4bdd,
0x945e455f24fb1cf8,0x8fe8caa93e74ef6a,
0xb975d6b6ee39e436,0xb3e2fd538e122b44,
0xe7d34c64a9c85d44,0x60dbbca87196b616,
0x90e40fbeea1d3a4a,0xbc8955e946fe31cd,
0xb51d13aea4a488dd,0x6babab6398bdbe41,
0xe264589a4dcdab14,0xc696963c7eed2dd1,
0x8d7eb76070a08aec,0xfc1e1de5cf543ca2,
0xb0de65388cc8ada8,0x3b25a55f43294bcb,
0xdd15fe86affad912,0x49ef0eb713f39ebe,
0x8a2dbf142dfcc7ab,0x6e3569326c784337,
0xacb92ed9397bf996,0x49c2c37f07965404,
0xd7e77a8f87daf7fb,0xdc33745ec97be906,
0x86f0ac99b4e8dafd,0x69a028bb3ded71a3,
0xa8acd7c0222311bc,0xc40832ea0d68ce0c,
0xd2d80db02aabd62b,0xf50a3fa490c30190,
0x83c7088e1aab65db,0x792667c6da79e0fa,
0xa4b8cab1a1563f52,0x577001b891185938,
0xcde6fd5e09abcf26,0xed4c0226b55e6f86,
0x80b05e5ac60b6178,0x544f8158315b05b4,
0xa0dc75f1778e39d6,0x696361ae3db1c721,
0xc913936dd571c84c,0x3bc3a19cd1e38e9,
0xfb5878494ace3a5f,0x4ab48a04065c723,
0x9d174b2dcec0e47b,0x62eb0d64283f9c76,
0xc45d1df942711d9a,0x3ba5d0bd324f8394,
0xf5746577930d6500,0xca8f44ec7ee36479,
0x9968bf6abbe85f20,0x7e998b13cf4e1ecb,
0xbfc2ef456ae276e8,0x9e3fedd8c321a67e,
0xefb3ab16c59b14a2,0xc5cfe94ef3ea101e,
0x95d04aee3b80ece5,0xbba1f1d158724a12,
0xbb445da9ca61281f,0x2a8a6e45ae8edc97,
0xea1575143cf97226,0xf52d09d71a3293bd,
0x924d692ca61be758,0x593c2626705f9c56,
0xb6e0c377cfa2e12e,0x6f8b2fb00c77836c,
0xe498f455c38b997a,0xb6dfb9c0f956447,
0x8edf98b59a373fec,0x4724bd4189bd5eac,
0xb2977ee300c50fe7,0x58edec91ec2cb657,
0xdf3d5e9bc0f653e1,0x2f2967b66737e3ed,
0x8b865b215899f46c,0xbd79e0d20082ee74,
0xae67f1e9aec07187,0xecd8590680a3aa11,
0xda01ee641a708de9,0xe80e6f4820cc9495,
0x884134fe908658b2,0x3109058d147fdcdd,
0xaa51823e34a7eede,0xbd4b46f0599fd415,
0xd4e5e2cdc1d1ea96,0x6c9e18ac7007c91a,
0x850fadc09923329e,0x3e2cf6bc604ddb0,
0xa6539930bf6bff45,0x84db8346b786151c,
0xcfe87f7cef46ff16,0xe612641865679a63,
0x81f14fae158c5f6e,0x4fcb7e8f3f60c07e,
0xa26da3999aef7749,0xe3be5e330f38f09d,
0xcb090c8001ab551c,0x5cadf5bfd3072cc5,
0xfdcb4fa002162a63,0x73d9732fc7c8f7f6,
0x9e9f11c4014dda7e,0x2867e7fddcdd9afa,
0xc646d63501a1511d,0xb281e1fd541501b8,
0xf7d88bc24209a565,0x1f225a7ca91a4226,
0x9ae757596946075f,0x3375788de9b06958,
0xc1a12d2fc3978937,0x52d6b1641c83ae,
0xf209787bb47d6b84,0xc0678c5dbd23a49a,
0x9745eb4d50ce6332,0xf840b7ba963646e0,
0xbd176620a501fbff,0xb650e5a93bc3d898,
0xec5d3fa8ce427aff,0xa3e51f138ab4cebe,
0x93ba47c980e98cdf,0xc66f336c36b10137,
0xb8a8d9bbe123f017,0xb80b0047445d4184,
0xe6d3102ad96cec1d,0xa60dc059157491e5,
0x9043ea1ac7e41392,0x87c89837ad68db2f,
0xb454e4a179dd1877,0x29babe4598c311fb,
0xe16a1dc9d8545e94,0xf4296dd6fef3d67a,
0x8ce2529e2734bb1d,0x1899e4a65f58660c,
0xb01ae745b101e9e4,0x5ec05dcff72e7f8f,
0xdc21a1171d42645d,0x76707543f4fa1f73,
0x899504ae72497eba,0x6a06494a791c53a8,
0xabfa45da0edbde69,0x487db9d17636892,
0xd6f8d7509292d603,0x45a9d2845d3c42b6,
0x865b86925b9bc5c2,0xb8a2392ba45a9b2,
0xa7f26836f282b732,0x8e6cac7768d7141e,
0xd1ef0244af2364ff,0x3207d795430cd926,
0x8335616aed761f1f,0x7f44e6bd49e807b8,
0xa402b9c5a8d3a6e7,0x5f16206c9c6209a6,
0xcd036837130890a1,0x36dba887c37a8c0f,
0x802221226be55a64,0xc2494954da2c9789,
0xa02aa96b06deb0fd,0xf2db9baa10b7bd6c,
0xc83553c5c8965d3d,0x6f92829494e5acc7,
0xfa42a8b73abbf48c,0xcb772339ba1f17f9,
0x9c69a97284b578d7,0xff2a760414536efb,
0xc38413cf25e2d70d,0xfef5138519684aba,
0xf46518c2ef5b8cd1,0x7eb258665fc25d69,
0x98bf2f79d5993802,0xef2f773ffbd97a61,
0xbeeefb584aff8603,0xaafb550ffacfd8fa,
0xeeaaba2e5dbf6784,0x95ba2a53f983cf38,
0x952ab45cfa97a0b2,0xdd945a747bf26183,
0xba756174393d88df,0x94f971119aeef9e4,
0xe912b9d1478ceb17,0x7a37cd5601aab85d,
0x91abb422ccb812ee,0xac62e055c10ab33a,
0xb616a12b7fe617aa,0x577b986b314d6009,
0xe39c49765fdf9d94,0xed5a7e85fda0b80b,
0x8e41ade9fbebc27d,0x14588f13be847307,
0xb1d219647ae6b31c,0x596eb2d8ae258fc8,
0xde469fbd99a05fe3,0x6fca5f8ed9aef3bb,
0x8aec23d680043bee,0x25de7bb9480d5854,
0xada72ccc20054ae9,0xaf561aa79a10ae6a,
0xd910f7ff28069da4,0x1b2ba1518094da04,
0x87aa9aff79042286,0x90fb44d2f05d0842,
0xa99541bf57452b28,0x353a1607ac744a53,
0xd3fa922f2d1675f2,0x42889b8997915ce8,
0x847c9b5d7c2e09b7,0x69956135febada11,
0xa59bc234db398c25,0x43fab9837e699095,
0xcf02b2c21207ef2e,0x94f967e45e03f4bb,
0x8161afb94b44f57d,0x1d1be0eebac278f5,
0xa1ba1ba79e1632dc,0x6462d92a69731732,
0xca28a291859bbf93,0x7d7b8f7503cfdcfe,
0xfcb2cb35e702af78,0x5cda735244c3d43e,
0x9defbf01b061adab,0x3a0888136afa64a7,
0xc56baec21c7a1916,0x88aaa1845b8fdd0,
0xf6c69a72a3989f5b,0x8aad549e57273d45,
0x9a3c2087a63f6399,0x36ac54e2f678864b,
0xc0cb28a98fcf3c7f,0x84576a1bb416a7dd,
0xf0fdf2d3f3c30b9f,0x656d44a2a11c51d5,
0x969eb7c47859e743,0x9f644ae5a4b1b325,
0xbc4665b596706114,0x873d5d9f0dde1fee,
0xeb57ff22fc0c7959,0xa90cb506d155a7ea,
0x9316ff75dd87cbd8,0x9a7f12442d588f2,
0xb7dcbf5354e9bece,0xc11ed6d538aeb2f,
0xe5d3ef282a242e81,0x8f1668c8a86da5fa,
0x8fa475791a569d10,0xf96e017d694487bc,
0xb38d92d760ec4455,0x37c981dcc395a9ac,
0xe070f78d3927556a,0x85bbe253f47b1417,
0x8c469ab843b89562,0x93956d7478ccec8e,
0xaf58416654a6babb,0x387ac8d1970027b2,
0xdb2e51bfe9d0696a,0x6997b05fcc0319e,
0x88fcf317f22241e2,0x441fece3bdf81f03,
0xab3c2fddeeaad25a,0xd527e81cad7626c3,
0xd60b3bd56a5586f1,0x8a71e223d8d3b074,
0x85c7056562757456,0xf6872d5667844e49,
0xa738c6bebb12d16c,0xb428f8ac016561db,
0xd106f86e69d785c7,0xe13336d701beba52,
0x82a45b450226b39c,0xecc0024661173473,
0xa34d721642b06084,0x27f002d7f95d0190,
0xcc20ce9bd35c78a5,0x31ec038df7b441f4,
0xff290242c83396ce,0x7e67047175a15271,
0x9f79a169bd203e41,0xf0062c6e984d386,
0xc75809c42c684dd1,0x52c07b78a3e60868,
0xf92e0c3537826145,0xa7709a56ccdf8a82,
0x9bbcc7a142b17ccb,0x88a66076400bb691,
0xc2abf989935ddbfe,0x6acff893d00ea435,
0xf356f7ebf83552fe,0x583f6b8c4124d43,
0x98165af37b2153de,0xc3727a337a8b704a,
0xbe1bf1b059e9a8d6,0x744f18c0592e4c5c,
0xeda2ee1c7064130c,0x1162def06f79df73,
0x9485d4d1c63e8be7,0x8addcb5645ac2ba8,
0xb9a74a0637ce2ee1,0x6d953e2bd7173692,
0xe8111c87c5c1ba99,0xc8fa8db6ccdd0437,
0x910ab1d4db9914a0,0x1d9c9892400a22a2,
0xb54d5e4a127f59c8,0x2503beb6d00cab4b,
0xe2a0b5dc971f303a,0x2e44ae64840fd61d,
0x8da471a9de737e24,0x5ceaecfed289e5d2,
0xb10d8e1456105dad,0x7425a83e872c5f47,
0xdd50f1996b947518,0xd12f124e28f77719,
0x8a5296ffe33cc92f,0x82bd6b70d99aaa6f,
0xace73cbfdc0bfb7b,0x636cc64d1001550b,
0xd8210befd30efa5a,0x3c47f7e05401aa4e,
0x8714a775e3e95c78,0x65acfaec34810a71,
0xa8d9d1535ce3b396,0x7f1839a741a14d0d,
0xd31045a8341ca07c,0x1ede48111209a050,
0x83ea2b892091e44d,0x934aed0aab460432,
0xa4e4b66b68b65d60,0xf81da84d5617853f,
0xce1de40642e3f4b9,0x36251260ab9d668e,
0x80d2ae83e9ce78f3,0xc1d72b7c6b426019,
0xa1075a24e4421730,0xb24cf65b8612f81f,
0xc94930ae1d529cfc,0xdee033f26797b627,
0xfb9b7cd9a4a7443c,0x169840ef017da3b1,
0x9d412e0806e88aa5,0x8e1f289560ee864e,
0xc491798a08a2ad4e,0xf1a6f2bab92a27e2,
0xf5b5d7ec8acb58a2,0xae10af696774b1db,
0x9991a6f3d6bf1765,0xacca6da1e0a8ef29,
0xbff610b0cc6edd3f,0x17fd090a58d32af3,
0xeff394dcff8a948e,0xddfc4b4cef07f5b0,
0x95f83d0a1fb69cd9,0x4abdaf101564f98e,
0xbb764c4ca7a4440f,0x9d6d1ad41abe37f1,
0xea53df5fd18d5513,0x84c86189216dc5ed,
0x92746b9be2f8552c,0x32fd3cf5b4e49bb4,
0xb7118682dbb66a77,0x3fbc8c33221dc2a1,
0xe4d5e82392a40515,0xfabaf3feaa5334a,
0x8f05b1163ba6832d,0x29cb4d87f2a7400e,
0xb2c71d5bca9023f8,0x743e20e9ef511012,
0xdf78e4b2bd342cf6,0x914da9246b255416,
0x8bab8eefb6409c1a,0x1ad089b6c2f7548e,
0xae9672aba3d0c320,0xa184ac2473b529b1,
0xda3c0f568cc4f3e8,0xc9e5d72d90a2741e,
0x8865899617fb1871,0x7e2fa67c7a658892,
0xaa7eebfb9df9de8d,0xddbb901b98feeab7,
0xd51ea6fa85785631,0x552a74227f3ea565,
0x8533285c936b35de,0xd53a88958f87275f,
0xa67ff273b8460356,0x8a892abaf368f137,
0xd01fef10a657842c,0x2d2b7569b0432d85,
0x8213f56a67f6b29b,0x9c3b29620e29fc73,
0xa298f2c501f45f42,0x8349f3ba91b47b8f,
0xcb3f2f7642717713,0x241c70a936219a73,
0xfe0efb53d30dd4d7,0xed238cd383aa0110,
0x9ec95d1463e8a506,0xf4363804324a40aa,
0xc67bb4597ce2ce48,0xb143c6053edcd0d5,
0xf81aa16fdc1b81da,0xdd94b7868e94050a,
0x9b10a4e5e9913128,0xca7cf2b4191c8326,
0xc1d4ce1f63f57d72,0xfd1c2f611f63a3f0,
0xf24a01a73cf2dccf,0xbc633b39673c8cec,
0x976e41088617ca01,0xd5be0503e085d813,
0xbd49d14aa79dbc82,0x4b2d8644d8a74e18,
0xec9c459d51852ba2,0xddf8e7d60ed1219e,
0x93e1ab8252f33b45,0xcabb90e5c942b503,
0xb8da1662e7b00a17,0x3d6a751f3b936243,
0xe7109bfba19c0c9d,0xcc512670a783ad4,
0x906a617d450187e2,0x27fb2b80668b24c5,
0xb484f9dc9641e9da,0xb1f9f660802dedf6,
0xe1a63853bbd26451,0x5e7873f8a0396973,
0x8d07e33455637eb2,0xdb0b487b6423e1e8,
0xb049dc016abc5e5f,0x91ce1a9a3d2cda62,
0xdc5c5301c56b75f7,0x7641a140cc7810fb,
0x89b9b3e11b6329ba,0xa9e904c87fcb0a9d,
0xac2820d9623bf429,0x546345fa9fbdcd44,
0xd732290fbacaf133,0xa97c177947ad4095,
0x867f59a9d4bed6c0,0x49ed8eabcccc485d,
0xa81f301449ee8c70,0x5c68f256bfff5a74,
0xd226fc195c6a2f8c,0x73832eec6fff3111,
0x83585d8fd9c25db7,0xc831fd53c5ff7eab,
0xa42e74f3d032f525,0xba3e7ca8b77f5e55,
0xcd3a1230c43fb26f,0x28ce1bd2e55f35eb,
0x80444b5e7aa7cf85,0x7980d163cf5b81b3,
0xa0555e361951c366,0xd7e105bcc332621f,
0xc86ab5c39fa63440,0x8dd9472bf3fefaa7,
0xfa856334878fc150,0xb14f98f6f0feb951,
0x9c935e00d4b9d8d2,0x6ed1bf9a569f33d3,
0xc3b8358109e84f07,0xa862f80ec4700c8,
0xf4a642e14c6262c8,0xcd27bb612758c0fa,
0x98e7e9cccfbd7dbd,0x8038d51cb897789c,
0xbf21e44003acdd2c,0xe0470a63e6bd56c3,
0xeeea5d5004981478,0x1858ccfce06cac74,
0x95527a5202df0ccb,0xf37801e0c43ebc8,
0xbaa718e68396cffd,0xd30560258f54e6ba,
0xe950df20247c83fd,0x47c6b82ef32a2069,
0x91d28b7416cdd27e,0x4cdc331d57fa5441,
0xb6472e511c81471d,0xe0133fe4adf8e952,
0xe3d8f9e563a198e5,0x58180fddd97723a6,
0x8e679c2f5e44ff8f,0x570f09eaa7ea7648,
};
static inline KsJsonU128 ks_json_full_multiplication(uint64_t left, uint64_t right) { __uint128_t product = (__uint128_t)left * (__uint128_t)right; KsJsonU128 result = {(uint64_t)product, (uint64_t)(product >> 64u)}; return result; }
static inline double ks_json_to_double(uint64_t mantissa, uint64_t exponent, int negative) { union { uint64_t bits; double value; } result; mantissa &= ~(UINT64_C(1) << 52u); result.bits = mantissa | (exponent << 52u) | ((uint64_t)negative << 63u); return result.value; }
static KS_UNUSED int ks_json_compute_float64(int32_t power, uint64_t magnitude, int negative, double *answer) {
    if (magnitude == 0u) { *answer = negative ? -0.0 : 0.0; return 1; }
    int64_t exponent = (((INT64_C(152170) + INT64_C(65536)) * (int64_t)power) >> 16u) + INT64_C(1087); int leading = __builtin_clzll(magnitude); magnitude <<= leading; uint32_t index = 2u * (uint32_t)(power + 342);
    KsJsonU128 product = ks_json_full_multiplication(magnitude, ks_json_power_of_five_128[index]); if ((product.high & UINT64_C(0x1ff)) == UINT64_C(0x1ff)) { KsJsonU128 next = ks_json_full_multiplication(magnitude, ks_json_power_of_five_128[index + 1u]); product.low += next.high; if (next.high > product.low) { product.high += 1u; } }
    uint64_t lower = product.low, upper = product.high, upper_bit = upper >> 63u; uint64_t mantissa = upper >> (upper_bit + 9u); leading += (int)(1u ^ upper_bit); int64_t real_exponent = exponent - leading;
    if (real_exponent <= 0) { if (-real_exponent + 1 >= 64) { *answer = negative ? -0.0 : 0.0; return 1; } mantissa >>= (uint32_t)(-real_exponent + 1); mantissa += mantissa & 1u; mantissa >>= 1u; real_exponent = mantissa < (UINT64_C(1) << 52u) ? 0 : 1; *answer = ks_json_to_double(mantissa, (uint64_t)real_exponent, negative); return 1; }
    if (lower <= 1u && power >= -4 && power <= 23 && (mantissa & 3u) == 1u && (mantissa << (upper_bit + 9u)) == upper) { mantissa &= ~UINT64_C(1); } mantissa += mantissa & 1u; mantissa >>= 1u;
    if (mantissa >= (UINT64_C(1) << 53u)) { mantissa = UINT64_C(1) << 52u; real_exponent += 1; } if (real_exponent > 2046) { return 0; } *answer = ks_json_to_double(mantissa, (uint64_t)real_exponent, negative); return 1;
}
#endif
static KS_UNUSED double ks_lua_decimal64_value(lua_State *L, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, uint64_t magnitude, int32_t exponent, int negative, int exact) {
    if (exact && magnitude <= UINT64_C(9007199254740991) && exponent >= -22 && exponent <= 22) {
        static const double powers[] = { 1.0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22 };
        double value = (double)magnitude; value = exponent < 0 ? value / powers[-exponent] : value * powers[exponent]; return negative ? -value : value;
    }
#if defined(KS_JSON_WIDE)
    if (exact) { double value; if (exponent < -342) { return negative ? -0.0 : 0.0; } if (exponent <= 308 && ks_json_compute_float64(exponent, magnitude, negative, &value)) { return value; } }
#endif
    return ks_lua_number_slice(L, source, source_length, start, length, "value stream decimal");
}
static int ks_lua_hex(unsigned char byte) {
    if (byte >= '0' && byte <= '9') { return (int)(byte - '0'); }
    if (byte >= 'A' && byte <= 'F') { return (int)(byte - 'A') + 10; }
    if (byte >= 'a' && byte <= 'f') { return (int)(byte - 'a') + 10; }
    return -1;
}
static int ks_lua_hex4(const unsigned char *source, size_t length, size_t *at, uint32_t *value) {
    if (*at > length || length - *at < 4u) { return 0; }
    uint32_t out = 0;
    for (int i = 0; i < 4; ++i) {
        int digit = ks_lua_hex(source[(*at)++]);
        if (digit < 0) { return 0; }
        out = out * 16u + (uint32_t)digit;
    }
    *value = out;
    return 1;
}
static size_t ks_lua_utf8(unsigned char *out, uint32_t codepoint) {
    if (codepoint <= 0x7fu) { out[0] = (unsigned char)codepoint; return 1; }
    if (codepoint <= 0x7ffu) { out[0] = (unsigned char)(0xc0u | (codepoint >> 6)); out[1] = (unsigned char)(0x80u | (codepoint & 0x3fu)); return 2; }
    if (codepoint <= 0xffffu) { out[0] = (unsigned char)(0xe0u | (codepoint >> 12)); out[1] = (unsigned char)(0x80u | ((codepoint >> 6) & 0x3fu)); out[2] = (unsigned char)(0x80u | (codepoint & 0x3fu)); return 3; }
    out[0] = (unsigned char)(0xf0u | (codepoint >> 18)); out[1] = (unsigned char)(0x80u | ((codepoint >> 12) & 0x3fu)); out[2] = (unsigned char)(0x80u | ((codepoint >> 6) & 0x3fu)); out[3] = (unsigned char)(0x80u | (codepoint & 0x3fu)); return 4;
}
typedef struct { const char *bytes; size_t length; uint64_t packed; uint32_t hash; int32_t scalar; } KsLuaShapeKey;
typedef struct { const void *identity; const unsigned char *compiled; size_t compiled_length; uint32_t first, count; uint64_t required; int aliases, defaults, factory; } KsLuaShapePlan;
typedef struct { int table_index, shape_index; uint32_t kind, next, count, mode, plan, expected; uint64_t seen; int expects_key, aliases, tuple; } KsLuaBuildFrame;
typedef struct { int null_index, array_marker_index, object_marker_index, root_index, frame_root_index, byte_root_index, selection_shape_index, array_shape_marker_index, serde_markers_index, pending_shape_index; uint32_t depth, frame_capacity, pending_mode; int pending_shape_owned, pending_scalar, root_done; KsLuaBuildFrame *frames; KsLuaBuildFrame inline_frames[16]; unsigned char *bytes; uint32_t byte_capacity, byte_allocated, plan_count, key_count; KsLuaShapePlan plans[16]; KsLuaShapeKey keys[64]; } KsLuaBuilder;
typedef struct { uint32_t capacity; uint32_t words[1]; } KsLuaScratchU32Storage;
typedef struct { uint32_t *words; uint32_t capacity, length, escape_length; int root_index; uint32_t inline_words[32]; } KsLuaScratchU32;
typedef struct { unsigned char *bytes; uint32_t capacity, length; int root_index, cached; } KsLuaScratchU8;
/* The selector is already a rooted string. Length-aware equality preserves
 * embedded NUL bytes and never allocates or interns the literal case. */
static KS_UNUSED bool ks_lua_string_match(lua_State *L, int index, const char *literal, size_t literal_length) {
    size_t length = 0;
    const char *bytes = lua_tolstring(L, index, &length);
    return bytes != NULL && length == literal_length && memcmp(bytes, literal, length) == 0;
}
static KS_UNUSED uint32_t ks_lua_string_length(lua_State *L, size_t length) {
    if (length > (size_t)UINT32_MAX) { luaL_error(L, "AOT builder string exceeds uint32 range"); return 0u; }
    return (uint32_t)length;
}
static KS_UNUSED uint32_t ks_lua_string_byte(lua_State *L, const unsigned char *bytes, size_t length, uint32_t offset) {
    if ((size_t)offset >= length) { luaL_error(L, "AOT builder byte is out of bounds"); return 0u; }
    return (uint32_t)bytes[offset];
}
static KS_UNUSED double ks_lua_string_byte_lua(lua_State *L, const unsigned char *bytes, size_t length, double index) {
    if (floor(index) != index || index < 1.0 || index > (double)length) { luaL_error(L, "AOT string.byte index is out of bounds"); return 0.0; }
    return (double)bytes[(size_t)index - 1u];
}
static KS_UNUSED void ks_lua_substring(lua_State *L, const unsigned char *bytes, size_t length, double first_value, double last_value) {
    if (floor(first_value) != first_value || floor(last_value) != last_value) { luaL_error(L, "AOT string.sub bounds must be integers"); return; }
    double first = first_value < 0.0 ? (double)length + first_value + 1.0 : first_value; double last = last_value < 0.0 ? (double)length + last_value + 1.0 : last_value;
    if (first < 1.0) { first = 1.0; } if (last > (double)length) { last = (double)length; } if (first > last || first > (double)length) { lua_pushlstring(L, "", 0u); return; }
    lua_pushlstring(L, (const char *)(bytes + (size_t)first - 1u), (size_t)(last - first + 1.0));
}
static KS_UNUSED double ks_lua_table_number(lua_State *L, int table_index, double key, const char *site) {
    lua_rawgeti(L, table_index, ks_lua_index(L, key, site)); if (lua_type(L, -1) != 3) { luaL_error(L, "AOT fresh table entry is not numeric"); return 0.0; }
    double value = lua_tonumber(L, -1); lua_settop(L, lua_gettop(L) - 1); return value;
}
static KS_UNUSED void ks_lua_string_buffer_init(lua_State *L, KsLuaStringBuffer *buffer) {
    luaL_buffinit(L, buffer);
}
static KS_UNUSED void ks_lua_string_buffer_append(lua_State *L, KsLuaStringBuffer *buffer, const unsigned char *bytes, size_t length) {
    (void)L; luaL_addlstring(buffer, (const char *)bytes, length);
}
static KS_UNUSED void ks_lua_string_buffer_append_slice(lua_State *L, KsLuaStringBuffer *buffer, const unsigned char *bytes, size_t length, double first_value, double last_value) {
    if (floor(first_value) != first_value || floor(last_value) != last_value) { luaL_error(L, "AOT string.sub bounds must be integers"); return; } double first = first_value < 0.0 ? (double)length + first_value + 1.0 : first_value; double last = last_value < 0.0 ? (double)length + last_value + 1.0 : last_value; if (first < 1.0) { first = 1.0; } if (last > (double)length) { last = (double)length; } if (first > last || first > (double)length) { return; } ks_lua_string_buffer_append(L, buffer, bytes + (size_t)first - 1u, (size_t)(last - first + 1.0));
}
static KS_UNUSED void ks_lua_string_buffer_finish(lua_State *L, KsLuaStringBuffer *buffer) {
    (void)L; luaL_pushresult(buffer);
}
static KS_UNUSED uint32_t ks_lua_string_u32(lua_State *L, const unsigned char *bytes, size_t length, uint32_t index) {
    if (KS_COUNT_OVERFLOWS(index, sizeof(uint32_t))) { luaL_error(L, "AOT builder word index overflows"); return 0u; }
    size_t offset = (size_t)index * sizeof(uint32_t); uint32_t value = 0u;
    if (offset > length || sizeof(uint32_t) > length - offset) { luaL_error(L, "AOT builder word is out of bounds"); return 0u; }
    memcpy(&value, bytes + offset, sizeof(value)); return value;
}
static KS_UNUSED void ks_lua_scratch_u32(lua_State *L, KsLuaScratchU32 *scratch, uint32_t capacity, const void *key) {
    scratch->capacity = capacity; scratch->length = 0u; scratch->escape_length = 0u; scratch->root_index = 0;
    if (capacity <= 32u) { scratch->words = scratch->inline_words; return; }
    if (KS_COUNT_OVERFLOWS(capacity, sizeof(uint32_t)) || (size_t)capacity * sizeof(uint32_t) > SIZE_MAX - sizeof(KsLuaScratchU32Storage)) { luaL_error(L, "AOT scratch capacity overflows"); scratch->words = NULL; return; }
    lua_pushlightuserdata(L, (void *)key); lua_rawget(L, -10000);
    KsLuaScratchU32Storage *storage = (KsLuaScratchU32Storage *)lua_touserdata(L, -1);
    if (storage == NULL || storage->capacity < capacity) {
        lua_settop(L, lua_gettop(L) - 1);
        size_t bytes = sizeof(KsLuaScratchU32Storage) + ((size_t)capacity - 1u) * sizeof(uint32_t);
        storage = (KsLuaScratchU32Storage *)lua_newuserdata(L, bytes); storage->capacity = capacity;
        lua_pushlightuserdata(L, (void *)key); lua_pushvalue(L, -2); lua_rawset(L, -10000);
    }
    scratch->words = storage->words; scratch->root_index = lua_gettop(L);
}
/* Zeroed, and readable to its capacity from the moment it exists. The
 * appending buffer's storage is not zero-filled -- first touching those
 * pages is a real cost in a parser and it earns it by never reading what
 * it has not written -- but a fixed buffer promises every word, so it
 * pays the fill once and answers what a fresh word should. */
/* A fixed buffer whose storage is the caller's array. Nothing is
 * allocated and nothing is rooted, because nothing here outlives the
 * frame that declared it or can be reached from Lua at all. */
static KS_UNUSED void ks_lua_scratch_u32_stack(KsLuaScratchU32 *scratch, uint32_t *storage, uint32_t capacity) {
    scratch->capacity = capacity; scratch->length = capacity; scratch->escape_length = 0u;
    scratch->root_index = 0; scratch->words = storage;
}
static KS_UNUSED void ks_lua_scratch_u32_fixed(lua_State *L, KsLuaScratchU32 *scratch, uint32_t capacity, const void *key) {
    ks_lua_scratch_u32(L, scratch, capacity, key);
    if (scratch->words != NULL && capacity != 0u) { memset(scratch->words, 0, (size_t)capacity * sizeof(uint32_t)); }
    scratch->length = capacity;
}
/* A fixed buffer's bound is its width, which the call site writes as a
 * literal. The comparison is the same one the appending buffer makes and
 * refuses the same indexes; what differs is that this one is against a
 * number the compiler has, so it can discharge it where the index is a
 * counted loop's and keep it where it cannot. Nothing here asserts the
 * index is in range -- it is checked, and the check is what is emitted. */
static KS_UNUSED uint32_t ks_lua_scratch_u32_get_fixed(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index, uint32_t bound) {
    if (index >= bound) { luaL_error(L, "AOT scratch read is out of bounds"); return 0u; }
    return scratch->words[index];
}
static KS_UNUSED void ks_lua_scratch_u32_set_fixed(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index, uint32_t value, uint32_t bound) {
    if (index >= bound) { luaL_error(L, "AOT scratch write is out of bounds"); return; }
    scratch->words[index] = value;
}
static KS_UNUSED uint32_t ks_lua_scratch_u32_get(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index) {
    if (index >= scratch->length) { luaL_error(L, "AOT scratch read is out of bounds"); return 0u; }
    return scratch->words[index];
}
static KS_UNUSED uint32_t ks_lua_scratch_u32_escape_get(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index) { if (index >= scratch->escape_length) { luaL_error(L, "AOT escape scratch read is out of bounds"); return 0u; } return scratch->words[scratch->capacity - 1u - index]; }
static KS_UNUSED void ks_lua_scratch_u32_set(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index, uint32_t value) {
    if (index > scratch->length || index >= scratch->capacity) { luaL_error(L, "AOT scratch write is out of bounds"); return; }
    if (index == scratch->length) { scratch->length += 1u; } scratch->words[index] = value;
}
static KS_UNUSED uint32_t ks_reverse_u32(uint32_t value) {
    value = ((value >> 1u) & UINT32_C(0x55555555)) | ((value & UINT32_C(0x55555555)) << 1u);
    value = ((value >> 2u) & UINT32_C(0x33333333)) | ((value & UINT32_C(0x33333333)) << 2u);
    value = ((value >> 4u) & UINT32_C(0x0f0f0f0f)) | ((value & UINT32_C(0x0f0f0f0f)) << 4u);
    value = ((value >> 8u) & UINT32_C(0x00ff00ff)) | ((value & UINT32_C(0x00ff00ff)) << 8u);
    return (value >> 16u) | (value << 16u);
}
static KS_UNUSED uint32_t ks_lua_scratch_u32_append_bits(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index, uint32_t base, KsMaskBits64 bits) {
    uint32_t needed = (uint32_t)(__builtin_popcount(bits.low) + __builtin_popcount(bits.high));
    if (index != scratch->length || needed > scratch->capacity - scratch->escape_length - index) { luaL_error(L, "AOT scratch bit append is out of bounds"); return index; }
#if defined(__aarch64__)
    uint32_t low = ks_reverse_u32(bits.low), high = ks_reverse_u32(bits.high);
    while (low != 0u) { uint32_t bit = (uint32_t)__builtin_clz(low); scratch->words[index++] = base + bit; low &= ~(UINT32_C(0x80000000) >> bit); }
    while (high != 0u) { uint32_t bit = (uint32_t)__builtin_clz(high); scratch->words[index++] = base + UINT32_C(32) + bit; high &= ~(UINT32_C(0x80000000) >> bit); }
#else
    while (bits.low != 0u) { uint32_t bit = (uint32_t)__builtin_ctz(bits.low); scratch->words[index++] = base + bit; bits.low &= bits.low - 1u; }
    while (bits.high != 0u) { uint32_t bit = (uint32_t)__builtin_ctz(bits.high); scratch->words[index++] = base + UINT32_C(32) + bit; bits.high &= bits.high - 1u; }
#endif
    scratch->length = index; return index;
}
static KS_UNUSED uint32_t ks_lua_scratch_u32_append_bits_eager(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index, uint32_t base, KsMaskBits64 bits) {
    uint32_t needed = (uint32_t)(__builtin_popcount(bits.low) + __builtin_popcount(bits.high));
    if (index != scratch->length || needed > scratch->capacity - index) { luaL_error(L, "AOT scratch bit append is out of bounds"); return index; }
#if defined(__aarch64__)
    uint32_t low = ks_reverse_u32(bits.low), high = ks_reverse_u32(bits.high);
    while (low != 0u) { uint32_t bit = (uint32_t)__builtin_clz(low); scratch->words[index++] = base + bit; low &= ~(UINT32_C(0x80000000) >> bit); }
    while (high != 0u) { uint32_t bit = (uint32_t)__builtin_clz(high); scratch->words[index++] = base + 32u + bit; high &= ~(UINT32_C(0x80000000) >> bit); }
#else
    while (bits.low != 0u) { uint32_t bit = (uint32_t)__builtin_ctz(bits.low); scratch->words[index++] = base + bit; bits.low &= bits.low - 1u; }
    while (bits.high != 0u) { uint32_t bit = (uint32_t)__builtin_ctz(bits.high); scratch->words[index++] = base + 32u + bit; bits.high &= bits.high - 1u; }
#endif
    scratch->length = index; return index;
}
static KS_UNUSED uint32_t ks_lua_scratch_u32_append_string_bits(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index, uint32_t base, KsMaskBits64 events, KsMaskBits64 quotes, KsMaskBits64 slashes, int in_string, int string_escaped) {
    uint32_t needed = (uint32_t)(__builtin_popcount(events.low) + __builtin_popcount(events.high));
    if (index != scratch->length || needed > scratch->capacity - index) { luaL_error(L, "AOT scratch string bit append is out of bounds"); return index; }
    uint64_t event_bits = (uint64_t)events.low | ((uint64_t)events.high << 32u);
    uint64_t quote_bits = (uint64_t)quotes.low | ((uint64_t)quotes.high << 32u);
    uint64_t slash_bits = (uint64_t)slashes.low | ((uint64_t)slashes.high << 32u);
    while (event_bits != 0u) {
        uint32_t bit = (uint32_t)__builtin_ctzll(event_bits); uint64_t before = (UINT64_C(1) << bit) - UINT64_C(1);
        if (in_string && (slash_bits & before) != 0u) { string_escaped = 1; } slash_bits &= ~before;
        uint32_t word = base + bit; if ((quote_bits & (UINT64_C(1) << bit)) != 0u) { if (in_string && string_escaped) { word |= UINT32_C(0x80000000); } in_string = !in_string; string_escaped = 0; }
        scratch->words[index++] = word; event_bits &= event_bits - UINT64_C(1);
    }
    if (in_string && slash_bits != 0u) { string_escaped = 1; } scratch->length = index; return index | (string_escaped ? UINT32_C(0x80000000) : 0u);
}
static KS_UNUSED uint32_t ks_lua_scratch_u32_append_string_shared_bits(lua_State *L, KsLuaScratchU32 *scratch, uint32_t index, uint32_t base, KsMaskBits64 events, KsMaskBits64 quotes, KsMaskBits64 slashes, int in_string, int string_escaped) { uint32_t needed = (uint32_t)(__builtin_popcount(events.low) + __builtin_popcount(events.high)); if (index != scratch->length || needed > scratch->capacity - scratch->escape_length - index) { luaL_error(L, "AOT scratch string bit append is out of bounds"); return index; } return ks_lua_scratch_u32_append_string_bits(L, scratch, index, base, events, quotes, slashes, in_string, string_escaped); }
static KS_UNUSED uint32_t ks_lua_scratch_u32_append_string_escape_bits(lua_State *L, KsLuaScratchU32 *scratch, KsLuaScratchU32 *escapes, uint32_t index, uint32_t base, KsMaskBits64 events, KsMaskBits64 quotes, KsMaskBits64 slashes, int slash_carry, int slash_odd, int in_string, int string_escaped) {
    uint32_t needed = (uint32_t)(__builtin_popcount(events.low) + __builtin_popcount(events.high));
    if (index != scratch->length || needed > scratch->capacity - scratch->escape_length - index) { luaL_error(L, "AOT scratch string bit append is out of bounds"); return index; }
    uint64_t event_bits = (uint64_t)events.low | ((uint64_t)events.high << 32u);
    uint64_t quote_bits = (uint64_t)quotes.low | ((uint64_t)quotes.high << 32u);
    uint64_t slash_bits = (uint64_t)slashes.low | ((uint64_t)slashes.high << 32u);
    uint64_t spanning = 0u; if (in_string) { uint32_t close = quote_bits == 0u ? 64u : (uint32_t)__builtin_ctzll(quote_bits); spanning |= close == 64u ? ~UINT64_C(0) : (UINT64_C(1) << close) - UINT64_C(1); } int ends_in_string = in_string ^ ((__builtin_popcountll(quote_bits) & 1) != 0); if (ends_in_string) { uint32_t open = quote_bits == 0u ? 0u : 63u - (uint32_t)__builtin_clzll(quote_bits); spanning |= quote_bits == 0u ? ~UINT64_C(0) : open == 63u ? 0u : ~((UINT64_C(1) << (open + 1u)) - UINT64_C(1)); }
    uint64_t retained_slashes = 0u, remaining_slashes = slash_bits & spanning; while (remaining_slashes != 0u) { uint32_t run_start = (uint32_t)__builtin_ctzll(remaining_slashes), run_end = run_start; while (run_end < 64u && (slash_bits & (UINT64_C(1) << run_end)) != 0u) { run_end += 1u; } uint32_t first = run_start + ((run_start == 0u && slash_carry && slash_odd) ? 1u : 0u); for (uint32_t lane = first; lane < run_end; lane += 2u) { retained_slashes |= UINT64_C(1) << lane; } uint64_t run_mask = run_end == 64u ? (~UINT64_C(0) << run_start) : ((UINT64_C(1) << run_end) - (UINT64_C(1) << run_start)); remaining_slashes &= ~run_mask; } uint32_t escape_needed = (uint32_t)__builtin_popcountll(retained_slashes); if (escape_needed > escapes->capacity - escapes->length - escapes->escape_length) { luaL_error(L, "AOT escape scratch append is out of bounds"); return index; }
    while (retained_slashes != 0u) { uint32_t bit = (uint32_t)__builtin_ctzll(retained_slashes); escapes->words[escapes->capacity - 1u - escapes->escape_length++] = base + bit; retained_slashes &= retained_slashes - UINT64_C(1); }
    while (event_bits != 0u) {
        uint32_t bit = (uint32_t)__builtin_ctzll(event_bits); uint64_t before = (UINT64_C(1) << bit) - UINT64_C(1);
        if (in_string && (slash_bits & before) != 0u) { string_escaped = 1; } slash_bits &= ~before;
        uint32_t word = base + bit; if ((quote_bits & (UINT64_C(1) << bit)) != 0u) { if (in_string && string_escaped) { word |= UINT32_C(0x80000000); } in_string = !in_string; string_escaped = 0; }
        scratch->words[index++] = word; event_bits &= event_bits - UINT64_C(1);
    }
    if (in_string && slash_bits != 0u) { string_escaped = 1; } scratch->length = index;
    return index | (string_escaped ? UINT32_C(0x80000000) : 0u);
}
static KS_UNUSED KsLuaScratchU8 ks_lua_scratch_u8(lua_State *L, uint32_t capacity) {
    unsigned char *bytes = (unsigned char *)lua_newuserdata(L, capacity == 0u ? 1u : (size_t)capacity);
    KsLuaScratchU8 scratch = {bytes, capacity, 0u, lua_gettop(L), 0}; return scratch;
}
/* One cached appending buffer, so a large scratch is allocated and
 * first touched once rather than on every call.
 *
 * Only an entry the emitter proved publishes once and then returns gets
 * this, because the buffer is offered back at that publish. Between the
 * take and the offer it is exclusively this call's: the take removes it
 * from the registry, so a reentrant call finds nothing and allocates its
 * own, and an error in between leaves the cache empty rather than
 * corrupting anything.
 *
 * Nothing is zeroed and nothing needs to be. An appending buffer reads
 * only below a fill length that starts at zero, so bytes left by the
 * previous call are unreachable rather than stale. */
/* One slot for every module in a state. A file-scope address would be
 * a different key in each translation unit, so each would keep its own
 * buffer and the bound below would be per module rather than per
 * state. An interned string is the same slot everywhere. */
#define KS_SCRATCH_CACHE_KEY "nupp.aot.scratch.u8"
#define KS_SCRATCH_CACHE_MAX ((size_t)8u << 20)
/* Lua 5.1's registry pseudo-index and userdata tag, as the numbers this
 * file already spells its other type tags as. */
#define KS_REGISTRY (-10000)
#define KS_TUSERDATA 7
static KS_UNUSED KsLuaScratchU8 ks_lua_scratch_u8_cached(lua_State *L, uint32_t capacity) {
    size_t want = capacity == 0u ? 1u : (size_t)capacity;
    lua_pushlstring(L, KS_SCRATCH_CACHE_KEY, sizeof(KS_SCRATCH_CACHE_KEY) - 1u);
    lua_rawget(L, -10000);
    if (lua_type(L, -1) == 7 && lua_objlen(L, -1) >= want) {
        lua_pushlstring(L, KS_SCRATCH_CACHE_KEY, sizeof(KS_SCRATCH_CACHE_KEY) - 1u);
        lua_pushnil(L);
        lua_rawset(L, -10000);
        unsigned char *taken = (unsigned char *)lua_touserdata(L, -1);
        KsLuaScratchU8 reused = {taken, capacity, 0u, lua_gettop(L), 1}; return reused;
    }
    lua_settop(L, lua_gettop(L) - 1);
    unsigned char *bytes = (unsigned char *)lua_newuserdata(L, want);
    KsLuaScratchU8 scratch = {bytes, capacity, 0u, lua_gettop(L), 1}; return scratch;
}
/* A fixed byte buffer whose storage is the caller's array. Nothing is
 * allocated and nothing is rooted, because nothing here outlives the
 * frame that declared it or can be reached from Lua at all. Readable to
 * its capacity from the moment it exists, so it is zeroed once. */
static KS_UNUSED KsLuaScratchU8 ks_lua_scratch_u8_stack(unsigned char *storage, uint32_t capacity) {
    if (capacity != 0u) { memset(storage, 0, (size_t)capacity); }
    KsLuaScratchU8 scratch = {storage, capacity, capacity, 0, 0}; return scratch;
}
/* The same comparisons the appending buffer makes, against a number the
 * call site wrote rather than a length loaded from the buffer. Nothing
 * here asserts the index is in range: it is checked, and the check is
 * what is emitted. */
static KS_UNUSED uint32_t ks_lua_scratch_u8_get_fixed(lua_State *L, KsLuaScratchU8 *scratch, uint32_t index, uint32_t bound) {
    if (index >= bound) { luaL_error(L, "AOT byte scratch read is out of bounds"); return 0u; }
    return (uint32_t)scratch->bytes[index];
}
/* Out of line and cold so that a guard is a predicted-not-taken branch
 * to somewhere else, rather than a call the hot block has to keep its
 * live values alive across. */
static KS_UNUSED KS_COLD void ks_scratch_raise(lua_State *L, const char *what) { luaL_error(L, what); }
static KS_UNUSED void ks_lua_scratch_u8_set_fixed(lua_State *L, KsLuaScratchU8 *scratch, uint32_t index, uint32_t value, uint32_t bound) {
    if (KS_UNLIKELY(index >= bound || value > 255u)) { ks_scratch_raise(L, "AOT byte scratch write is out of bounds"); return; }
    scratch->bytes[index] = (unsigned char)value;
}
static KS_UNUSED uint32_t ks_lua_scratch_u8_get(lua_State *L, KsLuaScratchU8 *scratch, uint32_t index) {
    if (index >= scratch->length) { luaL_error(L, "AOT byte scratch read is out of bounds"); return 0u; } return (uint32_t)scratch->bytes[index];
}
static KS_UNUSED void ks_lua_scratch_u8_set(lua_State *L, KsLuaScratchU8 *scratch, uint32_t index, uint32_t value) {
    if (KS_UNLIKELY(index > scratch->length || index >= scratch->capacity || value > 255u)) { ks_scratch_raise(L, "AOT byte scratch write is out of bounds"); return; }
    if (index == scratch->length) { scratch->length += 1u; } scratch->bytes[index] = (unsigned char)value;
}
static KS_UNUSED void ks_store_u8x4(unsigned char *destination, uint32_t value) {
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    destination[0] = (unsigned char)(value & 0xffu); destination[1] = (unsigned char)((value >> 8) & 0xffu);
    destination[2] = (unsigned char)((value >> 16) & 0xffu); destination[3] = (unsigned char)((value >> 24) & 0xffu);
#else
    memcpy(destination, &value, sizeof(value));
#endif
}
static KS_UNUSED void ks_lua_scratch_u8_set4_fixed(lua_State *L, KsLuaScratchU8 *scratch, uint32_t index, uint32_t value, uint32_t bound) {
    if (KS_UNLIKELY(index > bound || bound - index < 4u)) { ks_scratch_raise(L, "AOT byte scratch write is out of bounds"); return; }
    ks_store_u8x4(scratch->bytes + index, value);
}
static KS_UNUSED void ks_lua_scratch_u8_set4(lua_State *L, KsLuaScratchU8 *scratch, uint32_t index, uint32_t value) {
    if (KS_UNLIKELY(index > scratch->length || index > scratch->capacity || scratch->capacity - index < 4u)) { ks_scratch_raise(L, "AOT byte scratch write is out of bounds"); return; }
    if (KS_UNLIKELY(index < scratch->length && scratch->length - index < 4u)) { ks_scratch_raise(L, "AOT byte scratch write straddles the length"); return; }
    if (index == scratch->length) { scratch->length += 4u; }
    ks_store_u8x4(scratch->bytes + index, value);
}
static KS_UNUSED int ks_lua_scratch_u8_push(lua_State *L, KsLuaScratchU8 *scratch, uint32_t start, uint32_t length) {
    if (start > scratch->length || length > scratch->length - start) { return luaL_error(L, "AOT byte scratch string range is out of bounds"); }
    lua_pushlstring(L, (const char *)(scratch->bytes + start), (size_t)length);
    if (scratch->cached && (size_t)scratch->capacity <= KS_SCRATCH_CACHE_MAX) {
        lua_pushlstring(L, KS_SCRATCH_CACHE_KEY, sizeof(KS_SCRATCH_CACHE_KEY) - 1u);
        lua_rawget(L, -10000);
        int keep = lua_type(L, -1) != 7 || lua_objlen(L, -1) < (size_t)scratch->capacity;
        lua_settop(L, lua_gettop(L) - 1);
        if (keep) {
            lua_pushlstring(L, KS_SCRATCH_CACHE_KEY, sizeof(KS_SCRATCH_CACHE_KEY) - 1u);
            lua_pushvalue(L, scratch->root_index);
            lua_rawset(L, -10000);
        }
    }
    return 1;
}
#define KS_LUA_BUILD_SKIP UINT32_C(0)
#define KS_LUA_BUILD_ALL UINT32_C(1)
#define KS_LUA_BUILD_OBJECT UINT32_C(2)
#define KS_LUA_BUILD_ARRAY UINT32_C(3)
#define KS_LUA_BUILD_PENDING UINT32_MAX
static KS_UNUSED KsLuaBuilder ks_lua_builder_new(lua_State *L, int null_index, int array_marker_index, int object_marker_index, uint32_t max_depth, uint32_t byte_capacity, int selection_shape_index, int array_shape_marker_index, int serde_markers_index) {
    if (KS_COUNT_OVERFLOWS(max_depth, sizeof(KsLuaBuildFrame))) { luaL_error(L, "AOT value stream depth capacity overflows"); max_depth = 0u; }
    if (selection_shape_index != 0 && lua_type(L, selection_shape_index) <= 0) { selection_shape_index = 0; }
    uint32_t pending_mode = selection_shape_index == 0 ? KS_LUA_BUILD_ALL : KS_LUA_BUILD_OBJECT;
    KsLuaBuilder builder; builder.null_index = null_index; builder.array_marker_index = array_marker_index; builder.object_marker_index = object_marker_index; builder.root_index = 0; builder.frame_root_index = lua_gettop(L); builder.byte_root_index = 0; builder.selection_shape_index = selection_shape_index; builder.array_shape_marker_index = array_shape_marker_index; builder.serde_markers_index = serde_markers_index; builder.pending_shape_index = selection_shape_index; builder.depth = 0u; builder.frame_capacity = max_depth; builder.pending_mode = pending_mode; builder.pending_shape_owned = 0; builder.pending_scalar = 0; builder.root_done = 0; builder.frames = NULL; builder.bytes = NULL; builder.byte_capacity = byte_capacity; builder.byte_allocated = 0u; builder.plan_count = 0u; builder.key_count = 0u; return builder;
}
static KS_UNUSED KsLuaBuildFrame *ks_lua_builder_frame(KsLuaBuilder *builder, uint32_t index) {
    return builder->frames != NULL ? &builder->frames[index] : &builder->inline_frames[index];
}
static KS_UNUSED void ks_lua_builder_shift_indices(KsLuaBuilder *builder, int destination) {
    if (builder->byte_root_index >= destination) { builder->byte_root_index += 1; }
    if (builder->array_marker_index >= destination) { builder->array_marker_index += 1; } if (builder->object_marker_index >= destination) { builder->object_marker_index += 1; }
    if (builder->selection_shape_index >= destination) { builder->selection_shape_index += 1; } if (builder->array_shape_marker_index >= destination) { builder->array_shape_marker_index += 1; } if (builder->serde_markers_index >= destination) { builder->serde_markers_index += 1; }
    if (builder->pending_shape_index >= destination) { builder->pending_shape_index += 1; }
    for (uint32_t at = 0u; at < builder->depth; ++at) { KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, at); if (frame->table_index >= destination) { frame->table_index += 1; } if (frame->shape_index >= destination) { frame->shape_index += 1; } }
    if (builder->root_index >= destination) { builder->root_index += 1; }
}
static KS_UNUSED void ks_lua_builder_ensure_frames(lua_State *L, KsLuaBuilder *builder) {
    if (builder->frames != NULL || builder->frame_capacity <= 16u) { return; }
    size_t bytes = (size_t)builder->frame_capacity * sizeof(KsLuaBuildFrame);
    builder->frames = (KsLuaBuildFrame *)lua_newuserdata(L, bytes); memcpy(builder->frames, builder->inline_frames, sizeof(builder->inline_frames));
    int destination = builder->frame_root_index + 1; lua_insert(L, destination); builder->frame_root_index = destination;
    ks_lua_builder_shift_indices(builder, destination);
}
static KS_UNUSED unsigned char *ks_lua_builder_bytes(lua_State *L, KsLuaBuilder *builder, uint32_t needed) {
    if (needed > builder->byte_capacity) { luaL_error(L, "AOT value stream string exceeds its authored capacity"); return NULL; }
    if (builder->bytes != NULL && needed <= builder->byte_allocated) { return builder->bytes; }
    uint32_t capacity = builder->byte_allocated == 0u ? (builder->byte_capacity < 64u ? builder->byte_capacity : 64u) : builder->byte_allocated;
    while (capacity < needed) { if (capacity > builder->byte_capacity / 2u) { capacity = builder->byte_capacity; break; } capacity *= 2u; }
    unsigned char *bytes = (unsigned char *)lua_newuserdata(L, capacity == 0u ? 1u : (size_t)capacity);
    if (builder->byte_root_index == 0) { int destination = builder->frame_root_index + 1; lua_insert(L, destination); ks_lua_builder_shift_indices(builder, destination); builder->byte_root_index = destination; }
    else { lua_insert(L, builder->byte_root_index); lua_remove(L, builder->byte_root_index + 1); }
    builder->bytes = bytes; builder->byte_allocated = capacity;
    return builder->bytes;
}
static KS_UNUSED int ks_lua_builder_shape_marker(lua_State *L, KsLuaBuilder *builder, int shape_index, int marker);
static inline __attribute__((always_inline, unused)) int ks_lua_builder_complete(lua_State *L, KsLuaBuilder *builder, int pushed, int eager) {
    if (!eager && pushed && builder->pending_mode == KS_LUA_BUILD_OBJECT && builder->pending_shape_index != 0 && lua_type(L, builder->pending_shape_index) == 5) { int value = lua_gettop(L), matched = 0, literal = ks_lua_builder_shape_marker(L, builder, builder->pending_shape_index, 11); if (lua_type(L, literal) != 0) { matched = lua_equal(L, value, literal); } else { int choices = ks_lua_builder_shape_marker(L, builder, builder->pending_shape_index, 14); if (lua_type(L, choices) == 5) { size_t count = lua_objlen(L, choices); for (size_t at = 1u; at <= count && !matched; ++at) { lua_rawgeti(L, choices, (int)at); matched = lua_equal(L, value, -1); lua_settop(L, lua_gettop(L) - 1); } } } if (!matched) { return luaL_error(L, "nupp: value does not match literal schema or union"); } lua_settop(L, value); if (builder->pending_shape_owned) { lua_remove(L, builder->pending_shape_index); } builder->pending_shape_index = 0; builder->pending_shape_owned = 0; builder->pending_mode = KS_LUA_BUILD_PENDING; }
    if (builder->depth == 0u) {
        if (builder->root_done) { return luaL_error(L, "AOT value stream has more than one root"); }
        builder->root_done = 1; if (pushed) { builder->root_index = lua_gettop(L); } else { lua_pushnil(L); builder->root_index = lua_gettop(L); } return 1;
    }
    KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, builder->depth - 1u);
    if (frame->kind == 5u) {
        if (frame->count == UINT32_MAX) { return luaL_error(L, "AOT value stream array is too large"); } frame->count += 1u;
        if (!pushed) { return 1; }
        if (frame->table_index == 0 || (!eager && lua_gettop(L) != frame->table_index + 1)) { return luaL_error(L, "AOT value stream value is not above its array"); }
        if (lua_type(L, -1) == 0) { lua_settop(L, frame->table_index); return 1; }
        if (frame->next > (uint32_t)INT_MAX) { return luaL_error(L, "AOT value stream array exceeds C API range"); } lua_rawseti(L, frame->table_index, (int)frame->next++); return 1;
    }
    if (frame->expects_key) { return luaL_error(L, "AOT value stream object needs a key"); }
    if (frame->count == UINT32_MAX) { return luaL_error(L, "AOT value stream object is too large"); }
    frame->count += 1u; frame->expects_key = 1; if (!pushed) { return 1; }
    if (frame->table_index == 0 || (!eager && lua_gettop(L) != frame->table_index + 2)) { return luaL_error(L, "AOT value stream key and value are not above their object"); }
    if (lua_type(L, -1) == 0) { lua_settop(L, frame->table_index); return 1; } lua_rawset(L, frame->table_index); return 1;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_put(lua_State *L, KsLuaBuilder *builder, int eager) { return ks_lua_builder_complete(L, builder, 1, eager); }
static KS_UNUSED int ks_lua_builder_prepare(lua_State *L, KsLuaBuilder *builder) {
    if (builder->pending_mode != KS_LUA_BUILD_PENDING) { return 1; }
    if (builder->depth == 0u) { return luaL_error(L, "AOT value stream has more than one root"); }
    KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, builder->depth - 1u);
    if (frame->kind != 5u) { return luaL_error(L, "AOT value stream object needs a key"); }
    if (frame->mode == KS_LUA_BUILD_SKIP) { builder->pending_mode = KS_LUA_BUILD_SKIP; }
    else if (frame->mode == KS_LUA_BUILD_ALL) { builder->pending_mode = KS_LUA_BUILD_ALL; }
    else { if (frame->tuple) { if (frame->next > (uint32_t)INT_MAX) { return luaL_error(L, "AOT tuple index exceeds C API range"); } lua_rawgeti(L, frame->shape_index, (int)frame->next); if (lua_type(L, -1) == 0) { return luaL_error(L, "nupp: tuple has too many values"); } } else { lua_pushvalue(L, frame->shape_index); } builder->pending_shape_index = lua_gettop(L); builder->pending_shape_owned = 1; builder->pending_mode = KS_LUA_BUILD_OBJECT; }
    return 1;
}
static KS_UNUSED void ks_lua_builder_clear_pending(lua_State *L, KsLuaBuilder *builder) {
    if (builder->pending_shape_owned) { lua_remove(L, builder->pending_shape_index); } builder->pending_shape_index = 0; builder->pending_shape_owned = 0; builder->pending_scalar = 0; builder->pending_mode = KS_LUA_BUILD_PENDING;
}
static KS_UNUSED int ks_lua_builder_shape_marker(lua_State *L, KsLuaBuilder *builder, int shape_index, int marker);
static inline __attribute__((always_inline, unused)) int ks_lua_builder_scalar_wanted(lua_State *L, KsLuaBuilder *builder, int eager) {
    if (eager) { return 1; }
    ks_lua_builder_prepare(L, builder); uint32_t mode = builder->pending_mode;
    if (mode == KS_LUA_BUILD_SKIP) { ks_lua_builder_clear_pending(L, builder); return 0; }
    if (mode == KS_LUA_BUILD_ALL) { ks_lua_builder_clear_pending(L, builder); return 1; }
    if (builder->pending_scalar != 0) { return 1; } int shape = builder->pending_shape_index; int type = lua_type(L, shape);
    if (type == 1) { int wanted = lua_toboolean(L, shape); ks_lua_builder_clear_pending(L, builder); return wanted; }
    if (type == 3 && builder->serde_markers_index != 0 && lua_type(L, builder->serde_markers_index) == 5) { return 1; }
    if (type == 5) { int top = lua_gettop(L), scalar = ks_lua_builder_shape_marker(L, builder, shape, 10); int wanted = lua_type(L, scalar) == 3; lua_settop(L, top); if (!wanted) { int choices = ks_lua_builder_shape_marker(L, builder, shape, 14); wanted = lua_type(L, choices) == 5; lua_settop(L, top); } if (wanted) { return 1; } return luaL_error(L, "pull container shape matched a scalar value"); }
    return luaL_error(L, "pull shape entries must be true, false, object shapes, or array shapes");
}
static KS_UNUSED int ks_lua_builder_shape_marker(lua_State *L, KsLuaBuilder *builder, int shape_index, int marker) {
    if (builder->serde_markers_index == 0 || lua_type(L, builder->serde_markers_index) != 5) { lua_pushnil(L); return lua_gettop(L); }
    if (shape_index == 0 || lua_type(L, shape_index) != 5) { return luaL_error(L, "AOT value stream shape marker needs a table"); }
    lua_rawgeti(L, builder->serde_markers_index, marker); lua_rawget(L, shape_index); return lua_gettop(L);
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_scalar_validate(lua_State *L, KsLuaBuilder *builder, int eager, int actual, double value) {
    if (eager) { return 1; }
    if (builder->pending_mode != KS_LUA_BUILD_OBJECT || (builder->pending_shape_index == 0 && builder->pending_scalar == 0)) { return 1; }
    int shape = builder->pending_shape_index; int expected = builder->pending_scalar, literal = 0; if (expected == 0) { if (lua_type(L, shape) == 5) { int top = lua_gettop(L), scalar = ks_lua_builder_shape_marker(L, builder, shape, 10); if (lua_type(L, scalar) == 3) { expected = (int)lua_tonumber(L, scalar); } else { lua_settop(L, top); int choices = ks_lua_builder_shape_marker(L, builder, shape, 14); if (lua_type(L, choices) != 5) { return luaL_error(L, "pull container shape matched a scalar value"); } } lua_settop(L, top); literal = 1; if (expected == 0) { return 1; } } else { if (lua_type(L, shape) != 3) { return luaL_error(L, "pull container shape matched a scalar value"); } expected = (int)lua_tonumber(L, shape); } } if (expected < 0) { expected = -expected; }
    if (actual != expected && !(actual == 3 && expected >= 3)) { return luaL_error(L, expected == 1 ? "nupp: expected boolean" : expected == 2 ? "nupp: expected string" : "nupp: expected number"); }
    if (expected >= 3) {
        if (!isfinite(value)) { return luaL_error(L, "nupp: expected finite number"); }
        if (expected >= 4 && floor(value) != value) { return luaL_error(L, "nupp: expected integer"); }
        if (expected >= 5 && expected <= 8 && value < 0.0) { return luaL_error(L, "nupp: expected unsigned integer"); }
        if ((expected == 6 && value > 255.0) || (expected == 7 && value > 65535.0) || (expected == 8 && value > 4294967295.0) || (expected == 9 && (value < -128.0 || value > 127.0)) || (expected == 10 && (value < -32768.0 || value > 32767.0)) || (expected == 11 && (value < -2147483648.0 || value > 2147483647.0))) { return luaL_error(L, "nupp: number is outside schema range"); }
    }
    if (!literal) { ks_lua_builder_clear_pending(L, builder); } return 1;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_null_wanted(lua_State *L, KsLuaBuilder *builder, int eager) {
    if (eager) { return 1; }
    ks_lua_builder_prepare(L, builder); uint32_t mode = builder->pending_mode;
    if (mode == KS_LUA_BUILD_SKIP) { ks_lua_builder_clear_pending(L, builder); return 0; }
    if (mode == KS_LUA_BUILD_ALL) { ks_lua_builder_clear_pending(L, builder); return 1; }
    if (mode != KS_LUA_BUILD_OBJECT || (builder->pending_shape_index == 0 && builder->pending_scalar == 0)) { return luaL_error(L, "pull shape cannot accept null"); }
    if (builder->pending_scalar != 0) { int accepted = builder->pending_scalar < 0; if (!accepted) { return luaL_error(L, "nupp: null is not allowed"); } ks_lua_builder_clear_pending(L, builder); return 1; }
    int shape = builder->pending_shape_index; if (lua_type(L, shape) == 1) { int wanted = lua_toboolean(L, shape); ks_lua_builder_clear_pending(L, builder); return wanted; }
    if (lua_type(L, shape) == 3 && builder->serde_markers_index != 0 && lua_type(L, builder->serde_markers_index) == 5) { int accepted = lua_tonumber(L, shape) < 0.0; if (!accepted) { return luaL_error(L, "nupp: null is not allowed"); } ks_lua_builder_clear_pending(L, builder); return 1; }
    if (lua_type(L, shape) != 5) { return luaL_error(L, "pull shape cannot accept null"); } int top = lua_gettop(L); int nullable = ks_lua_builder_shape_marker(L, builder, shape, 9); int accepted = lua_toboolean(L, nullable); lua_settop(L, top);
    if (!accepted) { return luaL_error(L, "nupp: null is not allowed"); } ks_lua_builder_clear_pending(L, builder); return 1;
}
static KS_UNUSED uint32_t ks_lua_builder_key_hash(const unsigned char *bytes, size_t length) {
    uint32_t hash = UINT32_C(2166136261); for (size_t at = 0u; at < length; ++at) { hash ^= (uint32_t)bytes[at]; hash *= UINT32_C(16777619); } return hash;
}
static KS_UNUSED void ks_lua_builder_add_shape_key(lua_State *L, KsLuaBuilder *builder, int index) {
    KsLuaShapeKey *key = &builder->keys[builder->key_count++]; key->bytes = lua_tolstring(L, index, &key->length); key->hash = ks_lua_builder_key_hash((const unsigned char *)key->bytes, key->length); key->packed = 0u; key->scalar = 0;
    if (key->length <= 7u) { memcpy(&key->packed, key->bytes, key->length); key->packed |= (uint64_t)'"' << (key->length * 8u); }
}
static KS_UNUSED uint32_t ks_lua_builder_blob_u32(const unsigned char *bytes) { uint32_t value = 0u; memcpy(&value, bytes, sizeof(value)); return value; }
static KS_UNUSED int ks_lua_builder_plan_key(KsLuaBuilder *builder, KsLuaShapePlan *plan, uint32_t index, KsLuaShapeKey *key) {
    if (index >= plan->count) { return 0; } if (plan->compiled == NULL) { *key = builder->keys[plan->first + index]; return 1; }
    const unsigned char *header = plan->compiled + 12u + (size_t)index * 24u; uint32_t offset = ks_lua_builder_blob_u32(header + 16u); key->length = (size_t)ks_lua_builder_blob_u32(header); key->hash = ks_lua_builder_blob_u32(header + 4u); memcpy(&key->packed, header + 8u, sizeof(key->packed)); key->scalar = (int32_t)ks_lua_builder_blob_u32(header + 20u);
    size_t names = 12u + (size_t)plan->count * 24u; if (names > plan->compiled_length || (size_t)offset > plan->compiled_length - names || key->length > plan->compiled_length - names - (size_t)offset) { return 0; } key->bytes = (const char *)(plan->compiled + names + (size_t)offset); return 1;
}
static KS_UNUSED uint32_t ks_lua_builder_shape_plan(lua_State *L, KsLuaBuilder *builder, int shape_index) {
    const void *identity = lua_topointer(L, shape_index);
    for (uint32_t index = 0u; index < builder->plan_count; ++index) { if (builder->plans[index].identity == identity) return index; }
    if (builder->plan_count >= 16u) { return UINT32_MAX; }
    uint32_t first = builder->key_count; int top = lua_gettop(L); if (builder->serde_markers_index != 0) { lua_rawgeti(L, shape_index, 0); } else { ks_lua_builder_shape_marker(L, builder, shape_index, 6); } int compiled_index = lua_gettop(L); size_t compiled_length = 0u; const unsigned char *compiled = (const unsigned char *)lua_tolstring(L, compiled_index, &compiled_length);
    if (compiled != NULL && compiled_length >= 12u) { uint32_t descriptor = ks_lua_builder_blob_u32(compiled), count = descriptor & UINT32_C(65535); size_t headers = 12u + (size_t)count * 24u; if (count <= 64u && headers <= compiled_length && builder->plan_count < 16u) { uint32_t plan = builder->plan_count++; builder->plans[plan].identity = identity; builder->plans[plan].compiled = compiled; builder->plans[plan].compiled_length = compiled_length; builder->plans[plan].first = first; builder->plans[plan].count = count; builder->plans[plan].required = (uint64_t)ks_lua_builder_blob_u32(compiled + 4u) | ((uint64_t)ks_lua_builder_blob_u32(compiled + 8u) << 32u); builder->plans[plan].aliases = (descriptor & UINT32_C(2147483648)) != 0u; builder->plans[plan].defaults = (descriptor & UINT32_C(1073741824)) != 0u; builder->plans[plan].factory = (descriptor & UINT32_C(536870912)) != 0u; lua_settop(L, top); return plan; } }
    lua_settop(L, top); int order = ks_lua_builder_shape_marker(L, builder, shape_index, 5);
    if (lua_type(L, order) == 5) {
        size_t count = lua_objlen(L, order); if (count > 64u - builder->key_count) { lua_settop(L, top); return UINT32_MAX; }
        for (size_t at = 1u; at <= count; ++at) { lua_rawgeti(L, order, (int)at); if (lua_type(L, -1) != 4) { lua_settop(L, top); builder->key_count = first; return UINT32_MAX; } ks_lua_builder_add_shape_key(L, builder, -1); lua_settop(L, lua_gettop(L) - 1); }
    } else {
        lua_settop(L, top); lua_pushnil(L);
        while (lua_next(L, shape_index) != 0) {
            if (lua_type(L, -2) == 4 && !(lua_type(L, -1) == 1 && !lua_toboolean(L, -1))) {
                if (builder->key_count >= 64u) { lua_settop(L, top); builder->key_count = first; return UINT32_MAX; }
                ks_lua_builder_add_shape_key(L, builder, -2);
            }
            lua_settop(L, lua_gettop(L) - 1);
        }
    }
    lua_settop(L, top);
    uint32_t plan = builder->plan_count++; builder->plans[plan].identity = identity; builder->plans[plan].compiled = NULL; builder->plans[plan].compiled_length = 0u; builder->plans[plan].first = first; builder->plans[plan].count = builder->key_count - first; builder->plans[plan].required = 0u; int aliases = ks_lua_builder_shape_marker(L, builder, shape_index, 1); builder->plans[plan].aliases = lua_type(L, aliases) == 5; lua_settop(L, top); int defaults = ks_lua_builder_shape_marker(L, builder, shape_index, 8); builder->plans[plan].defaults = lua_type(L, defaults) == 5; lua_settop(L, top); int factory = ks_lua_builder_shape_marker(L, builder, shape_index, 12); builder->plans[plan].factory = lua_type(L, factory) == 6; lua_settop(L, top); return plan;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_open(lua_State *L, KsLuaBuilder *builder, uint32_t kind, uint32_t capacity, int eager) {
    if (!eager) { ks_lua_builder_prepare(L, builder); }
    if (builder->depth >= builder->frame_capacity) { return luaL_error(L, "AOT value stream nesting exceeds its authored capacity"); }
    if (builder->depth == 16u && builder->frames == NULL) { ks_lua_builder_ensure_frames(L, builder); }
    if (capacity > (uint32_t)INT_MAX) { return luaL_error(L, "AOT value stream capacity exceeds C API range"); }
    if (!lua_checkstack(L, 4)) { return luaL_error(L, "AOT builder Lua stack exhausted"); }
    uint32_t mode = eager ? KS_LUA_BUILD_ALL : builder->pending_mode; int shape_index = 0;
    if (!eager && mode == KS_LUA_BUILD_OBJECT) {
        if (builder->pending_scalar != 0) { return luaL_error(L, "pull scalar shape %d matched a container value", builder->pending_scalar); }
        int shape = builder->pending_shape_index; int type = lua_type(L, shape);
        if (type == 1) { mode = lua_toboolean(L, shape) ? KS_LUA_BUILD_ALL : KS_LUA_BUILD_SKIP; }
        else if (type == 3) { return luaL_error(L, "pull scalar shape matched a container value"); }
        else if (type != 5) { return luaL_error(L, "pull shape entries must be true, false, object shapes, or array shapes"); }
        else {
            lua_pushvalue(L, builder->array_shape_marker_index); lua_rawget(L, shape); int item = lua_gettop(L);
            if (kind == 5u) { if (lua_type(L, item) == 0) { return luaL_error(L, "pull object shape matched an array value"); } mode = KS_LUA_BUILD_ARRAY; shape_index = item; }
            else { if (lua_type(L, item) != 0) { return luaL_error(L, "pull array shape matched an object value"); } lua_settop(L, item - 1); mode = KS_LUA_BUILD_OBJECT; shape_index = shape; }
        }
    }
    if (!eager && (mode == KS_LUA_BUILD_ALL || mode == KS_LUA_BUILD_SKIP)) { ks_lua_builder_clear_pending(L, builder); }
    else if (!eager) {
        if (mode == KS_LUA_BUILD_OBJECT && !builder->pending_shape_owned) { lua_pushvalue(L, shape_index); shape_index = lua_gettop(L); }
        if (mode == KS_LUA_BUILD_ARRAY && builder->pending_shape_owned) { int wrapper = builder->pending_shape_index; lua_remove(L, wrapper); if (shape_index > wrapper) { shape_index -= 1; } }
        builder->pending_shape_owned = 0; builder->pending_shape_index = 0; builder->pending_mode = KS_LUA_BUILD_PENDING;
    }
    uint32_t plan = !eager && mode == KS_LUA_BUILD_OBJECT ? ks_lua_builder_shape_plan(L, builder, shape_index) : UINT32_MAX;
    uint32_t object_capacity = plan == UINT32_MAX ? capacity : builder->plans[plan].count;
    if (mode != KS_LUA_BUILD_SKIP) { lua_createtable(L, kind == 5u ? (int)capacity : 0, kind == 6u ? (int)object_capacity : 0); }
    KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, builder->depth++);
    frame->table_index = mode == KS_LUA_BUILD_SKIP ? 0 : lua_gettop(L); frame->shape_index = shape_index; frame->kind = kind; frame->next = 1u; frame->count = 0u; frame->mode = mode; frame->plan = plan; frame->expected = 0u; frame->seen = 0u; frame->expects_key = kind == 6u; frame->aliases = plan != UINT32_MAX && builder->plans[plan].aliases; frame->tuple = 0; if (kind == 5u && mode == KS_LUA_BUILD_ARRAY && lua_type(L, shape_index) == 5) { int top = lua_gettop(L), tuple = ks_lua_builder_shape_marker(L, builder, shape_index, 13); frame->tuple = lua_toboolean(L, tuple); lua_settop(L, top); } if (kind == 6u && mode == KS_LUA_BUILD_OBJECT && plan == UINT32_MAX) { int aliases = ks_lua_builder_shape_marker(L, builder, shape_index, 1); frame->aliases = lua_type(L, aliases) == 5; lua_settop(L, frame->table_index); }
    return 1;
}
static inline __attribute__((always_inline, unused)) uint32_t ks_lua_builder_query(lua_State *L, KsLuaBuilder *builder, uint32_t query) {
    if (query == 0u) { return builder->depth; }
    if (builder->depth == 0u) { if (query == 3u) { return 0u; } luaL_error(L, "AOT value stream has no current container"); return 0u; }
    KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, builder->depth - 1u);
    if (query == 1u) { return frame->kind; }
    return query == 3u ? frame->kind | (frame->count > 0u ? 0x100u : 0u) : frame->count;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_key(lua_State *L, KsLuaBuilder *builder) {
    if (builder->depth == 0u) { return luaL_error(L, "AOT value stream key is outside an object"); }
    KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, builder->depth - 1u);
    if (frame->kind != 6u || !frame->expects_key) { return luaL_error(L, "AOT value stream object is not expecting a key"); } frame->expects_key = 0;
    if (frame->mode == KS_LUA_BUILD_SKIP) { lua_settop(L, lua_gettop(L) - 1); builder->pending_mode = KS_LUA_BUILD_SKIP; return 1; }
    if (lua_gettop(L) != frame->table_index + 1) { return luaL_error(L, "AOT value stream key is not above its object"); }
    if (frame->mode == KS_LUA_BUILD_ALL) { builder->pending_mode = KS_LUA_BUILD_ALL; return 1; }
    lua_pushvalue(L, -1); lua_rawget(L, frame->shape_index);
    if (lua_type(L, -1) == 0 || (lua_type(L, -1) == 1 && !lua_toboolean(L, -1))) { lua_settop(L, frame->table_index); builder->pending_mode = KS_LUA_BUILD_SKIP; return 1; }
    { int aliases = ks_lua_builder_shape_marker(L, builder, frame->shape_index, 1); if (lua_type(L, aliases) == 5) { lua_pushvalue(L, frame->table_index + 1); lua_rawget(L, aliases); lua_remove(L, aliases); if (lua_type(L, -1) == 0) { lua_settop(L, lua_gettop(L) - 1); } else { lua_insert(L, frame->table_index + 1); lua_remove(L, frame->table_index + 2); } } else { lua_settop(L, aliases - 1); } }
    builder->pending_shape_index = lua_gettop(L); builder->pending_shape_owned = 1; builder->pending_mode = KS_LUA_BUILD_OBJECT; return 1;
}
static inline __attribute__((always_inline, unused)) uint32_t ks_lua_copy_find_slash16(const unsigned char *input, unsigned char *out) {
#if defined(__aarch64__)
    uint8x16_t bytes = vld1q_u8(input); vst1q_u8(out, bytes);
    const uint8_t powers_data[16] = {1u, 2u, 4u, 8u, 16u, 32u, 64u, 128u, 1u, 2u, 4u, 8u, 16u, 32u, 64u, 128u};
    uint8x16_t powers = vld1q_u8(powers_data), slash = vdupq_n_u8((uint8_t)'\\');
    uint8x16_t matches = vandq_u8(vceqq_u8(bytes, slash), powers);
    return (uint32_t)vaddv_u8(vget_low_u8(matches)) | ((uint32_t)vaddv_u8(vget_high_u8(matches)) << 8u);
#elif defined(__x86_64__) || defined(_M_X64)
    __m128i bytes = _mm_loadu_si128((const __m128i *)input); _mm_storeu_si128((__m128i *)out, bytes);
    __m128i slash = _mm_set1_epi8('\\');
    return (uint32_t)(uint16_t)_mm_movemask_epi8(_mm_cmpeq_epi8(bytes, slash));
#else
    uint32_t bits = 0u; memcpy(out, input, 16u); for (uint32_t at = 0u; at < 16u; ++at) { if (input[at] == '\\') { bits |= UINT32_C(1) << at; } } return bits;
#endif
}
static inline __attribute__((always_inline, unused)) uint32_t ks_lua_copy_find_slash32(const unsigned char *input, unsigned char *out) {
    return ks_lua_copy_find_slash16(input, out) | (ks_lua_copy_find_slash16(input + 16u, out + 16u) << 16u);
}
static KS_UNUSED int ks_lua_builder_validate_escaped_string(lua_State *L, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length) {
    size_t first = (size_t)start, count = (size_t)length; if (first > source_length || count > source_length - first) { return luaL_error(L, "AOT value stream string range is out of bounds"); }
    const unsigned char *input = source + first; size_t at = 0u;
    while (at < count) {
        const unsigned char *slash = (const unsigned char *)memchr(input + at, '\\', count - at); if (slash == NULL) { break; } at = (size_t)(slash - input) + 1u;
        if (at >= count) { return luaL_error(L, "AOT value stream has an incomplete escape"); } unsigned char escaped = input[at++];
        if (escaped == '"' || escaped == '\\' || escaped == '/' || escaped == 'b' || escaped == 'f' || escaped == 'n' || escaped == 'r' || escaped == 't') { continue; }
        if (escaped != 'u') { return luaL_error(L, "AOT value stream has an unknown escape"); }
        uint32_t codepoint = 0u; if (!ks_lua_hex4(input, count, &at, &codepoint)) { return luaL_error(L, "AOT value stream has an invalid Unicode escape"); }
        if (codepoint >= 0xd800u && codepoint <= 0xdbffu) { uint32_t low = 0u; if (at > count || count - at < 2u || input[at] != '\\' || input[at + 1u] != 'u') { return luaL_error(L, "AOT value stream has an unmatched high surrogate"); } at += 2u; if (!ks_lua_hex4(input, count, &at, &low) || low < 0xdc00u || low > 0xdfffu) { return luaL_error(L, "AOT value stream has an invalid low surrogate"); } }
        else if (codepoint >= 0xdc00u && codepoint <= 0xdfffu) { return luaL_error(L, "AOT value stream has an unmatched low surrogate"); }
    }
    return 1;
}
static KS_UNUSED int ks_lua_builder_unescape(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, const unsigned char **decoded, size_t *decoded_length) {
    size_t first = (size_t)start, count = (size_t)length;
    if (first > source_length || count > source_length - first) { return luaL_error(L, "AOT value stream string range is out of bounds"); }
    if (count > (size_t)builder->byte_capacity) { return luaL_error(L, "AOT value stream string exceeds its authored capacity"); }
    const unsigned char *input = source + first; unsigned char *out = ks_lua_builder_bytes(L, builder, length); size_t at = 0u, written = 0u;
        size_t window_start = 0u, window_end = 0u, window_written = 0u; uint32_t pending_slashes = 0u;
        while (at < count) {
            if (pending_slashes == 0u && at < window_end) { size_t literal = window_end - at; memcpy(out + written, input + at, literal); at = window_end; written += literal; continue; }
            if (pending_slashes == 0u) {
                size_t remaining = count - at, window = remaining >= 32u ? 32u : remaining >= 16u || (remaining >= 8u && (size_t)builder->byte_capacity - written >= 16u) ? 16u : remaining, logical = window > remaining ? remaining : window;
                window_start = at; window_end = at + logical; window_written = written;
                if (window == 32u) { pending_slashes = ks_lua_copy_find_slash32(input + at, out + written); }
                else if (window == 16u) { pending_slashes = ks_lua_copy_find_slash16(input + at, out + written); if (logical < 16u) { pending_slashes &= (UINT32_C(1) << logical) - 1u; } }
                else { memcpy(out + written, input + at, window); for (uint32_t lane = 0u; lane < (uint32_t)window; ++lane) { if (input[at + lane] == '\\') { pending_slashes |= UINT32_C(1) << lane; } } }
                if (pending_slashes == 0u) { at = window_end; written += logical; continue; }
            }
            uint32_t slash_lane = (uint32_t)__builtin_ctz(pending_slashes); pending_slashes &= pending_slashes - 1u;
            size_t slash_at = window_start + (size_t)slash_lane; if (slash_at < at) { continue; }
            size_t literal = slash_at - at; if (literal != 0u && (at != window_start || written != window_written)) { memcpy(out + written, input + at, literal); }
            written += literal; at = slash_at + 1u; if (at >= count) { return luaL_error(L, "AOT value stream has an incomplete escape"); }
            unsigned char escaped_byte = input[at++];
            if (escaped_byte == '"' || escaped_byte == '\\' || escaped_byte == '/') { out[written++] = escaped_byte; }
            else if (escaped_byte == 'b') { out[written++] = '\b'; } else if (escaped_byte == 'f') { out[written++] = '\f'; }
            else if (escaped_byte == 'n') { out[written++] = '\n'; } else if (escaped_byte == 'r') { out[written++] = '\r'; } else if (escaped_byte == 't') { out[written++] = '\t'; }
            else if (escaped_byte == 'u') {
                uint32_t codepoint = 0u; if (!ks_lua_hex4(input, count, &at, &codepoint)) { return luaL_error(L, "AOT value stream has an invalid Unicode escape"); }
                if (codepoint >= 0xd800u && codepoint <= 0xdbffu) { uint32_t low = 0u; if (at > count || count - at < 2u || input[at] != '\\' || input[at + 1u] != 'u') { return luaL_error(L, "AOT value stream has an unmatched high surrogate"); } at += 2u; if (!ks_lua_hex4(input, count, &at, &low) || low < 0xdc00u || low > 0xdfffu) { return luaL_error(L, "AOT value stream has an invalid low surrogate"); } codepoint = 0x10000u + (codepoint - 0xd800u) * 0x400u + low - 0xdc00u; }
                else if (codepoint >= 0xdc00u && codepoint <= 0xdfffu) { return luaL_error(L, "AOT value stream has an unmatched low surrogate"); }
                written += ks_lua_utf8(out + written, codepoint);
            } else { return luaL_error(L, "AOT value stream has an unknown escape"); }
        }
    *decoded = out; *decoded_length = written;
    return 1;
}
static KS_UNUSED int ks_lua_builder_unescape_indexed(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, KsLuaScratchU32 *escapes, uint32_t escape_index, uint32_t escape_count, const unsigned char **decoded, size_t *decoded_length) {
    size_t first = (size_t)start, count = (size_t)length; if (first > source_length || count > source_length - first) { return luaL_error(L, "AOT value stream string range is out of bounds"); }
    if (escape_index > escapes->escape_length || escape_count > escapes->escape_length - escape_index) { return luaL_error(L, "AOT value stream escape range is out of bounds"); } if (count > (size_t)builder->byte_capacity) { return luaL_error(L, "AOT value stream string exceeds its authored capacity"); }
    const unsigned char *input = source + first; unsigned char *out = ks_lua_builder_bytes(L, builder, length); size_t at = 0u, written = 0u;
    for (uint32_t item = 0u; item < escape_count; ++item) {
        uint32_t absolute = escapes->words[escapes->capacity - 1u - escape_index - item]; if ((size_t)absolute < first + at || (size_t)absolute >= first + count) { return luaL_error(L, "AOT value stream escape position is invalid"); } size_t slash_at = (size_t)absolute - first;
        size_t literal = slash_at - at; if (literal != 0u) { memcpy(out + written, input + at, literal); } written += literal; at = slash_at + 1u; if (at >= count) { return luaL_error(L, "AOT value stream has an incomplete escape"); } unsigned char escaped_byte = input[at++];
        if (escaped_byte == '"' || escaped_byte == '\\' || escaped_byte == '/') { out[written++] = escaped_byte; }
        else if (escaped_byte == 'b') { out[written++] = '\b'; } else if (escaped_byte == 'f') { out[written++] = '\f'; } else if (escaped_byte == 'n') { out[written++] = '\n'; } else if (escaped_byte == 'r') { out[written++] = '\r'; } else if (escaped_byte == 't') { out[written++] = '\t'; }
        else if (escaped_byte == 'u') {
            uint32_t codepoint = 0u; if (!ks_lua_hex4(input, count, &at, &codepoint)) { return luaL_error(L, "AOT value stream has an invalid Unicode escape"); }
            if (codepoint >= 0xd800u && codepoint <= 0xdbffu) { uint32_t low = 0u; if (at > count || count - at < 2u || input[at] != '\\' || input[at + 1u] != 'u') { return luaL_error(L, "AOT value stream has an unmatched high surrogate"); } if (item + 1u >= escape_count || escapes->words[escapes->capacity - 1u - escape_index - item - 1u] != start + (uint32_t)at) { return luaL_error(L, "AOT value stream surrogate escape metadata is invalid"); } item += 1u; at += 2u; if (!ks_lua_hex4(input, count, &at, &low) || low < 0xdc00u || low > 0xdfffu) { return luaL_error(L, "AOT value stream has an invalid low surrogate"); } codepoint = 0x10000u + (codepoint - 0xd800u) * 0x400u + low - 0xdc00u; }
            else if (codepoint >= 0xdc00u && codepoint <= 0xdfffu) { return luaL_error(L, "AOT value stream has an unmatched low surrogate"); }
            written += ks_lua_utf8(out + written, codepoint);
        } else { return luaL_error(L, "AOT value stream has an unknown escape"); }
    }
    if (at < count) { memcpy(out + written, input + at, count - at); written += count - at; } *decoded = out; *decoded_length = written; return 1;
}
static KS_UNUSED int ks_lua_builder_escaped_string(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, int publish) {
    const unsigned char *decoded = NULL; size_t decoded_length = 0u;
    ks_lua_builder_unescape(L, builder, source, source_length, start, length, &decoded, &decoded_length);
    if (publish) { lua_pushlstring(L, (const char *)decoded, decoded_length); } return 1;
}
static KS_UNUSED KsLuaBuilder ks_lua_eager_builder_new(lua_State *L, int null_index, int array_marker_index, int object_marker_index, uint32_t max_depth, uint32_t byte_capacity) {
    return ks_lua_builder_new(L, null_index, array_marker_index, object_marker_index, max_depth, byte_capacity, 0, 0, 0);
}
static KS_UNUSED int ks_lua_builder_select_key(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, int escaped, KsLuaScratchU32 *escape_positions, uint32_t escape_index, uint32_t escape_count);
static inline __attribute__((always_inline, unused)) int ks_lua_builder_string(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, int escaped, int key, int eager);
static inline __attribute__((always_inline, unused)) int ks_lua_builder_string_escapes(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, KsLuaScratchU32 *escapes, uint32_t escape_index, uint32_t escape_count, int key, int eager) {
    if (length < 64u) { return ks_lua_builder_string(L, builder, source, source_length, start, length, 1, key, eager); }
    if (key) { return ks_lua_builder_select_key(L, builder, source, source_length, start, length, 1, escapes, escape_index, escape_count); }
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (wanted) { ks_lua_builder_scalar_validate(L, builder, eager, 2, 0.0); const unsigned char *decoded = NULL; size_t decoded_length = 0u; ks_lua_builder_unescape_indexed(L, builder, source, source_length, start, length, escapes, escape_index, escape_count, &decoded, &decoded_length); lua_pushlstring(L, (const char *)decoded, decoded_length); } else { const unsigned char *ignored = NULL; size_t ignored_length = 0u; ks_lua_builder_unescape_indexed(L, builder, source, source_length, start, length, escapes, escape_index, escape_count, &ignored, &ignored_length); } return ks_lua_builder_complete(L, builder, wanted, eager);
}
static KS_UNUSED int ks_lua_builder_select_entry(lua_State *L, KsLuaBuilder *builder, KsLuaBuildFrame *frame, const unsigned char *key, size_t key_length) {
    int entry = lua_gettop(L);
    if (frame->aliases) { int aliases = ks_lua_builder_shape_marker(L, builder, frame->shape_index, 1); lua_pushlstring(L, (const char *)key, key_length); lua_rawget(L, aliases); lua_remove(L, aliases); if (lua_type(L, -1) == 0) { lua_settop(L, lua_gettop(L) - 1); lua_pushlstring(L, (const char *)key, key_length); } lua_insert(L, entry); }
    builder->pending_shape_index = lua_gettop(L); builder->pending_shape_owned = 1; builder->pending_mode = KS_LUA_BUILD_OBJECT; return 1;
}
static KS_UNUSED int ks_lua_builder_select_known(lua_State *L, KsLuaBuilder *builder, KsLuaBuildFrame *frame, const unsigned char *key, size_t key_length) {
    lua_pushlstring(L, (const char *)key, key_length); if (!frame->aliases) { lua_pushvalue(L, -1); } lua_rawget(L, frame->shape_index); return ks_lua_builder_select_entry(L, builder, frame, key, key_length);
}
static KS_UNUSED int ks_lua_builder_select_planned(lua_State *L, KsLuaBuilder *builder, KsLuaBuildFrame *frame, uint32_t index, const KsLuaShapeKey *key) {
    frame->seen |= UINT64_C(1) << index;
    if (frame->aliases) { lua_rawgeti(L, frame->shape_index, -((int)index + 1)); if (lua_type(L, -1) == 0) { lua_settop(L, lua_gettop(L) - 1); lua_pushlstring(L, key->bytes, key->length); } } else { lua_pushlstring(L, key->bytes, key->length); } if (key->scalar != 0) { builder->pending_shape_index = 0; builder->pending_shape_owned = 0; builder->pending_scalar = key->scalar; builder->pending_mode = KS_LUA_BUILD_OBJECT; return 1; } lua_rawgeti(L, frame->shape_index, (int)index + 1);
    if (lua_type(L, -1) == 0) { lua_settop(L, frame->table_index); return ks_lua_builder_select_known(L, builder, frame, (const unsigned char *)key->bytes, key->length); } builder->pending_shape_index = lua_gettop(L); builder->pending_shape_owned = 1; builder->pending_mode = KS_LUA_BUILD_OBJECT; return 1;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_shape_key_matches(const KsLuaShapeKey *shape_key, const unsigned char *key, size_t key_length, uint64_t packed, uint32_t hash, int escaped) {
    if (shape_key->length != key_length) { return 0; } if (!escaped && key_length <= 7u) { return shape_key->packed == packed; } if (key_length > 7u && shape_key->hash != hash) { return 0; } return memcmp(shape_key->bytes, key, key_length) == 0;
}
static KS_UNUSED int ks_lua_builder_select_key(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, int escaped, KsLuaScratchU32 *escape_positions, uint32_t escape_index, uint32_t escape_count) {
    size_t first = (size_t)start, key_length = (size_t)length;
    if (first > source_length || key_length > source_length - first) { return luaL_error(L, "AOT value stream string range is out of bounds"); }
    if (builder->depth == 0u) { return luaL_error(L, "AOT value stream key is outside an object"); }
    KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, builder->depth - 1u);
    if (frame->kind != 6u || !frame->expects_key) { return luaL_error(L, "AOT value stream object is not expecting a key"); } frame->expects_key = 0;
    if (frame->mode == KS_LUA_BUILD_SKIP) { if (escaped) { ks_lua_builder_validate_escaped_string(L, source, source_length, start, length); } builder->pending_mode = KS_LUA_BUILD_SKIP; return 1; }
    if (frame->mode == KS_LUA_BUILD_ALL) {
        if (escaped) { ks_lua_builder_escaped_string(L, builder, source, source_length, start, length, 1); } else { lua_pushlstring(L, (const char *)(source + first), key_length); }
        builder->pending_mode = KS_LUA_BUILD_ALL; return 1;
    }
    const unsigned char *key = source + first;
    if (escaped) {
        if (escape_positions != NULL) { ks_lua_builder_unescape_indexed(L, builder, source, source_length, start, length, escape_positions, escape_index, escape_count, &key, &key_length); } else { ks_lua_builder_unescape(L, builder, source, source_length, start, length, &key, &key_length); }
        frame = ks_lua_builder_frame(builder, builder->depth - 1u);
    }
    int table_index = frame->table_index;
    if (frame->plan != UINT32_MAX) {
        KsLuaShapePlan *plan = &builder->plans[frame->plan];
        uint64_t packed = 0u; uint32_t hash = key_length > 7u ? ks_lua_builder_key_hash(key, key_length) : 0u; if (!escaped && key_length <= 7u && first + key_length < source_length) { memcpy(&packed, key, key_length + 1u); }
        uint32_t expected = frame->expected < plan->count ? frame->expected : 0u;
        if (plan->count != 0u) { KsLuaShapeKey shape_key; if (!ks_lua_builder_plan_key(builder, plan, expected, &shape_key)) { return luaL_error(L, "AOT serde key plan is malformed"); } if (ks_lua_builder_shape_key_matches(&shape_key, key, key_length, packed, hash, escaped)) { frame->expected = expected + 1u; return ks_lua_builder_select_planned(L, builder, frame, expected, &shape_key); } }
        for (uint32_t index = 0u; index < plan->count; ++index) {
            if (index == expected) { continue; }
            KsLuaShapeKey shape_key; if (!ks_lua_builder_plan_key(builder, plan, index, &shape_key)) { return luaL_error(L, "AOT serde key plan is malformed"); }
            if (ks_lua_builder_shape_key_matches(&shape_key, key, key_length, packed, hash, escaped)) {
                frame->expected = index + 1u; return ks_lua_builder_select_planned(L, builder, frame, index, &shape_key);
            }
        }
    } else {
        lua_pushnil(L);
        while (lua_next(L, frame->shape_index) != 0) {
            if (lua_type(L, -2) == 4) {
                size_t shape_length = 0u; const char *shape_key = lua_tolstring(L, -2, &shape_length);
                if (shape_length == key_length && memcmp(shape_key, key, key_length) == 0) {
                    if (lua_type(L, -1) == 1 && !lua_toboolean(L, -1)) { lua_settop(L, table_index); builder->pending_mode = KS_LUA_BUILD_SKIP; return 1; }
                    lua_settop(L, table_index); return ks_lua_builder_select_known(L, builder, frame, key, key_length);
                }
            }
            lua_settop(L, lua_gettop(L) - 1);
        }
    }
    lua_settop(L, table_index); int wildcard = ks_lua_builder_shape_marker(L, builder, frame->shape_index, 2);
    if (lua_type(L, wildcard) != 0) { lua_pushlstring(L, (const char *)key, key_length); lua_insert(L, wildcard); return ks_lua_builder_select_entry(L, builder, frame, key, key_length); }
    lua_settop(L, table_index); int reject = ks_lua_builder_shape_marker(L, builder, frame->shape_index, 3);
    if (lua_toboolean(L, reject)) { lua_pushlstring(L, (const char *)key, key_length); return luaL_error(L, "nupp: unknown member %s", lua_tolstring(L, -1, NULL)); }
    lua_settop(L, table_index); builder->pending_mode = KS_LUA_BUILD_SKIP; return 1;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_string(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, int escaped, int key, int eager) {
    size_t first = (size_t)start, count = (size_t)length;
    if (first > source_length || count > source_length - first) { return luaL_error(L, "AOT value stream string range is out of bounds"); }
    if (key) {
        return ks_lua_builder_select_key(L, builder, source, source_length, start, length, escaped, NULL, 0u, 0u);
    }
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager);
    if (wanted) { ks_lua_builder_scalar_validate(L, builder, eager, 2, 0.0); } if (escaped && wanted) { ks_lua_builder_escaped_string(L, builder, source, source_length, start, length, 1); } else if (escaped) { ks_lua_builder_validate_escaped_string(L, source, source_length, start, length); } else if (wanted) { lua_pushlstring(L, (const char *)(source + first), count); }
    return ks_lua_builder_complete(L, builder, wanted, eager);
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_number_slice(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, int eager) {
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (!wanted) { return ks_lua_builder_complete(L, builder, 0, eager); }
    double value = ks_lua_number_slice(L, source, source_length, start, length, "value stream"); ks_lua_builder_scalar_validate(L, builder, eager, 3, value); lua_pushnumber(L, value); return ks_lua_builder_complete(L, builder, 1, eager);
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_integer_slice(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, int eager) {
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (!wanted) { return ks_lua_builder_complete(L, builder, 0, eager); }
    double value = ks_lua_integer_slice(L, source, source_length, start, length); ks_lua_builder_scalar_validate(L, builder, eager, 3, value); lua_pushnumber(L, value); return ks_lua_builder_complete(L, builder, 1, eager);
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_number(lua_State *L, KsLuaBuilder *builder, double value, int eager) {
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (wanted) { ks_lua_builder_scalar_validate(L, builder, eager, 3, value); lua_pushnumber(L, value); } return ks_lua_builder_complete(L, builder, wanted, eager);
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_integer64(lua_State *L, KsLuaBuilder *builder, uint64_t magnitude, int negative, int eager) { int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (wanted) { double unsigned_value = (double)magnitude; double value = negative ? -unsigned_value : unsigned_value; ks_lua_builder_scalar_validate(L, builder, eager, 3, value); lua_pushnumber(L, value); } return ks_lua_builder_complete(L, builder, wanted, eager); }
static inline __attribute__((always_inline, unused)) int ks_lua_builder_decimal64(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t length, uint64_t magnitude, int32_t exponent, int negative, int exact, int eager) { int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (wanted) { double value = ks_lua_decimal64_value(L, source, source_length, start, length, magnitude, exponent, negative, exact); ks_lua_builder_scalar_validate(L, builder, eager, 3, value); lua_pushnumber(L, value); } return ks_lua_builder_complete(L, builder, wanted, eager); }
static inline __attribute__((always_inline, unused)) int ks_json_eight_digits(const unsigned char *source, uint32_t *value) {
    uint64_t word; memcpy(&word, source, sizeof(word)); if (((word & UINT64_C(0xf0f0f0f0f0f0f0f0)) | (((word + UINT64_C(0x0606060606060606)) & UINT64_C(0xf0f0f0f0f0f0f0f0)) >> 4u)) != UINT64_C(0x3333333333333333)) { return 0; }
    word = (word & UINT64_C(0x0f0f0f0f0f0f0f0f)) * UINT64_C(2561) >> 8u; word = (word & UINT64_C(0x00ff00ff00ff00ff)) * UINT64_C(6553601) >> 16u; *value = (uint32_t)((word & UINT64_C(0x0000ffff0000ffff)) * UINT64_C(42949672960001) >> 32u); return 1;
}
static KS_UNUSED uint32_t ks_lua_builder_number_token(lua_State *L, KsLuaBuilder *builder, const unsigned char *source, size_t source_length, uint32_t start, uint32_t limit, int eager) {
    uint32_t at = start, magnitude_digits = 0u, fraction_digits = 0u; uint64_t magnitude = 0u; int negative = 0, exact = 1, integer_token = 1; int64_t explicit_exponent = 0;
    if ((size_t)limit > source_length || limit >= UINT32_C(2147483648) || start >= limit) { return start + 1u; } if (source[at] == '-') { negative = 1; at += 1u; if (at >= limit) { return at + 1u; } }
    if (source[at] == '0') { magnitude_digits = 1u; at += 1u; if (at < limit && (unsigned)(source[at] - '0') <= 9u) { return at + 1u; } }
    else if ((unsigned)(source[at] - '1') <= 8u) {
        while (limit - at >= 8u && (unsigned)(source[at + 7u] - '0') <= 9u) { uint32_t eight; if (!ks_json_eight_digits(source + at, &eight)) { break; } if (exact && magnitude_digits <= 11u) { magnitude = magnitude * UINT64_C(100000000) + (uint64_t)eight; } else { exact = 0; } magnitude_digits += 8u; at += 8u; }
        while (at < limit && (unsigned)(source[at] - '0') <= 9u) { if (exact && magnitude_digits < 19u) { magnitude = magnitude * 10u + (uint64_t)(source[at] - '0'); } else { exact = 0; } magnitude_digits += 1u; at += 1u; }
    } else { return at + 1u; }
    if (at < limit && source[at] == '.') {
        integer_token = 0; at += 1u; uint32_t fraction_start = at;
        while (limit - at >= 8u && (unsigned)(source[at + 7u] - '0') <= 9u) { uint32_t eight; if (!ks_json_eight_digits(source + at, &eight)) { break; } if (exact && magnitude_digits <= 11u) { magnitude = magnitude * UINT64_C(100000000) + (uint64_t)eight; } else { exact = 0; } magnitude_digits += 8u; fraction_digits += 8u; at += 8u; }
        while (at < limit && (unsigned)(source[at] - '0') <= 9u) { if (exact && magnitude_digits < 19u) { magnitude = magnitude * 10u + (uint64_t)(source[at] - '0'); } else { exact = 0; } magnitude_digits += 1u; fraction_digits += 1u; at += 1u; }
        if (at == fraction_start) { return at + 1u; }
    }
    if (at < limit && (source[at] == 'e' || source[at] == 'E')) {
        integer_token = 0; at += 1u; int exponent_negative = 0; if (at < limit && (source[at] == '+' || source[at] == '-')) { exponent_negative = source[at] == '-'; at += 1u; } uint32_t exponent_start = at;
        while (at < limit && (unsigned)(source[at] - '0') <= 9u) { if (explicit_exponent < INT64_C(1000000)) { explicit_exponent = explicit_exponent * 10 + (int64_t)(source[at] - '0'); } at += 1u; }
        if (at == exponent_start) { return at + 1u; } if (exponent_negative) { explicit_exponent = -explicit_exponent; }
    }
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (wanted) { uint32_t length = at - start; double value; if (integer_token && exact) { value = (double)magnitude; if (negative) { value = -value; } } else if (integer_token) { value = ks_lua_number_slice(L, source, source_length, start, length, "value stream integer"); } else { int64_t decimal_exponent = explicit_exponent - (int64_t)fraction_digits; int exponent_fits = decimal_exponent >= INT32_MIN && decimal_exponent <= INT32_MAX; value = ks_lua_decimal64_value(L, source, source_length, start, length, magnitude, exponent_fits ? (int32_t)decimal_exponent : 0, negative, exact && exponent_fits); } ks_lua_builder_scalar_validate(L, builder, eager, 3, value); lua_pushnumber(L, value); }
    ks_lua_builder_complete(L, builder, wanted, eager); return UINT32_C(2147483648) | at;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_pushed_scalar(lua_State *L, KsLuaBuilder *builder, int eager) {
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (wanted) { int actual = lua_type(L, -1); double value = actual == 3 ? lua_tonumber(L, -1) : 0.0; ks_lua_builder_scalar_validate(L, builder, eager, actual, value); } else { lua_settop(L, lua_gettop(L) - 1); } return ks_lua_builder_complete(L, builder, wanted, eager);
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_boolean(lua_State *L, KsLuaBuilder *builder, int value, int eager) {
    int wanted = ks_lua_builder_scalar_wanted(L, builder, eager); if (wanted) { ks_lua_builder_scalar_validate(L, builder, eager, 1, 0.0); lua_pushboolean(L, value); } return ks_lua_builder_complete(L, builder, wanted, eager);
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_null(lua_State *L, KsLuaBuilder *builder, int eager) {
    int wanted = ks_lua_builder_null_wanted(L, builder, eager); if (wanted) { lua_pushvalue(L, builder->null_index); } return ks_lua_builder_complete(L, builder, wanted, eager);
}
static KS_UNUSED int ks_lua_builder_finish_object(lua_State *L, KsLuaBuilder *builder, KsLuaBuildFrame *frame) {
    int table_index = frame->table_index; int required = ks_lua_builder_shape_marker(L, builder, frame->shape_index, 7);
    if (lua_type(L, required) == 5) { size_t count = lua_objlen(L, required); for (size_t at = 1u; at <= count; ++at) { lua_rawgeti(L, required, (int)at); lua_pushvalue(L, -1); lua_rawget(L, table_index); if (lua_type(L, -1) == 0) { return luaL_error(L, "nupp: missing required member %s", lua_tolstring(L, -2, NULL)); } lua_settop(L, lua_gettop(L) - 2); } }
    lua_settop(L, table_index); if (frame->plan != UINT32_MAX && builder->plans[frame->plan].compiled != NULL) { lua_rawgeti(L, frame->shape_index, -66); } else { ks_lua_builder_shape_marker(L, builder, frame->shape_index, 8); } int defaults = lua_gettop(L);
    if (lua_type(L, defaults) == 5) { lua_pushnil(L); while (lua_next(L, defaults) != 0) { lua_pushvalue(L, -2); lua_rawget(L, table_index); if (lua_type(L, -1) == 0) { lua_settop(L, lua_gettop(L) - 1); lua_pushvalue(L, -2); lua_pushvalue(L, -2); lua_rawset(L, table_index); } else { lua_settop(L, lua_gettop(L) - 1); } lua_settop(L, lua_gettop(L) - 1); } }
    lua_settop(L, table_index); return 1;
}
static KS_UNUSED int ks_lua_builder_finalize_object(lua_State *L, KsLuaBuilder *builder, KsLuaBuildFrame *frame) {
    int table_index = frame->table_index; if (frame->plan != UINT32_MAX && builder->plans[frame->plan].compiled != NULL) { lua_rawgeti(L, frame->shape_index, -67); } else { ks_lua_builder_shape_marker(L, builder, frame->shape_index, 12); } int factory = lua_gettop(L); if (lua_type(L, factory) == 0) { lua_settop(L, table_index); return 0; } if (lua_type(L, factory) != 6) { return luaL_error(L, "nupp: serde factory is not callable"); } lua_pushvalue(L, table_index); lua_call(L, 1, 1); lua_remove(L, table_index); return 1;
}
static inline __attribute__((always_inline, unused)) int ks_lua_builder_close(lua_State *L, KsLuaBuilder *builder, int eager) {
    if (builder->depth == 0u) { return luaL_error(L, "AOT value stream close has no container"); }
    KsLuaBuildFrame *frame = ks_lua_builder_frame(builder, builder->depth - 1u);
    if (frame->kind == 6u && !frame->expects_key) { return luaL_error(L, "AOT value stream object has an unmatched key"); }
    if (eager) { int marker_index = frame->kind == 5u ? builder->array_marker_index : builder->object_marker_index; if (marker_index != 0) { lua_pushvalue(L, marker_index); lua_setmetatable(L, frame->table_index); } builder->depth -= 1u; return ks_lua_builder_complete(L, builder, 1, 1); }
    int pushed = frame->mode != KS_LUA_BUILD_SKIP;
    if (pushed && !eager && lua_gettop(L) != frame->table_index) { return luaL_error(L, "AOT value stream container is not on top"); }
    if (pushed) { int marker_index = frame->kind == 5u ? builder->array_marker_index : builder->object_marker_index; if (frame->kind == 5u && frame->mode == KS_LUA_BUILD_ARRAY && frame->tuple && frame->count != (uint32_t)lua_objlen(L, frame->shape_index)) { return luaL_error(L, "nupp: tuple length does not match"); } if (frame->kind == 6u && frame->mode == KS_LUA_BUILD_OBJECT) { if (frame->plan != UINT32_MAX) { KsLuaShapePlan *plan = &builder->plans[frame->plan]; uint64_t missing = plan->required & ~frame->seen; if (missing != 0u) { KsLuaShapeKey key; uint32_t index = (uint32_t)__builtin_ctzll(missing); if (!ks_lua_builder_plan_key(builder, plan, index, &key)) { return luaL_error(L, "AOT serde key plan is malformed"); } lua_pushlstring(L, key.bytes, key.length); return luaL_error(L, "nupp: missing required member %s", lua_tolstring(L, -1, NULL)); } if (plan->defaults) { ks_lua_builder_finish_object(L, builder, frame); } if (plan->factory && ks_lua_builder_finalize_object(L, builder, frame)) { marker_index = 0; } } else { ks_lua_builder_finish_object(L, builder, frame); if (ks_lua_builder_finalize_object(L, builder, frame)) { marker_index = 0; } } if (marker_index != 0) { if (frame->plan != UINT32_MAX && builder->plans[frame->plan].compiled != NULL) { lua_rawgeti(L, frame->shape_index, -65); } else { ks_lua_builder_shape_marker(L, builder, frame->shape_index, 4); } int serde_mt = lua_gettop(L); if (lua_type(L, serde_mt) != 0) { lua_setmetatable(L, frame->table_index); marker_index = 0; } else { lua_settop(L, serde_mt - 1); } } } if (marker_index != 0) { lua_pushvalue(L, marker_index); lua_setmetatable(L, frame->table_index); } }
    int shape_index = frame->shape_index; builder->depth -= 1u; if (shape_index != 0) { lua_remove(L, shape_index); } return ks_lua_builder_complete(L, builder, pushed, eager);
}
static KS_UNUSED int ks_lua_builder_finish(lua_State *L, KsLuaBuilder *builder) {
    if (builder->depth != 0u) { return luaL_error(L, "AOT value stream has an unclosed container"); }
    if (!builder->root_done || builder->root_index == 0) { return luaL_error(L, "AOT value stream has no root"); }
    if (builder->root_index != lua_gettop(L)) { return luaL_error(L, "AOT value stream root is not on top"); }
    return 1;
}

