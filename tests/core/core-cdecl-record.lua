-- Records the VM's C declaration service's answers (nupp.compiler.nativecdecl,
-- over libclang) for the core's to be compared with: every `cdef` block and
-- FFI type string in the repository, the preprocessed stdio.h and pthread.h
-- when cc is there, then the cases below, sent in order to one fresh
-- service. Writes one line per request to the file arg[1] names: the
-- request's JSON, a tab, and the VM's answer's JSON. The guest runner runs
-- it before the corecdecl case (catalog-core-cdecl), in the directory that
-- case then runs in, so the paths libclang spells in its answers agree.
local CASES
do
    local json = require("nupp.serde.internal.json.values")

    local function inspect(text, prelude)
        return {"inspect", json.encode({text = text, prelude = prelude})}
    end

    CASES = {
        {"declare", "typedef struct { float x; } NP;"},
        {"struct", nil, {id = 1}},
        {"declare", "struct Fw; typedef struct Fw *FwP; struct Fw { int a; };"},
        {"declare", "typedef struct Q2 *Q2P;"},
        {"type", "Q2P"},
        {"declare", "void vf(void); int np(); void *vp(void *x);"},
        {"declare", "struct WithAnon { int tag; union { int i; double d; }; struct { char c; } named; int after; };"},
        {"type", "struct WithAnon"},
        {
            "declare",
            "struct Bits { unsigned a : 3; unsigned : 0; unsigned b : 3; unsigned : 5; char c; long long d : 40; };"
        },
        {"type", "struct Bits"},
        {
            "declare",
            "enum Neg { NA = -1, NB = 0x7fffffff }; enum Big { BA = 0xffffffff }; enum Bigger { BB = 0x100000000 };"
        },
        inspect("enum Neg2 { N2 = -1 }; typedef enum { Z } ZT;"),
        {
            "declare",
            "struct Fl { int n; double d[]; }; typedef int ai __attribute__((aligned(8))); struct HasAi { char c; ai x; };"
        },
        {"type", "struct Fl"},
        {"type", "struct HasAi"},
        {"type", "void"},
        {"type", "void *"},
        {"type", "int (int)"},
        {"type", "__int128"},
        {"type", "float _Complex"},
        {"type", "double __attribute__((vector_size(32)))"},
        {"type", "float __attribute__((vector_size(8)))"},
        {"type", "char __attribute__((vector_size(64)))"},
        {"type", "_Float16"},
        {"type", "struct { char c; int : 0; char d; }"},
        {"type", "struct { char c; int : 4; char d; }"},
        {"type", "struct { char c; long long : 0; }"},
        {"type", "struct { char c; int x : 4; }"},
        {"type", "struct { short s : 4; char c; }"},
        {"type", "struct { char a; long long b : 3; char c; }"},
        {"type", "struct { int a : 31; int b : 2; }"},
        {"type", "struct { long long a : 40; int b : 30; }"},
        {"type", "union { char c; int x : 20; }"},
        {"type", "union { char c[5]; short s; }"},
        {"type", "struct {}"},
        {"type", "struct { char c; int x __attribute__((aligned(16))); }"},
        {"type", "struct { char c; int x; } __attribute__((packed))"},
        {"type", "enum { BG1 = 0x100000000 }"},
        {"type", "enum { BG2 = -0x100000000 }"},
        {"type", "enum { BG3 = 0x80000000 }"},
        {"type", "nope_t"},
        {"type", "int[?]"},
        {"type", "int (*)(int, ...)"},
        {"type", "long double"},
        {"type", "char"},
        {"type", "unsigned char*"},
        {"type", "_Bool"},
        {"type", "int[3][2]"},
        {"type", "int[]"},
        {"type", "const char * const"},
        {"type", "volatile int"},
        {"type", "enum { Z1, Z2 = 5 }"},
        {"declare", "this is not C"},
        {"declare", "int f(int)"},
        {"declare", "foo_t g(void);"},
        {"declare", "struct S1 { int a; }; struct S1 { int a; };"},
        {"declare", "struct S2 { struct Nope n; };"},
        {"declare", "int h(int a,);"},
        {"declare", "int x = 3;"},
        {"declare", "int k(void) { return 1; }"},
        {"declare", "typedef int T1; typedef long T1;"},
        {"declare", "struct S3 { int a; int a; };"},
        {"declare", "int arr[-1];"},
        {"declare", "int m(int)\nint n(int);"},
        {"declare", "\n\nint q(int)"},
        inspect(
            "typedef struct Q9 *Q9P; int f9(struct Q8 *p); struct O { struct I { int x; } i; }; struct O2 *makeO2(void);"
        ),
        inspect("struct Inc; typedef struct { int a; } TT; typedef TT TT2;"),
        {
            "declare",
            "typedef unsigned long long ull; typedef signed char sc; typedef unsigned short us; ull fu(sc a, us b, long double c, const volatile int *d, int arr[3], int (*cb)(void), char s[]);"
        },
        {"functions"},
        {"float32", "0.1"},
        {"float32", "16777217"},
        {"float32", "1e40"},
        inspect(
            table.concat(
                {
                    "struct NuppCdeclPoint { double x; double y; };",
                    "void nuppCdeclVisit(void (*visit)(int), unsigned long n);"
                },
                "\n"
            )
        ),
        inspect("struct NuppCdeclArrays { int values[4]; float matrix[2][3]; };"),
        inspect("typedef struct { float x; float y; } NuppCdeclAnonPoint;"),
        inspect(
            "struct NuppCdeclOwned { NuppCdeclPrelude *value; };",
            "typedef struct NuppCdeclPrelude NuppCdeclPrelude;"
        ),
        inspect("struct NuppCdeclForwardTarget { int value; };", "struct NuppCdeclForwardTarget;"),
        inspect(
            table.concat(
                {
                    "enum NuppCdeclStatus { NUPP_CDECL_OK = 0, NUPP_CDECL_LAST = 7 };",
                    "typedef enum { NUPP_CDECL_ANON = 3 } NuppCdeclAnon;"
                },
                "\n"
            )
        ),
        inspect("enum NuppCdeclSigned { NUPP_CDECL_ERR = -1, NUPP_CDECL_NONE = 0 };"),
        inspect("struct NuppCdeclKept { int n; };", {
            "typedef struct NuppCdeclNoSuchThing *NuppCdeclFine;",
            "typedef __nupp_cdecl_never_declared_t NuppCdeclBroken;"
        }),
        inspect({
            "struct NuppCdeclOpaque;",
            "struct NuppCdeclUnsized { struct NuppCdeclOpaque inner; };",
            "int nuppCdeclSurvives(int a);"
        }),
        inspect("struct NuppCdeclWhole { struct NuppCdeclNeverDefined inner; };"),
        inspect(
            table.concat(
                {
                    "struct NuppCdeclAnonMember { int tag; union { int i; double d; }; int after; };",
                    "struct NuppCdeclPadding { unsigned a : 3; unsigned : 0; unsigned b : 3; unsigned : 5; };"
                },
                "\n"
            )
        ),
        inspect(
            table.concat(
                {
                    "typedef float nupp_cdecl_v4 __attribute__((vector_size(16)));",
                    "nupp_cdecl_v4 nuppCdeclVector(double _Complex z);"
                },
                "\n"
            )
        ),
        inspect("struct NuppCdeclFlags { bool on : 1; int level : 4; };"),
        {"type", "struct { uint8_t kind; uint32_t len; uint16_t a : 3; }"},
        inspect("struct __attribute__((packed)) NuppCdeclPacked { uint8_t kind; uint32_t len; };"),
        inspect({
            "int nuppCdeclUnitOne(void);",
            "struct NuppCdeclUnitTwo { int x; };",
            "struct NuppCdeclUnitBroken { struct NuppCdeclUnitNever inner; };"
        }),
        {"declare", "struct Rep { int a; };"},
        {"declare", "struct Rep { int a; };"},
        {"declare", "struct Rep { int a; }; int repf(void);"},
        {"declare", "int repf(void);"},
        {"declare", "int repf(void); struct Rep { int a; };"},
        {"type", "NUPP_CDECL_OK"},
        {"type", "struct Rep *[2]"},
        {"type", "int (*[3])(void)"},
        {"abi"},
        {"declare", "struct RA { int a; };"},
        {"declare", "int rf(void);"},
        {"declare", "struct RA { int a; }; int rf(void);"},
        {"declare", "int rf(void);struct RA{int a;};"},
        {"declare", ""},
        {"declare", "/* only a comment */"},
        {"declare", "// line comment\n"},
        {"declare", "int a1, a2; extern int e1; static int s1;"},
        {"declare", "int ka(a, b);"},
        {"declare", "void (*signal2(int sig, void (*func)(int)))(int);"},
        {"declare", "typedef int fnt(int, char); fnt *fnp; fnt realfn;"},
        {
            "declare",
            "enum Ex { EA = 1 << 3, EB = EA | 2, EC = 'x', ED = sizeof(int) * 2, EE = (EA > EB) ? 10 : 20, EF = ~0, EG = -EA, EH = 7 / 2, EI = -7 % 3 };"
        },
        {"type", "enum Ex"},
        {
            "declare",
            "struct Fp { int (*cb)(void *ctx, int n); void (*vt[3])(void); struct Fp *next; const char *name; };"
        },
        {"type", "struct Fp"},
        {"type", "struct Fp *"},
        {"declare", "union Ub { struct { unsigned lo : 16, hi : 16; } parts; unsigned whole; float f; };"},
        {"type", "union Ub"},
        {"declare", "static inline int inl(int x) { return x * 2; }"},
        {"declare", "_Static_assert(sizeof(int) == 4, \"int\");"},
        {"declare", "struct Arr { char name[16]; int matrix[3][4]; struct Fp fps[2]; } __attribute__((aligned(32)));"},
        {"type", "struct Arr"},
        {"declare", "typedef struct Node { struct Node *left, *right; int value; } Node, *NodeP;"},
        {"type", "Node"},
        {"type", "NodeP"},
        {"type", "Node[?]"},
        {
            "declare",
            "unsigned u1; signed s2; short int si; long int li; long long unsigned int llui; unsigned char uc; char unsigned cu;"
        },
        {"declare", "typedef unsigned long long int ulli_t; typedef const volatile unsigned int cvui_t;"},
        {"type", "ulli_t"},
        {"type", "cvui_t *"},
        {"type", "const char **"},
        {"type", "char *const *"},
        {"declare", "int f1(void); int f1(void); int f1();"},
        {"declare", "int f2(int); long f2(int);"},
        {"declare", "struct Uq; union Uq;"},
        {"declare", "enum Fwd2; enum Fwd2 { FW = 1 };"},
        {"declare", "int va(const char *fmt, ...); void vb(int n, ...);"},
        {"declare", "struct Bad { int x }"},
        {"declare", "struct Bad2 { int x; "},
        {"declare", "int bad3(int x, int y"},
        {"declare", "typedef int;"},
        {"declare", "int 3x;"},
        {"declare", "struct { int anon; };"},
        {"declare", "int arr2[2][-3];"},
        {"declare", "void vv;"},
        {"declare", "struct Inc2 v2;"},
        {"declare", "int arrInc[];"},
        {"declare", "int f3(void) { return 1; } int f3(void) { return 2; }"},
        {"declare", "enum Dup { DA, DA };"},
        {"declare", "struct B2 { int a : 33; };"},
        inspect("int u1(void);\nint u2(void);"),
        inspect({"int okone(void);", "struct BrokenX { int x }", "int oktwo(void);"}),
        {"type", "struct RA"},
        {"type", "union Uq"},
        {"type", "int (*)[4]"},
        {"type", "int *(*)(int)"},
        {"type", "void (*)(void (*)(int))"},
        {"type", "unsigned"},
        {"type", "signed char[2]"},
        {"type", "bool"},
        {"type", "size_t"},
        {"type", "ptrdiff_t"},
        {"type", "int8_t*"},
        {"type", "uint64_t[?]"},
        {"type", "double _Complex"},
        {"type", "struct RA [3]"},
        {"type", "int[0]"},
        {"type", "struct NotThere *"},
        {"type", ""},
        {"type", "int int"},
        {"type", "struct { int x; } *"},
        {"type", "union { struct { int a, b; }; long c; }"},
        {"float32", "-0.0"},
        {"float32", "3.4028236e38"},
        {"float32", "1e-46"},
        {"float32", "nan"},
        {"struct", nil, {id = 999}},
        {"functions"},
    }
end

local native = require("nupp.compiler.nativecdecl")
local json = require("nupp.serde.internal.json.values")
local ROOT = debug.getinfo(1, "S").source:match("^@(/.*)/tests/core/[^/]*$")
assert(ROOT, "run this script by its absolute path")

local requests = {}

local function add(operation, text, extra)
    local r = {operation = operation, text = text}
    for k, v in pairs(extra or {}) do
        r[k] = v
    end
    requests[#requests + 1] = r
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("a")
    file:close()

    return text
end

-- Every cdef block and FFI type string in the repository.
local listing = assert(
    io.popen(
        "cd '"
        .. ROOT
        .. "' && find src tests bench docs -type f "
        .. "\\( -name '*.nupp' -o -name '*.lua' -o -name '*.md' \\) | LC_ALL=C sort"
    )
)
local blocks, types = {}, {}
for path in listing:lines() do
    local text = read(ROOT .. "/" .. path) or ""
    for _, body in text:gmatch("cdef%s*%(?%s*%[(=*)%[(.-)%]%1%]") do
        if not body:find("..", 1, true) and not body:find("$", 1, true) then
            blocks[#blocks + 1] = body
        end
    end
    for body in text:gmatch("cdef%s*%(?%s*\"([^\"\n]*)\"") do
        blocks[#blocks + 1] = body
    end
    for kind, spec in text:gmatch("ffi%.(%a+)%(%s*\"([^\"\n]+)\"") do
        if kind == "new"
            or kind == "cast"
            or kind == "typeof"
            or kind == "sizeof"
            or kind == "istype"
            or kind == "metatype"
            or kind == "alignof"
        then
            types[#types + 1] = spec
        end
    end
end
listing:close()
for _, body in ipairs(blocks) do
    add("declare", body)
end
for _, spec in ipairs(types) do
    add("type", spec)
end
add("functions")

-- System headers, preprocessed, whole.
if os.execute("cc --version >/dev/null 2>&1") then
    for _, header in ipairs({"stdio", "pthread"}) do
        local pipe = assert(io.popen("echo '#include <" .. header .. ".h>' | cc -E -P -x c - 2>/dev/null"))
        local text = pipe:read("a")
        pipe:close()
        if text ~= "" then
            add("inspect", json.encode({text = text}))
        end
    end
end

for _, r in ipairs(CASES) do
    add(r[1], r[2], r[3])
end

local out = assert(io.open(assert(arg[1], "usage: core-cdecl-record.lua OUT"), "wb"))
for _, r in ipairs(requests) do
    local text = json.encode(r)
    out:write(text, "\t", native.request(text), "\n")
end
out:close()
print(("%d requests recorded"):format(#requests))
