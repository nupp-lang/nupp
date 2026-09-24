/* The standalone executable's main: the host's checks, with the AOT code,
   LuaJIT and the runtime all linked in statically by the component's lld.
   Built ahead of time with the product, like the runtime objects. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct lua_State lua_State;
typedef int (*lua_CFunction)(lua_State *);
lua_State *luaL_newstate(void);
void luaL_openlibs(lua_State *);
int luaL_loadstring(lua_State *, const char *);
int lua_pcall(lua_State *, int, int, int);
void lua_pushcclosure(lua_State *, lua_CFunction, int);
void lua_createtable(lua_State *, int, int);
void lua_setfield(lua_State *, int, const char *);
const char *lua_tolstring(lua_State *, int, size_t *);
int lua_toboolean(lua_State *, int);
void lua_pushboolean(lua_State *, int);

int nupp_aot_rows(lua_State *);
int nupp_aot_object(lua_State *);
int nupp_aot_stream(lua_State *);
int KS_REGISTER(lua_State *);
void nupp_aot_map(double *, const double *, double, double, size_t);
void nupp_aot_refine(double *, const double *, size_t);
void nupp_aot_explicitMap(double *, const double *, double, double, size_t, size_t);
void nupp_aot_explicitRefine(double *, const double *, size_t, size_t);
double nupp_aot_explicitAlgebraic(const double *, const double *, size_t, size_t);
void nupp_aot_waves(double *, const double *, double, size_t);
void ks_map(double *, const double *, double, double, size_t);
void ks_refine(double *, const double *, size_t);
void ks_explicit_map(double *, const double *, double, double, size_t, size_t);
void ks_explicit_refine(double *, const double *, size_t, size_t);
double ks_explicit_algebraic(const double *, const double *, size_t, size_t);
void ks_waves(double *, const double *, double, size_t);

static const char *harness =
    "local ours, theirs, quick = ...\n"
    "local function ser(v)\n"
    "  local t = type(v)\n"
    "  if t == \"table\" then\n"
    "    local keys = {}\n"
    "    for k in pairs(v) do keys[#keys + 1] = k end\n"
    "    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)\n"
    "    local parts = {}\n"
    "    for _, k in ipairs(keys) do parts[#parts + 1] = ser(k) .. \"=\" .. ser(v[k]) end\n"
    "    return \"{\" .. table.concat(parts, \",\") .. \"}\"\n"
    "  elseif t == \"string\" then\n"
    "    return string.format(\"%q\", v)\n"
    "  end\n"
    "  return tostring(v)\n"
    "end\n"
    "local function pack(...) return {n = select(\"#\", ...), ...} end\n"
    "local function run(f, ...)\n"
    "  local r = pack(pcall(f, ...))\n"
    "  local parts = {}\n"
    "  for i = 1, r.n do parts[i] = ser(r[i]) end\n"
    "  local text = table.concat(parts, \" | \")\n"
    "  if #text > 120 then text = text:sub(1, 117) .. \"...\" end\n"
    "  return text, r[1]\n"
    "end\n"
    "local cases = {\n"
    "  {\"rows\", 0}, {\"rows\", 5}, {\"rows\", 2.5}, {\"rows\", 1000},\n"
    "  {\"rows\", \"x\"}, {\"rows\", -1}, {\"rows\", 1e300},\n"
    "  {\"object\", \"hi\"}, {\"object\", 42}, {\"object\", {}},\n"
    "  {\"stream\", \"abcd12efgh\", \"\\1\\0\\0\\0\", false},\n"
    "  {\"stream\", \"abcd12efgh\", \"\\255\\255\\255\\127\", nil},\n"
    "  {\"stream\", \"ab\", \"x\", nil}, {\"stream\", 1}, {\"stream\", \"abcd1xefgh\", \"abcd\", 0},\n"
    "}\n"
    "if quick then cases = {{\"rows\", \"x\"}, {\"rows\", -1}} end\n"
    "local ok, same, errors = true, 0, 0\n"
    "for _, c in ipairs(cases) do\n"
    "  local a, fine = run(ours[c[1]], unpack(c, 2))\n"
    "  local b = run(theirs[c[1]], unpack(c, 2))\n"
    "  if a ~= b then ok = false else same = same + 1 end\n"
    "  if not fine then errors = errors + 1 end\n"
    "  print((\"  %-6s %-7s(%s) -> %s\"):format(a == b and \"same\" or \"DIFFER\", c[1], ser(c[2]), a))\n"
    "  if a ~= b then print(\"         C -> \" .. b) end\n"
    "end\n"
    "print((\"  %d/%d cases identical to the C entries; %d of them raised through generated frames\"):format(same, #cases, errors))\n"
    "return ok\n";

static double left[65539], right[65539], a[65543], b[65543];

static double call(int k, int ours, size_t n) {
    double *out = ours ? a : b;
    switch (k) {
    case 0: (ours ? nupp_aot_map : ks_map)(out, left, 1.25, -0.5, n); return 0;
    case 1: (ours ? nupp_aot_refine : ks_refine)(out, left, n); return 0;
    case 2: (ours ? nupp_aot_explicitMap : ks_explicit_map)(out, left, 1.25, -0.5, n, n); return 0;
    case 3: (ours ? nupp_aot_explicitRefine : ks_explicit_refine)(out, left, n, n); return 0;
    default: return (ours ? nupp_aot_explicitAlgebraic : ks_explicit_algebraic)(left, right, n, n);
    }
}

int main(void) {
    static const char *names[] = {"map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic"};
    int failures = 0;
    for (int k = 0; k < 5; k++) {
        int ok = 1;
        size_t sizes[21]; int ns = 0;
        for (size_t n = 0; n < 18; n++) sizes[ns++] = n;
        sizes[ns++] = 63; sizes[ns++] = 1000; sizes[ns++] = 65539;
        for (int s = 0; s < ns && ok; s++) {
            size_t n = sizes[s];
            for (size_t i = 0; i < n; i++) { left[i] = (double)(i % 97 + 1) * 0.125; right[i] = (double)(i % 17 + 1) * 0.0625; }
            for (size_t i = 0; i < n + 4; i++) { a[i] = -777.0; b[i] = -777.0; }
            double ra = call(k, 1, n), rb = call(k, 0, n);
            if (memcmp(a, b, (n + 4) * sizeof a[0]) != 0) ok = 0;
            double d = ra - rb, m = rb < 0 ? -rb : rb;
            if ((d < 0 ? -d : d) > 1e-12 * (m > 1 ? m : 1)) ok = 0;
            if (k != 4 && memcmp(&ra, &rb, sizeof ra) != 0) ok = 0;
        }
        printf("  %-18s %s\n", names[k], ok ? "bit-identical to C, n = 0..17, 63, 1000, 65539" : "DIFFER");
        failures += !ok;
    }
    {
        int ok = 1;
        size_t sizes[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1000};
        for (int s = 0; s < 11; s++) {
            size_t n = sizes[s];
            for (size_t i = 0; i < n; i++) left[i] = ((double)i - 400.0) * 0.0125;
            for (size_t i = 0; i < n + 2; i++) { a[i] = -7.0; b[i] = -7.0; }
            nupp_aot_waves(a, left, 0.5, n);
            ks_waves(b, left, 0.5, n);
            if (memcmp(a, b, (n + 2) * sizeof a[0]) != 0) ok = 0;
        }
        printf("  %-18s %s\n", "waves", ok ? "bit-identical to C, n = 0..9, 1000" : "DIFFER");
        failures += !ok;
    }
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    if (luaL_loadstring(L, harness) != 0) return 2;
    lua_createtable(L, 0, 3);
    lua_pushcclosure(L, nupp_aot_rows, 0); lua_setfield(L, -2, "rows");
    lua_pushcclosure(L, nupp_aot_object, 0); lua_setfield(L, -2, "object");
    lua_pushcclosure(L, nupp_aot_stream, 0); lua_setfield(L, -2, "stream");
    lua_pushcclosure(L, KS_REGISTER, 0);
    if (lua_pcall(L, 0, 1, 0) != 0) return 2;
    lua_pushboolean(L, 0);
    if (lua_pcall(L, 3, 1, 0) != 0) { printf("harness: %s\n", lua_tolstring(L, -1, 0)); return 2; }
    int same = lua_toboolean(L, -1);
    printf("lua-builder entries match C: %s\n", same ? "true" : "false");
    failures += !same;
    printf("failures: %d\n", failures);
    return failures != 0;
}
