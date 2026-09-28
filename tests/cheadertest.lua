-- Typing a pinned C header at compile time: LuaJIT parses it, and the
-- types are read back out of the FFI rather than translated by us.
local cheaderMod = require("nupp.compiler.cinterop.cheader")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")
local T = require("nupp.compiler.types")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local M = {}

local function loaded()
    local res, err = cheaderMod.load(HERE .. "/fixtures/sink.h")
    assert(res, "header must load: " .. tostring(err))
    return res
end

function M.signaturesComeFromLuaJITsOwnParse()
    local res = loaded()
    -- imported pointers are nullable: C does not say which may be NULL
    assertEq(T.tostring(res.exports.nuppSinkOpen), "function(cstring?): boolean")
    assertEq(T.tostring(res.exports.nuppSinkCategory), "function(int32, int32, cstring?)")
    assertEq(T.tostring(res.exports.nuppSinkClose), "function()")
    -- `unsigned long` follows the host ABI: LLP64 on Windows, LP64 here.
    local width = require("ffi").os == "Windows" and "uint32" or "uint64"
    assertEq(T.tostring(res.exports.nuppSinkCount), "function(): " .. width)
end

function M.pointersAndStructsDecode()
    local res = loaded()
    -- float parameter, struct pointer, double return
    assertEq(T.tostring(res.exports.nuppSinkScale), "function(float, SinkPoint*?): number")
    assertEq(T.tostring(res.exports.nuppSinkBytes), "function(uint8*?, const uint8*?): uint8*?")
    assertEq(
        T.tostring(assert(cheaderMod.typeFromString("const unsigned char *"))),
        "const uint8*?",
        "literal type strings preserve unsigned bytes and const"
    )
end

function M.completeDirectDeclaratorsDecode()
    local res, err = cheaderMod.load(HERE .. "/fixtures/complete_c_interop.h")
    assert(res, "complete header must load: " .. tostring(err))
    local parameter = res.exports.nupp_complete_use_context.params[1]
    local pointer = parameter.members[1] == T.nil_ and parameter.members[2] or parameter.members[1]
    local context = pointer.elem
    assertEq(context.name, "nupp_complete_context", "typedef names the anonymous struct identity")
    assertEq(T.tostring(context.byname.matrix), "float[3][2]")
    assertEq(T.tostring(context.byname.callback), "function(int32)?")
    assertEq(T.tostring(res.exports.nupp_complete_get_callback), "function(): function(int32)?")
    assertEq(T.tostring(res.exports.nupp_complete_set_callbacks), "function((function(int32)?)*?)")
    assertEq(T.tostring(res.exports.nupp_complete_get_row), "function(): int32[4]*?")
end

local function scratchHeader(name, text)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local path = dir .. "/" .. name
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
    return path, dir
end

function M.onlyAConstCharPointerIsText()
    -- LuaJIT fills a `const char *` from a Lua string and refuses one for a
    -- writable `char *`, so only the first is `cstring`.
    local path, dir = scratchHeader("charp.h", table.concat({
        "void nupp_charp_fill(char *buf, unsigned long n);",
        "char *nupp_charp_dup(const char *s);",
        "void nupp_charp_signed(signed char *bytes);",
    }, "\n"))
    local res = assert(cheaderMod.load(path))
    os.execute("rm -rf '" .. dir .. "'")
    local width = require("ffi").os == "Windows" and "uint32" or "uint64"
    assertEq(T.tostring(res.exports.nupp_charp_fill), "function(int8*?, " .. width .. ")")
    assertEq(T.tostring(res.exports.nupp_charp_dup), "function(cstring?): int8*?")
    assertEq(T.tostring(res.exports.nupp_charp_signed), "function(int8*?)")
end

function M.aBoolBitfieldIsTypedAsTheBooleanItReadsAs()
    local path, dir = scratchHeader("flags.h", "struct NuppFlagsBits { _Bool on : 1; int level : 4; };\n"
        .. "struct NuppFlagsBits *nupp_flags_new(void);\n")
    local res = assert(cheaderMod.load(path))
    os.execute("rm -rf '" .. dir .. "'")
    local result = res.exports.nupp_flags_new.rets[1]
    local pointer = result.members[1] == T.nil_ and result.members[2] or result.members[1]
    assertEq(T.tostring(pointer.elem.byname.on), "boolean")
    assertEq(T.tostring(pointer.elem.byname.level), "int32")
end

function M.aConditionalNeedsThePreprocessor()
    local header = table.concat({
        "#ifndef NUPP_COND_H",
        "#define NUPP_COND_H",
        "#ifdef _WIN32",
        "typedef unsigned short nupp_cond_wide;",
        "#else",
        "typedef unsigned int nupp_cond_wide;",
        "#endif",
        "nupp_cond_wide nupp_cond_width(nupp_cond_wide x);",
        "#endif",
    }, "\n") .. "\n"
    local path, dir = scratchHeader("cond.h", header)
    local res, err = cheaderMod.load(path)
    assertEq(res, nil, "both branches would reach LuaJIT")
    assert(err:find("cond.h:3: #ifdef _WIN32 needs cheader's \"preprocess\" argument", 1, true), err)
    if os.execute("cc --version >/dev/null 2>&1") == 0 then
        local preprocessed = assert(cheaderMod.load(path, {preprocess = true}))
        local want = require("ffi").os == "Windows" and "function(uint16): uint16" or "function(uint32): uint32"
        assertEq(T.tostring(preprocessed.exports.nupp_cond_width), want, "the preprocessor picks the branch")
    end
    os.execute("rm -rf '" .. dir .. "'")

    local disabled, disabledDir = scratchHeader("off.h", "#if 0\nint nupp_off_hidden(void);\n#endif\nint nupp_off_shown(void);\n")
    local _, offErr = cheaderMod.load(disabled)
    os.execute("rm -rf '" .. disabledDir .. "'")
    assert(offErr and offErr:find("off.h:1: #if 0 needs", 1, true), tostring(offErr))
end

function M.aCplusplusGuardIsSettledWithoutAPreprocessor()
    local path, dir = scratchHeader("cpp.h", table.concat({
        "/* A project header's usual shape. */",
        "#ifndef NUPP_CPP_H",
        "#define NUPP_CPP_H",
        "#ifdef __cplusplus",
        "extern \"C\" {",
        "#endif",
        "int nupp_cpp_add(int a, int b);",
        "#if defined(__cplusplus)",
        "}",
        "#else",
        "int nupp_cpp_c_only(void);",
        "#endif",
        "#endif",
    }, "\n") .. "\n")
    local res, err = cheaderMod.load(path)
    os.execute("rm -rf '" .. dir .. "'")
    assert(res, err)
    assertEq(T.tostring(res.exports.nupp_cpp_add), "function(int32, int32): int32")
    assertEq(T.tostring(res.exports.nupp_cpp_c_only), "function(): int32")
end

function M.aParseErrorNamesTheHeadersOwnLine()
    local header = table.concat({
        "/* A header with a long",
        "   multi-line comment",
        "   spanning three lines */",
        "#ifndef NUPP_BAD_H",
        "#define NUPP_BAD_H",
        "#include <stdint.h>",
        "",
        "int nupp_bad_good(int a);",
        "int nupp_bad_broken(int a b);",
        "#endif",
    }, "\n") .. "\n"
    local path, dir = scratchHeader("bad.h", header)
    local _, err = cheaderMod.load(path)
    assert(err and err:find("bad.h:9: ", 1, true), "the broken declaration is on line 9: " .. tostring(err))
    if os.execute("cc --version >/dev/null 2>&1") == 0 then
        local _, preprocessedErr = cheaderMod.load(path, {preprocess = true})
        assert(preprocessedErr and preprocessedErr:find("bad.h:9: ", 1, true),
            "linemarkers name the header's line: " .. tostring(preprocessedErr))
    end
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aNulByteIsRefused()
    local path, dir = scratchHeader("nul.h", "int nupp_nul_a(void);\n\0int nupp_nul_b(void);\n")
    local res, err = cheaderMod.load(path)
    os.execute("rm -rf '" .. dir .. "'")
    assertEq(res, nil, "nothing past the NUL would be declared")
    assert(err:find("nul.h:2: the header holds a NUL byte", 1, true), err)
end

function M.noPreprocessorNeededForASelfContainedHeader()
    -- the fixture has #ifndef/#include and still loads with no compiler
    local res, err = cheaderMod.load(HERE .. "/fixtures/sink.h")
    assert(res, "no cc required: " .. tostring(err))
end

function M.missingHeaderIsReported()
    local res, err = cheaderMod.load(HERE .. "/fixtures/nope.h")
    assert(not res, "missing header fails")
    assert(err:find("cannot read", 1, true), "says why: " .. tostring(err))
end

local function diagsOf(src)
    local result = parser.parse(src, HERE .. "/probe.nupp")
    assertEq(#result.errors, 0, "syntax: " .. (result.errors[1] and result.errors[1].msg or ""))
    local out = {}
    for j, d in ipairs(check.check(result, HERE .. "/probe.nupp", env)) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

function M.cheaderTypesCallSites()
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local sink = cheader('fixtures/sink.h')",
                    "local ok: boolean = sink.nuppSinkOpen('/tmp/x')",
                    "sink.nuppSinkCategory(1, 2, 'render')",
                },
                "\n"
            )
        ),
        ""
    )
    -- a wrong argument is caught against the header's own signature
    assertEq(
        diagsOf(table.concat({"local sink = cheader('fixtures/sink.h')", "sink.nuppSinkOpen(42)",}, "\n")),
        "NUPP2006"
    )
    -- so is a symbol the header does not declare
    assertEq(
        diagsOf(table.concat({"local sink = cheader('fixtures/sink.h')", "sink.nuppNoSuchThing()",}, "\n")),
        "NUPP2004"
    )
end

function M.badArgumentsToCheaderAreReported()
    assertEq(diagsOf("local x = cheader()"), "NUPP2301")
    assertEq(diagsOf("local x = cheader('fixtures/missing.h')"), "NUPP2302")
end

function M.cheaderArgumentsAreLiteralsOrReported()
    assertEq(diagsOf("local lib = 'z'\nlocal x = cheader('fixtures/sink.h', lib)"), "NUPP2301")
    assertEq(diagsOf("local x = cheader('fixtures/sink.h', nil, 'preprocessed')"), "NUPP2301")
    assertEq(diagsOf("local x = cheader('fixtures/sink.h', 'z', 'preprocess', 'more')"), "NUPP2301")
    assertEq(diagsOf("local x = cheader('fixtures/sink.h', nil)\nreturn x"), "")
end

function M.generatedCodeDeclaresAndBinds()
    local result = parser.parse("local sink = cheader('fixtures/sink.h')\nreturn sink", HERE .. "/p.nupp")
    assertEq(#result.errors, 0, "parses")
    check.check(result, HERE .. "/p.nupp", env)
    local code = gen.generate(result, HERE .. "/p.nupp")
    assert(code:find("__nuppFfi.cdef", 1, true), "declares to the FFI:\n" .. code)
    assert(code:find("nuppSinkOpen", 1, true), "carries the declarations")
    assert(code:find("__nuppFfi.C", 1, true), "binds the default namespace")
    -- redeclaration is tolerated: one process may load a header twice
    assert(code:find("pcall(__nuppFfi.cdef", 1, true), "tolerates redefinition")
end

function M.namedLibraryBindsThroughFfiLoad()
    local result = parser.parse("local z = cheader('fixtures/sink.h', 'z')\nreturn z", HERE .. "/p2.nupp")
    check.check(result, HERE .. "/p2.nupp", env)
    local code = gen.generate(result, HERE .. "/p2.nupp")
    assert(code:find('__nuppFfi.load("z")', 1, true), "resolves through the named library:\n" .. code)
    local watched = gen.generate(result, HERE .. "/p2.nupp", nil, {
        mode = "initial",
        module = "cheader-mapped",
        libraries = {z = "/tmp/exact-z-library"},
    })
    assert(
        watched:find('__nuppFfi.load("/tmp/exact-z-library")', 1, true),
        "watch generation resolves the mapped artifact exactly:\n" .. watched
    )
end

function M.headerProvenanceNamesTheDirectInput()
    local path = HERE .. "/fixtures/sink.h"
    local result = assert(cheaderMod.load(path))
    assertEq(result.sourcePath, require("nupp.compiler.fs").canonical(path))
    assertEq(#result.dependencies, 1)
    assertEq(result.dependencies[1], result.sourcePath)
    assert(
        type(result.semanticFingerprint) == "string" and #result.semanticFingerprint > 0,
        "semantic header fingerprint"
    )
end

function M.preprocessorProvenanceIncludesNestedHeaders()
    if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
        return require("assert").skip("cc is unavailable")
    end
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local nested = assert(io.open(dir .. "/nested.h", "wb"))
    nested:write("typedef int nested_value;\n")
    nested:close()
    local root = assert(io.open(dir .. "/root.h", "wb"))
    root:write('#include "nested.h"\nnested_value read_nested(void);\n')
    root:close()
    local result, problem = cheaderMod.load(dir .. "/root.h", {preprocess = true})
    assert(result, problem)
    local found = {}
    for _, path in ipairs(result.dependencies) do
        found[path] = true
    end
    local fs = require("nupp.compiler.fs")
    assert(found[fs.canonical(dir .. "/root.h")], "primary header is observed")
    assert(found[fs.canonical(dir .. "/nested.h")], "nested header is observed")
end

function M.preprocessorFingerprintIncludesCompilerArguments()
    if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
        return require("assert").skip("cc is unavailable")
    end
    local path = HERE .. "/fixtures/sink.h"
    local plain = assert(cheaderMod.provenance(path, {preprocess = true}))
    local configured = assert(
        cheaderMod.provenance(path, {
            preprocess = true,
            ccArgs = {"-DNUPP_UNUSED_TOOLCHAIN_MARKER=1"},
        })
    )
    assert(
        plain.semanticFingerprint ~= configured.semanticFingerprint,
        "compiler arguments participate even when declarations are unchanged"
    )
end

return M
