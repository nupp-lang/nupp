local testAssert = require("assert")
-- FFI operations the checker knows about: their return type follows the
-- type they are given, rather than collapsing to any.
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local P = "local struct P\n    x: float\n    y: float\nend"

local function diagsOf(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax: " .. (result.errors[1] and result.errors[1].msg or ""))
    local out = {}
    for j, d in ipairs(check.check(result, "test.nupp", env)) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

local M = {}

function M.newReturnsTheTypeItWasGiven()
    testAssert.eq(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal v: number = p.x"), "")
    testAssert.eq(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal s: string = p.x"), "NUPP2001")
    testAssert.eq(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal v = p.nope"), "NUPP2004")
end

function M.aFieldlessCdefStructIsNeverAllocated()
    -- import-c renders an incomplete C struct this way. C gives it no size, so the
    -- storage behind a value of it would be whatever C writes past.
    local opaque = "cdef struct Opaque\nend"
    testAssert.eq(diagsOf(opaque .. "\nlocal p: Opaque*? = nil\nreturn p"), "")
    testAssert.eq(diagsOf(opaque .. "\nlocal o = ffi.new<Opaque>()"), "NUPP2203")
    testAssert.eq(diagsOf(opaque .. "\nlocal o = carray(Opaque, 4)"), "NUPP2401")
end

function M.castReturnsTheTargetType()
    testAssert.eq(
        diagsOf(
            P .. table.concat(
                {"", "local p = ffi.new<P>()", "local raw = ffi.cast<voidptr>(p)", "local back: voidptr = raw",},
                "\n"
            )
        ),
        ""
    )
    testAssert.eq(
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
    testAssert.eq(diagsOf(P .. "\nlocal n: number = ffi.sizeof<P>()"), "")
    testAssert.eq(diagsOf(P .. "\nlocal s: string = ffi.sizeof<P>()"), "NUPP2001")
    -- typeof yields the runtime ctype standing for the type
    testAssert.eq(diagsOf(P .. "\nlocal c: ctype<P> = ffi.typeof<P>()"), "")
    testAssert.eq(diagsOf(P .. "\nlocal c: ctype<voidptr> = ffi.typeof<P>()"), "NUPP2001")
end

function M.gcKeepsTheTypeOfItsValue()
    testAssert.eq(
        diagsOf(P .. table.concat({"", "local p = ffi.gc(ffi.new<P>(), nil)", "local v: number = p.x",}, "\n")),
        ""
    )
    testAssert.eq(
        diagsOf(P .. table.concat({"", "local p = ffi.gc(ffi.new<P>(), nil)", "local s: string = p.x",}, "\n")),
        "NUPP2001"
    )
end

function M.istypeNarrows()
    testAssert.eq(
        diagsOf(
            P .. table.concat(
                {"", "local v: any", "if ffi.istype<P>(v) then", "    local n: number = v.x", "end",},
                "\n"
            )
        ),
        ""
    )
    testAssert.eq(
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
    testAssert.eq(diagsOf("local a, b, c = 1, 2, 3\nprint(a < b > c)"), "NUPP2003")
    testAssert.eq(diagsOf("local t = {new = 1}\nlocal a, b = 1, 2\nprint(t.new < a > b)"), "NUPP2003")
end

-- `ffi.C` is typed from what the checked file declared, not from what the
-- compiler's process happens to hold. The registry LuaJIT keeps is global and
-- has no idea who declared what, so reading it for membership let one program
-- see another's symbols and let a standard facility's own bindings displace a
-- file's.

function M.theCNamespaceHoldsWhatThisFileDeclared()
    testAssert.eq(
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

    testAssert.eq(
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
    testAssert.eq(
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

    testAssert.eq(
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
    testAssert.eq(diagsOf(source), "", "first check")
    testAssert.eq(diagsOf(source), "", "second check over the same source")
end

function M.aGuardedCdefStillDeclares()
    -- `pcall(ffi.cdef, ...)` is how a program tolerates redeclaring a name the
    -- process already holds, and it is what the compiler's own ansi module does.
    testAssert.eq(
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
    testAssert.eq(
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

    testAssert.eq(
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
    local V = P .. "\nlocal ffi = require('ffi')\nlocal v = P(1.0, 2.0)\n"
    testAssert.eq(
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
    testAssert.eq(diagsOf(V .. "local raw = ffi.cast('unsigned char*', v)\nlocal a = raw[0]"), "NUPP2604")
    testAssert.eq(
        diagsOf(V .. "local raw = ffi.cast('unsigned char*', v)\n@unsafe do\n   raw[0] = 300\nend"),
        "NUPP2001"
    )
    -- a plain char pointer is still text
    testAssert.eq(diagsOf(V .. "local text = ffi.cast('const char*', v)\nlocal s: cstring = text"), "")
end

return M
