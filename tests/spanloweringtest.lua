-- Trusted indexed-view range proof and contiguous-span lowering.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local optimize = require("nupp.compiler.optimize")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function checked(src)
   local result = parser.parse(src, "test.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   local diagnostics = check.check(result, "test.nupp", env)
   return result, diagnostics
end

local function compile(src, options)
   local result = checked(src)
   assertEq(#result.errors, 0, "checker errors")
   optimize.run(result, options or {level = 1})
   local code, diags = gen.generate(result, "test")
   assertEq(#diags, 0, "generation diagnostics")
   return code:gsub("%s+", "")
end

local HEADER = [[
local span = require("nupp.span")
local indexed = require("nupp.indexed")
local struct Cell
    value: int32
end
]]

local M = {}

function M.levelZeroAndADisabledPassKeepCheckedAccess()
   local source = HEADER .. [[
local function work(borrows input: span.Span<Cell>): int32
    const values = input
    local total = 0 as int32
    for index = 1, #values do
        total += values[index].value
    end
    return total
end
return work
]]
   local levelZero = compile(source, {level = 0})
   local disabled = compile(source, {level = 1, disabled = {['OPT-6'] = true}})
   assert(levelZero:find("values:get(index).value", 1, true), levelZero)
   assert(disabled:find("values:get(index).value", 1, true), disabled)
end

function M.aCommonRangeLowersReadsFieldsAndWholeStores()
   local code = compile(HEADER .. [[
local function work(
    exclusive output: span.WriteSpan<Cell>,
    borrows input: span.Span<Cell>
): nil
    const out = output
    const source = input
    const rows = indexed.range(1, #out, out, source)
    for index = rows.first, rows.last do
        out[index].value = source[index].value
    end
    for index = rows.first, rows.last do
        out[index] = source[index]
    end
end
return work
]])
   assert(code:find("out.pointer[out.offset+index-1].value=source.pointer[source.offset+index-1].value", 1, true), code)
   assert(code:find("out.pointer[out.offset+index-1]=source.pointer[source.offset+index-1]", 1, true), code)
end

function M.aCanonicalLengthLoopUsesTheSameProof()
   local code = compile(HEADER .. [[
local function work(exclusive output: span.WriteSpan<Cell>): nil
    const out = output
    for index = 1, #out do
        out[index].value += 1
    end
end
return work
]])
   assert(code:find(".pointer[", 1, true) and code:find(".value+=1", 1, true), code)
   assert(code:find("forindex=1,out.countdo", 1, true), code)
end

function M.arbitraryAndComputedIndexesStayChecked()
   local code = compile(HEADER .. [[
local function work(borrows input: span.Span<Cell>, index: integer): int32
    return input[index + 0].value
end
return work
]])
   assert(code:find("input:get(index+0).value", 1, true), code)
end

function M.aProofOnlyAdmitsNamedStableViews()
   local code = compile(HEADER .. [[
local function work(borrows left: span.Span<Cell>, borrows right: span.Span<Cell>): nil
    const a = left
    const b = right
    for index = 1, #a do
        print(a[index].value, b[index].value)
    end
end
return work
]])
   assert(code:find("a.pointer[a.offset+index-1].value", 1, true), code)
   assert(code:find("b:get(index).value", 1, true), code)
end

function M.nonescapingSlicesComposeWithoutWrapperAllocation()
   local code = compile(HEADER .. [[
local function work(borrows input: span.Span<Cell>): int32
    const first = 2
    const last = 4
    const outer = input:slice(first, last)
    const inner = outer:slice(1, 2)
    local total = 0 as int32
    for index = 1, #inner do
        total += inner[index].value
    end
    return total
end
return work
]])
   assert(code:find("._sliceFinish(", 1, true), code)
   assert(not code:find(":slice(", 1, true), code)
   assert(code:find("input.offset+2-1+1-1+index-1", 1, true), code)
end

function M.anEscapingSliceKeepsItsSafeWrapper()
   local code = compile(HEADER .. [[
local function work(borrows input: span.Span<Cell>): span.Span<Cell> borrows (input)
    const result = input:slice(2, 4)
    return result
end
return work
]])
   assert(code:find(":slice(2,4)", 1, true), code)
   assert(not code:find("._sliceFinish(", 1, true), code)
end

function M.nonescapingSharedDowngradesRemainOnTheRootAdapter()
   local code = compile(HEADER .. [[
local function work(exclusive input: span.WriteSpan<Cell>): int32
    const readable = input:shared()
    local total = 0 as int32
    for index = 1, #readable do
        total += readable[index].value
    end
    return total
end
return work
]])
   assert(not code:find(":shared(", 1, true), code)
   assert(code:find("input.pointer[input.offset+index-1].value", 1, true), code)
end

function M.fixedSpansUseTheCommonAdapter()
   local code = compile([[
local span = require("nupp.span")
local struct Cell
    value: uint8
end
local function work(exclusive output: span.FixedWriteSpan<Cell, 4>): nil
    const out = output
    for index = 1, #out do
        out[index].value = 7
    end
end
return work
]])
   assert(code:find("forindex=1,out.countdo", 1, true), code)
   assert(code:find("out.pointer[out.offset+index-1].value=7", 1, true), code)
end

function M.removedSpanMembersHaveMigrationDiagnostics()
   local _, diagnostics = checked(HEADER .. [[
local function old(borrows values: span.Span<Cell>): nil
    print(values.count, values:get(1).value)
    span.range(1, 1, values)
end
]])
   local text = {}
   for _, diagnostic in ipairs(diagnostics or {}) do text[#text + 1] = diagnostic.msg or diagnostic.message end
   text = table.concat(text, "\n")
   assert(text:find("use #view", 1, true), text)
   assert(text:find("use view[index]", 1, true), text)
   assert(text:find("indexed.range", 1, true), text)
end

function M.aLookalikeIndexedTypeCannotEnterTheTrustedRange()
   local _, diagnostics = checked([[
local indexed = require("nupp.indexed")
local record Fake
    readonly count: integer
end
const fake = new Fake(count = 1)
const range = indexed.range(1, 1, fake)
print(range)
]])
   local text = {}
   for _, diagnostic in ipairs(diagnostics or {}) do text[#text + 1] = diagnostic.msg or diagnostic.message end
   text = table.concat(text, "\n")
   assert(text:find("standard Span or SoA view", 1, true), text)
end

return M
