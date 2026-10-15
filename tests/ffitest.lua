local testAssert = require("nupp.test")
-- FFI operations the checker knows about: their return type follows the
-- type they are given, rather than collapsing to any.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local P = "local struct P\n    x: float\n    y: float\nend"

local function diagsOf(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax: " .. (result.errors[1] and result.errors[1].msg or ""))
    local out = {}
    for j, d in ipairs(check.check(result, "test.nupp", env)) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

local M = {}

function M.newReturnsTheTypeItWasGiven()
    testAssert.equal(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal v: number = p.x"), "")
    testAssert.equal(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal s: string = p.x"), "NUPP2001")
    testAssert.equal(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal v = p.nope"), "NUPP2004")
end

function M.aFieldlessCdefStructIsNeverAllocated()
    -- import-c renders an incomplete C struct this way. C gives it no size, so the
    -- storage behind a value of it would be whatever C writes past.
    local opaque = "cdef struct Opaque\nend"
    testAssert.equal(diagsOf(opaque .. "\nlocal p: Opaque*? = nil\nreturn p"), "")
    testAssert.equal(diagsOf(opaque .. "\nlocal o = ffi.new<Opaque>()"), "NUPP2203")
    testAssert.equal(diagsOf(opaque .. "\nlocal o = carray(Opaque, 4)"), "NUPP2401")
end

function M.castReturnsTheTargetType()
    testAssert.equal(
        diagsOf(
            P .. table.concat(
                {"", "local p = ffi.new<P>()", "local raw = ffi.cast<voidptr>(p)", "local back: voidptr = raw",},
                "\n"
            )
        ),
        ""
    )
    testAssert.equal(
        diagsOf(
            P .. table.concat(
                {"", "local p = ffi.new<P>()", "local raw = ffi.cast<voidptr>(p)", "local wrong: string = raw",},
                "\n"
            )
        ),
        "NUPP2001"
    )
end

function M.sizeofAndTypeofAreTyped()
    testAssert.equal(diagsOf(P .. "\nlocal n: number = ffi.sizeof<P>()"), "")
    testAssert.equal(diagsOf(P .. "\nlocal s: string = ffi.sizeof<P>()"), "NUPP2001")
    -- typeof yields the runtime ctype standing for the type
    testAssert.equal(diagsOf(P .. "\nlocal c: ctype<P> = ffi.typeof<P>()"), "")
    testAssert.equal(diagsOf(P .. "\nlocal c: ctype<voidptr> = ffi.typeof<P>()"), "NUPP2001")
end

function M.gcKeepsTheTypeOfItsValue()
    testAssert.equal(
        diagsOf(P .. table.concat({"", "local p = ffi.gc(ffi.new<P>(), nil)", "local v: number = p.x",}, "\n")),
        ""
    )
    testAssert.equal(
        diagsOf(P .. table.concat({"", "local p = ffi.gc(ffi.new<P>(), nil)", "local s: string = p.x",}, "\n")),
        "NUPP2001"
    )
end

function M.istypeNarrows()
    testAssert.equal(
        diagsOf(
            P .. table.concat(
                {"", "local v: any", "if ffi.istype<P>(v) then", "    local n: number = v.x", "end",},
                "\n"
            )
        ),
        ""
    )
    testAssert.equal(
        diagsOf(
            P .. table.concat(
                {"", "local v: any", "if ffi.istype<P>(v) then", "    local s: string = v.x", "end",},
                "\n"
            )
        ),
        "NUPP2001"
    )
end

function M.comparisonChainsStillParse()
    -- only ffi.<intrinsic> takes a type argument, so `a < b > c` is
    -- ordinary Lua everywhere else
    testAssert.equal(diagsOf("local a, b, c = 1, 2, 3\nprint(a < b > c)"), "NUPP2003")
    testAssert.equal(diagsOf("local t = {new = 1}\nlocal a, b = 1, 2\nprint(t.new < a > b)"), "NUPP2003")
end

-- `ffi.C` is typed from what the checked file declared, not from what the
-- compiler's process happens to hold. The registry LuaJIT keeps is global and
-- has no idea who declared what, so reading it for membership let one program
-- see another's symbols and let a standard facility's own bindings displace a
-- file's.

function M.theCNamespaceHoldsWhatThisFileDeclared()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    'local ffi = require("ffi")',
                    'ffi.cdef[[int nuppProbeDeclared(int);]]',
                    "local n: integer = ffi.C.nuppProbeDeclared(1)",
                },
                "\n"
            )
        ),
        "",
        "a declared symbol is a member"
    )

    testAssert.equal(
        diagsOf(
            table.concat({'local ffi = require("ffi")', "local n: integer = ffi.C.nuppProbeNeverDeclared(1)",}, "\n")
        ),
        "NUPP2004",
        "a symbol this file never declared is not"
    )
end

function M.anotherProgramsDeclarationsAreNotVisible()
    -- The first check declares it to the process for good; the second must still
    -- refuse it, because the second program did not.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    'local ffi = require("ffi")',
                    'ffi.cdef[[int nuppLeakProbe(int);]]',
                    "local n: integer = ffi.C.nuppLeakProbe(1)",
                },
                "\n"
            )
        ),
        "",
        "the declaring program sees it"
    )

    testAssert.equal(
        diagsOf(table.concat({'local ffi = require("ffi")', "local n: integer = ffi.C.nuppLeakProbe(1)",}, "\n")),
        "NUPP2004",
        "a program that declared nothing does not"
    )
end

function M.checkingTheSameSourceTwiceKeepsItsDeclarations()
    -- LuaJIT holds the block after the first check, so a second run declares
    -- nothing new. The names have to come back anyway.
    local source = table.concat(
        {
            'local ffi = require("ffi")',
            'ffi.cdef[[int nuppRepeatProbe(int);]]',
            "local n: integer = ffi.C.nuppRepeatProbe(1)",
        },
        "\n"
    )
    testAssert.equal(diagsOf(source), "", "first check")
    testAssert.equal(diagsOf(source), "", "second check over the same source")
end

function M.aGuardedCdefStillDeclares()
    -- `pcall(ffi.cdef, ...)` is how a program tolerates redeclaring a name the
    -- process already holds, and it is what the compiler's own ansi module does.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    'local ffi = require("ffi")',
                    'pcall(ffi.cdef, "int nuppGuardedProbe(int);")',
                    "local n: integer = ffi.C.nuppGuardedProbe(1)",
                },
                "\n"
            )
        ),
        "",
        "a guarded declaration is still a declaration"
    )
end

function M.ffiLoadCarriesTheSameNamespace()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    'local ffi = require("ffi")',
                    'ffi.cdef[[int nuppLoadProbe(int);]]',
                    'local lib = ffi.load("probe")',
                    "local n: integer = lib.nuppLoadProbe(1)",
                },
                "\n"
            )
        ),
        "",
        "a declared symbol is reachable through ffi.load"
    )

    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    'local ffi = require("ffi")',
                    'local lib = ffi.load("probe")',
                    "local n: integer = lib.nuppUndeclaredThroughLoad(1)",
                },
                "\n"
            )
        ),
        "NUPP2004",
        "and an undeclared one is not"
    )
end

function M.unsignedBytePointerCastsAreIndexableUnderUnsafe()
    -- "unsigned char *" and "uint8_t *" name the bytes of a value, not text
    local V = P .. "\nlocal ffi = require('ffi')\nlocal v = new P(1.0, 2.0)\n"
    testAssert.equal(
        diagsOf(
            V .. table.concat(
                {
                    "local raw = ffi.cast('unsigned char*', v)",
                    "local raw2 = ffi.cast('uint8_t*', v)",
                    "@unsafe do",
                    "   local a: uint32 = raw[0]",
                    "   local b: uint32 = raw2[4]",
                    "   raw[1] = 7",
                    "end",
                },
                "\n"
            )
        ),
        ""
    )
    testAssert.equal(diagsOf(V .. "local raw = ffi.cast('unsigned char*', v)\nlocal a = raw[0]"), "NUPP2604")
    testAssert.equal(diagsOf(V .. "local raw = ffi.cast('unsigned char*', v)\n@unsafe do\n   raw[0] = 300\nend"), "NUPP2001")
    -- a plain char pointer is still text
    testAssert.equal(diagsOf(V .. "local text = ffi.cast('const char*', v)\nlocal s: cstring = text"), "")
end

return M
