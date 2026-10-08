local testAssert = require("nupp.test")
-- private-export-type: a valid unnameable nominal in a declared module's public
-- surface is suspicious, while transparent aliases and intentionally private fields
-- are not.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

-- One environment for the whole suite: every case checks against one built
-- exactly this way, and building one means checking the prelude from source.
local sharedEnv = envMod.new(".", {config = {include = {"."}}})

local function reports(source, opts)
    local filename = "geom/shapes.nupp"
    local result = parser.parse(source, filename)
    testAssert.equal(#result.errors, 0, "syntax errors in test source")
    local diags = check.check(result, filename, sharedEnv, opts or {moduleName = "geom.shapes"})
    local found = {}
    for _, diag in ipairs(diags) do
        if diag.code == "NUPP2516" then
            found[#found + 1] = diag
        end
    end

    return found
end

local function assertQuiet(source, label)
    local found = reports(source)
    testAssert.equal(#found, 0, label or "expected no private-export-type report")
end

local M = {}

function M.warnsWhenAnExportedRecordReachesAPrivateRecord()
    local found = reports(
        [[
module geom.shapes

local record Coordinate
   x: number
   y: number
end

export record Point
   coordinate: Coordinate
end
]]
    )
    testAssert.equal(#found, 1, "one public declaration exposes Coordinate")
    local at = found[1]
    testAssert.equal(at.lint, "private-export-type", "lint name")
    testAssert.equal(at.severity, "warning", "default level")
    testAssert.equal(at.line, 8, "reports at the exported declaration")
    assert(at.msg:find('exported "Point" exposes private record "Coordinate"', 1, true), at.msg)
    testAssert.equal(#(at.related or {}), 1, "points to the private declaration")
    testAssert.equal(at.related[1].line, 3, "private declaration line")
end

function M.walksFunctionSignaturesAndContainers()
    local found = reports(
        [[
module geom.shapes

local struct Coordinate
   x: float
end

export function first(values: {Coordinate}): Coordinate
   return values[1]
end
]]
    )
    testAssert.equal(#found, 1, "one export reports one private identity")
    assert(found[1].msg:find('private struct "Coordinate"', 1, true), found[1].msg)
end

function M.anExportedAliasGivesTheNominalAPublicName()
    assertQuiet(
        [[
module geom.shapes

local record Coordinate
   x: number
end

export type PublicCoordinate = Coordinate

export function x(value: Coordinate): number
   return value.x
end
]],
        "the public alias makes Coordinate nameable"
    )
end

function M.anExportedGenericAliasNamesThePrivateNominalFamily()
    assertQuiet(
        [[
module geom.shapes

local record Coordinate<T>
   value: T
end

export type PublicCoordinate<T> = Coordinate<T>

export function value<T>(coordinate: Coordinate<T>): T
   return coordinate.value
end
]],
        "the generic public alias names every Coordinate application"
    )
end

function M.warnsWhenAGenericDefaultNamesAPrivateNominal()
    local found = reports(
        [[
module geom.shapes

local record Coordinate
   x: number
end

export record Box<T = Coordinate>
   value: T
end
]]
    )
    testAssert.equal(#found, 1, "the omitted type argument exposes Coordinate")
    assert(found[1].msg:find('private record "Coordinate"', 1, true), found[1].msg)
end

function M.transparentPrivateAliasesDoNotWarn()
    assertQuiet(
        [[
module geom.shapes

local type Coordinate = number

export record Point
   x: Coordinate
   y: Coordinate
end
]],
        "an erased alias leaves no private nominal identity"
    )
end

function M.privateRecordFieldsStayOutsideThePublicSurface()
    assertQuiet(
        [[
module geom.shapes

local record Coordinate
   x: number
end

export record Point
   @private coordinate: Coordinate
   x: number
end
]],
        "a private field is not part of the exported surface"
    )
end

function M.canBeAllowedAtTheExport()
    assertQuiet(
        [[
module geom.shapes

local record Coordinate
   x: number
end

@allow("private-export-type")
export record Point
   coordinate: Coordinate
end
]],
        "the export owns the lint suppression"
    )
end

function M.respectsTheProjectLintLevel()
    local source = [[
module geom.shapes
local record Coordinate x: number end
export record Point coordinate: Coordinate end
]]
    local found = reports(source, {moduleName = "geom.shapes", lints = {["private-export-type"] = "note"},})
    testAssert.equal(#found, 1)
    testAssert.equal(found[1].severity, "note", "configured level")
end

return M
