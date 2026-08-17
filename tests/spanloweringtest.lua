-- OPT-6, range-proven standard span access lowering.
local parser = require("nupp.compiler.parser")
local optimize = require("nupp.compiler.optimize")
local gen = require("nupp.compiler.gen")
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

local function compile(src, opts)
   opts = opts or {}
   local result = parser.parse(src, "test.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   check.check(result, "test.nupp", env)
   assertEq(#result.errors, 0, "checker errors")
   local remarks = optimize.run(result, {
      level = opts.level == nil and 1 or opts.level,
      disabled = opts.disabled,
      relaxed = opts.relaxed,
   })
   local code, diags = gen.generate(result, "test")
   assertEq(#diags, 0, "generation diagnostics")
   return code, remarks
end

local function compact(text)
   return (text:gsub("%s+", ""))
end

local function remarksFor(remarks)
   local found = {}
   for _, entry in ipairs(remarks) do
      if entry.code == "OPT-6" then
         found[#found + 1] = entry
      end
   end
   return found
end

local HEADER = [[
local span = require("nupp.span")
local struct Cell
    value: int32
end
]]

local function source(body, annotation)
   return HEADER .. (annotation == false and "" or '@relax("frames")\n') .. [[
local function work(
    exclusive output: span.WriteSpan<Cell>,
    borrows input: span.Span<Cell>
): nil
    const out = output
    const source = input
    const rows = span.range(1, out.count, out, source)
]] .. body .. [[
end
return work
]]
end

local M = {}

function M.lowersSharedReadsAndImmediateMutableFields()
   local code, remarks = compile(source([[
    for index = rows.first, rows.last do
        out:getMut(index).value = source:get(index).value
    end
]]))
   local emitted = compact(code)
   assert(emitted:find("out.pointer[out.offset+index-1].value=", 1, true), code)
   assert(emitted:find("source.pointer[source.offset+index-1].value", 1, true), code)
   assertEq(emitted:find(":getMut(", 1, true), nil, "getMut is gone")
   assertEq(emitted:find(":get(index)", 1, true), nil, "get is gone")
   local notes = remarksFor(remarks)
   assertEq(#notes, 1, "one loop remark")
   assert(notes[1].msg:find("lowers 2 checked accesses", 1, true), notes[1].msg)
end

function M.lowersABoundMutablePointer()
   local code = compile(source([[
    for index = rows.first, rows.last do
        local cell = out:getMut(index)
        cell.value = source:get(index).value
    end
]]))
   local emitted = compact(code)
   assert(emitted:find("localcell=(out.pointer+out.offset+index-1)", 1, true), code)
end

function M.lowersStatementSet()
   local code, remarks = compile(source([[
    for index = rows.first, rows.last do
        out:set(index, source:get(index))
    end
]]))
   local emitted = compact(code)
   assert(emitted:find("out.pointer[out.offset+index-1]=source.pointer[source.offset+index-1]", 1, true), code)
   assertEq(#remarksFor(remarks), 1, "set and get aggregate by loop")
end

function M.keepsAValuePositionSetChecked()
   local code, remarks = compile(source([[
    for index = rows.first, rows.last do
        local ignored = out:set(index, new Cell(1))
    end
]]))
   assert(compact(code):find("out:set(index,Cell(1))", 1, true), code)
   local notes = remarksFor(remarks)
   assertEq(#notes, 1, "one decline")
   assert(notes[1].msg:find("unsupported-value-position", 1, true), notes[1].msg)
end

function M.requiresFramesRelaxation()
   local code, remarks = compile(source([[
    for index = rows.first, rows.last do
        local cell = source:get(index)
        print(cell.value)
    end
]], false))
   assert(compact(code):find("source:get(index)", 1, true), code)
   local notes = remarksFor(remarks)
   assertEq(#notes, 1, "one frames decline")
   assert(notes[1].msg:find("frames-held", 1, true), notes[1].msg)
end

function M.acceptsCompilationWideFramesRelaxation()
   local code, remarks = compile(source([[
    for index = rows.first, rows.last do
        local cell = source:get(index)
        print(cell.value)
    end
]], false), {relaxed = {frames = true}})
   assert(compact(code):find("source.pointer[source.offset+index-1]", 1, true), code)
   assertEq(#remarksFor(remarks), 1, "one applied remark")
end

function M.levelZeroAndDisabledPassRetainCalls()
   local src = source([[
    for index = rows.first, rows.last do
        local cell = source:get(index)
        print(cell.value)
    end
]])
   local zero = compact(compile(src, {level = 0}))
   local disabled = compact(compile(src, {disabled = {['OPT-6'] = true}}))
   assert(zero:find("source:get(index)", 1, true), zero)
   assert(disabled:find("source:get(index)", 1, true), disabled)
end

function M.keepsComputedAndUnwitnessedIndexesChecked()
   local code, remarks = compile(source([[
    for index = rows.first, rows.last do
        local exact = source:get(index)
        local computed = source:get(index + 0)
        print(exact.value, computed.value)
    end
]]))
   local emitted = compact(code)
   assert(emitted:find("source.pointer[source.offset+index-1]", 1, true), code)
   assert(emitted:find("source:get(index+0)", 1, true), code)
   assert(remarksFor(remarks)[1].msg:find("lowers 1 checked access", 1, true))
end

function M.doesNotInferFromOnlyOneWitnessBound()
   local code, remarks = compile(HEADER .. [[
@relax("frames")
local function work(borrows input: span.Span<Cell>): nil
    const source = input
    const rows = span.range(1, source.count, source)
    for index = rows.first, source.count do
        print(source:get(index).value)
    end
end
return work
]])
   assert(compact(code):find("source:get(index)", 1, true), code)
   assertEq(#remarksFor(remarks), 0, "an unproved loop is not an optimizer decline")
end

function M.refusesOmittedSpansExplicitStepsAndOutsideAccesses()
   local code, remarks = compile(HEADER .. [[
@relax("frames")
local function work(
    borrows left: span.Span<Cell>,
    borrows right: span.Span<Cell>
): nil
    const a = left
    const b = right
    const rows = span.range(1, a.count, a)
    print(a:get(1).value)
    for index = rows.first, rows.last, 1 do
        print(a:get(index).value, b:get(index).value)
    end
    for index = rows.first, rows.last do
        print(a:get(index).value, b:get(index).value)
    end
    print(a:get(1).value)
end
return work
]])
   local emitted = compact(code)
   assert(emitted:find("a.pointer[a.offset+index-1]", 1, true), code)
   assert(emitted:find("b:get(index)", 1, true), code)
   local _, explicitCount = emitted:gsub("a:get%(index%)", "")
   assertEq(explicitCount, 1, "the explicit-step loop remains checked")
   assertEq(#remarksFor(remarks), 1, "only the canonical proved loop remarks")
end

function M.keepsMutableSpanBindingsChecked()
   local code, remarks = compile(HEADER .. [[
@relax("frames")
local function work(borrows input: span.Span<Cell>): nil
    local source = input
    const rows = span.range(1, source.count, source)
    for index = rows.first, rows.last do
        print(source:get(index).value)
    end
end
return work
]])
   assert(compact(code):find("source:get(index)", 1, true), code)
   assertEq(#remarksFor(remarks), 0, "an unstable span has no proof to decline")
end

function M.doesNotTransportTheProofIntoANestedFunction()
   local code, remarks = compile(HEADER .. [[
@relax("frames")
local function work(borrows input: span.Span<Cell>): function(): nil
    const source = input
    const rows = span.range(1, source.count, source)
    local callback: function(): nil = function(): nil end
    for index = rows.first, rows.last do
        callback = function(): nil
            print(source:get(index).value)
        end
    end
    return callback
end
return work
]])
   assert(compact(code):find("source:get(index)", 1, true), code)
   assertEq(#remarksFor(remarks), 0, "proofs stop at the function boundary")
end

function M.lowersNarrowAndFixedSpanContracts()
   local code, remarks = compile([[
local span = require("nupp.span")
@relax("frames")
local function copy(
    exclusive output: span.FixedWriteSpan<uint8, 4>,
    borrows input: span.FixedSpan<uint8, 4>
): nil
    const out = output
    const source = input
    const rows = span.range(1, 4, out, source)
    for index = rows.first, rows.last do
        out:set(index, source:get(index))
    end
end
return copy
]])
   local emitted = compact(code)
   assert(emitted:find("out.pointer[out.offset+index-1]=source.pointer[source.offset+index-1]", 1, true), code)
   assert(remarksFor(remarks)[1].msg:find("lowers 2 checked accesses", 1, true))
end

function M.evaluatesASetValueOnce()
   local code = compile(HEADER .. [[
local calls = 0
local function nextValue(): Cell
    calls = calls + 1
    return new Cell(calls)
end
@relax("frames")
local function work(exclusive output: span.WriteSpan<Cell>): nil
    const out = output
    const rows = span.range(1, out.count, out)
    for index = rows.first, rows.last do
        out:set(index, nextValue())
    end
end
return work
]])
   local emitted = compact(code)
   assert(emitted:find("out.pointer[out.offset+index-1]=nextValue()", 1, true), code)
   local _, calls = emitted:gsub("nextValue%(%)", "")
   assertEq(calls, 2, "one declaration plus one authored value evaluation")
end

function M.emptyRangesAndRangeFailuresStayAtTheWitness()
   local src = HEADER .. [[
local module = {}
@relax("frames")
function module.read(
    borrows input: span.Span<Cell>,
    first: integer,
    last: integer
): integer
    const source = input
    const rows = span.range(first, last, source)
    local total = 0
    for index = rows.first, rows.last do
        total = total + source:get(index).value
    end
    return total
end
return module
]]
   local optimized = compile(src)
   local checked = compile(src, {disabled = {['OPT-6'] = true}})
   local ffi = require("ffi")
   local priorPreload = package.preload["nupp.span"]
   local priorLoaded = package.loaded["nupp.span"]
   package.preload["nupp.span"] = function()
      return {range = function(first, last, view)
         if first < 1 or last < first - 1 or last > view.count then
            error("range sentinel", 2)
         end
         return {first = first, last = last}
      end}
   end

   local function load(code)
      package.loaded["nupp.span"] = nil
      local module = assert(loadstring(code, "@range_failure"))()
      local array = ffi.typeof("struct { int32_t value; }[?]")
      local storage = array(2)
      local methods = {get = function(self, index)
         assert(index >= 1 and index <= self.count)
         return self.pointer[self.offset + index - 1]
      end}
      methods.__index = methods
      return module, setmetatable({pointer = storage, offset = 0, count = 2}, methods)
   end

   local optimizedModule, optimizedSpan = load(optimized)
   local checkedModule, checkedSpan = load(checked)
   assertEq(optimizedModule.read(optimizedSpan, 1, 0), 0, "optimized empty range")
   assertEq(checkedModule.read(checkedSpan, 1, 0), 0, "checked empty range")
   local optimizedOk, optimizedError = pcall(optimizedModule.read, optimizedSpan, 0, 1)
   local checkedOk, checkedError = pcall(checkedModule.read, checkedSpan, 0, 1)
   package.preload["nupp.span"] = priorPreload
   package.loaded["nupp.span"] = priorLoaded
   assertEq(optimizedOk, false, "optimized invalid range raises")
   assertEq(checkedOk, false, "checked invalid range raises")
   assert(tostring(optimizedError):find("range sentinel", 1, true), optimizedError)
   assert(tostring(checkedError):find("range sentinel", 1, true), checkedError)
end

function M.preservesLinesAndRunsLikeTheCheckedForm()
   local src = [[
local span = require("nupp.span")
local module = {}
struct module.Cell
    value: int32
end
@relax("frames")
function module.copy(
    exclusive output: span.WriteSpan<module.Cell>,
    borrows input: span.Span<module.Cell>
): nil
    const out = output
    const source = input
    const rows = span.range(1, out.count, out, source)
    for index = rows.first, rows.last do
        out:getMut(index).value = source:get(index).value + 7
    end
end
return module
]]
   local optimized = compile(src)
   local checked = compile(src, {disabled = {['OPT-6'] = true}})
   local function lines(text)
      local _, count = text:gsub("\n", "")
      return count
   end
   assertEq(lines(optimized), lines(checked), "lowering preserves generated lines")

   local ffi = require("ffi")
   local priorPreload = package.preload["nupp.span"]
   local priorLoaded = package.loaded["nupp.span"]
   package.preload["nupp.span"] = function()
      return {
         range = function(first, last, ...)
            local spans = {...}
            assert(first >= 1 and last >= first - 1)
            for _, view in ipairs(spans) do assert(last <= view.count) end
            return {first = first, last = last}
         end,
      }
   end
   package.loaded["nupp.span"] = nil

   local function run(code)
      package.loaded["nupp.span"] = nil
      local module = assert(loadstring(code, "@span_lowering_runtime"))()
      local array = ffi.typeof("$[?]", module.Cell)
      local inputStorage, outputStorage = array(8), array(12)
      for index = 0, 7 do inputStorage[index].value = index * 3 end
      local methods = {
         get = function(self, index)
            assert(index >= 1 and index <= self.count)
            return self.pointer[self.offset + index - 1]
         end,
         getMut = function(self, index)
            assert(index >= 1 and index <= self.count)
            return self.pointer + self.offset + index - 1
         end,
         set = function(self, index, value)
            assert(index >= 1 and index <= self.count)
            self.pointer[self.offset + index - 1] = value
         end,
      }
      methods.__index = methods
      local input = setmetatable({pointer = inputStorage, offset = 1, count = 6}, methods)
      local output = setmetatable({pointer = outputStorage, offset = 3, count = 6}, methods)
      module.copy(output, input)
      local values = {}
      for index = 0, 5 do values[index + 1] = outputStorage[index + 3].value end
      return table.concat(values, ",")
   end

   local ok, optimizedResult = pcall(run, optimized)
   local checkedOk, checkedResult = pcall(run, checked)
   package.preload["nupp.span"] = priorPreload
   package.loaded["nupp.span"] = priorLoaded
   assert(ok, optimizedResult)
   assert(checkedOk, checkedResult)
   assertEq(optimizedResult, checkedResult, "slice offsets agree")
   assertEq(optimizedResult, "10,13,16,19,22,25", "expected physical elements")
end

return M
