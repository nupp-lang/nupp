-- The build's ahead-of-time policy.
--
-- Driven through the real binary, because the policy is a manifest key and what
-- it produces is a file on disk; neither is visible from inside the compiler.

local test = require("assert")
local aot = require("nupp.compiler.build.aot")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local KERNEL = [[
local span = require("nupp.span")

local struct Sample
    value: float
    weight: float
end

local struct Decimal
    value: number
end

@aot(lanes = true)
local function scale(
    exclusive samples: span.WriteSpan<Sample>,
    borrows source: span.Span<Sample>,
    first: integer,
    last: integer,
    factor: number
): nil
    if #samples ~= #source then
        error("length mismatch", 2)
    end
    if first < 1 or last > #samples or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local sample = samples[i]
        local input = source[i]
        sample.value = input.value * factor + input.weight
        sample.weight = input.weight * factor
    end
end

@aot(lanes = false)
local function sumBytes(
    borrows first: span.Span<uint8>,
    borrows second: span.Span<uint8>
): (number, uint32, uint32)
    local total = 0.0
    for i = 1, #first do
        total = total + first[i]
    end
    for i = 1, #second do
        total = total + second[i]
    end
    return total, nupp.math.u32.wrap(#first), nupp.math.u32.wrap(#second)
end

@aot(lanes = false)
local function fillDecimals(exclusive values: span.WriteSpan<Decimal>, value: number): nil
    for i = 1, #values do
        values[i].value = value
    end
end

return {
    scale = scale,
    sumBytes = sumBytes,
    fillDecimals = fillDecimals,
    Sample = Sample,
    Decimal = Decimal,
}
]]

local SIMD_KERNEL = [[
local span = require("nupp.span")
local simd = require("nupp.simd")
local preferredBytes = simd.preferredU8

local function drain(bits: simd.MaskBits64): (uint32, uint32)
    return bits:firstSet(), bits:clearFirst():count()
end

@aot(lanes = false)
local function maskOps(low: uint32, high: uint32): (uint32, uint32, uint32, uint32)
    local raw = simd.maskBits64(low, high)
    local prefixed = raw:prefixXor(false)
    local first, left = drain(prefixed)
    return prefixed:lowBits(), prefixed:highBits(), first, left
end

@aot(lanes = false)
local function countQuotes(borrows source: span.Span<uint8>): uint32
    local species = preferredBytes()
    local cursor = 0.0
    local found: uint32 = 0
    while cursor < #source do
        local bytes = species:load(source, cursor)
        local tail = species:tail(#source - cursor)
        local matches = bytes:equal(34)
        local valid = matches:andBits(tail)
        found = nupp.math.u32.add(found, valid:count())
        cursor = cursor + species.lanes
    end
    return found
end

@aot(lanes = false)
local function lookupAligned(borrows source: span.Span<uint8>): uint32
    local species = preferredBytes()
    local previous = species:load(source, nupp.math.u32.wrap(0))
    local current = species:load(source, species.lanes)
    local aligned = simd.alignBytes(previous, current, nupp.math.u32.wrap(3))
    local table = simd.tableU8x16(15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
    local lookedUp = aligned:shiftRight(nupp.math.u32.wrap(4)):lookup16(table)
    local matches = lookedUp:xorBits(species:splat(nupp.math.u32.wrap(15))):equal(0)
    return matches:count()
end

return {countQuotes = countQuotes, maskOps = maskOps, lookupAligned = lookupAligned}
]]

local PLAIN = [[
local m = {}

--- An ordinary module with no `@aot` anywhere in it.
function m.greet(name: string): string
    return "hello " .. name
end

return m
]]

local BUILDER = [[
local valueBuilder = require("nupp.value_builder")
local simd = require("nupp.simd")

@aot
local function rows(count: integer): {number}
    local result = table.new(count, 0)
    for index = 1, count do
        result[index] = index * 2
    end
    return result
end

@aot
local function object(name: string): {[string]: any}
    local result = {name = name, nested = {1, 2, 3}}
    result["ready"] = true
    return result
end

@aot(lanes = false)
local function stream(source: string, tape: string, nullValue: any): (any, uint32, uint32)
    local state = valueBuilder.new(nullValue)
    valueBuilder.openObject(state, nupp.math.u32.wrap(2))
    valueBuilder.key(state, source, nupp.math.u32.wrap(0), nupp.math.u32.wrap(4), false)
    valueBuilder.numberSlice(state, source, nupp.math.u32.wrap(4), nupp.math.u32.wrap(2))
    valueBuilder.key(state, source, nupp.math.u32.wrap(6), nupp.math.u32.wrap(4), false)
    valueBuilder.boolean(state, true)
    valueBuilder.close(state)
    return valueBuilder.finish(state), valueBuilder.byte(source, nupp.math.u32.wrap(4)),
        valueBuilder.word(tape, nupp.math.u32.wrap(0))
end

@aot(lanes = false)
local function primitives(source: string, nullValue: any): (any, uint32, uint32, uint32)
    local view = simd.paddedStringU8(source)
    local bytes = view:loadFull(nupp.math.u32.wrap(0))
    local aligned = simd.alignBytes(view:loadTail(), bytes, nupp.math.u32.wrap(1))
    local table = simd.tableU8x16(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
    local classes = aligned:lookup16(table):equal(7):count()
    local scratch = valueBuilder.newWordScratch(nupp.math.u32.wrap(3))
    local bits = simd.maskBits64(nupp.math.u32.wrap(5), nupp.math.u32.wrap(4))
    local next = valueBuilder.appendSetBits(scratch, nupp.math.u32.wrap(0), nupp.math.u32.wrap(10), bits)
    local state = valueBuilder.new(nullValue)
    valueBuilder.openArray(state, next)
    valueBuilder.number(state, valueBuilder.scratchWord(scratch, nupp.math.u32.wrap(0)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(scratch, nupp.math.u32.wrap(1)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(scratch, nupp.math.u32.wrap(2)) * 1.0)
    valueBuilder.close(state)
    return valueBuilder.finish(state), view.fullLength, view.tailLength, classes
end

return {rows = rows, object = object, stream = stream, primitives = primitives}
]]

local function project(policy)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write(([[
return {
   include = {"src"},
   build = {
      targets = {
         native = {
            kind = "modules",
            entries = {"kernel", "plain"},
            outDir = "build/native",
            %s
         },
      },
   },
}
]]):format(policy and ('aot = "' .. policy .. '",') or ""))
   manifest:close()
   for name, source in pairs({["src/kernel.nupp"] = KERNEL, ["src/plain.nupp"] = PLAIN}) do
      local handle = assert(io.open(dir .. "/" .. name, "wb"))
      handle:write(source)
      handle:close()
   end
   return dir
end

local function builderProject(policy)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write(([=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"builder"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]):format(policy))
   manifest:close()
   local source = assert(io.open(dir .. "/src/builder.g.nupp", "wb"))
   source:write(BUILDER)
   source:close()
   return dir
end

local function build(dir)
   local pipe = assert(io.popen(
      ("cd %q && NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\""):format(dir, NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

   return (out:gsub("__exit__:%d+%s*$", "")), code
end

local function read(path)
   local handle = io.open(path, "rb")
   if not handle then return nil end
   local text = handle:read("*a")
   handle:close()
   return text
end


local M = {}

function M.theDefaultPolicyEmitsNothing()
   local dir = project(nil)
   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(dir .. "/build/native/aot/src/kernel.c"), nil,
      "a project that did not ask for native code gets none, and needs no C compiler")
   assert(read(dir .. "/build/native/kernel.lua"), "the ordinary Lua body is still what was built")
end

function M.offEmitsNothing()
   local dir = project("off")
   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(dir .. "/build/native/aot/src/kernel.c"), nil, "off means off")
end

function M.emitCWritesTheCBesideTheBuild()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)

   local c = read(dir .. "/build/native/aot/src/kernel.c")
   assert(c, "the C was written where the build is writing")
   assert(c:find("void ks_scale(", 1, true), "and it defines the exported symbol: " .. c:sub(1, 200))
   assert(c:find("void ks_scale_forced_scalar(", 1, true),
      "beside the oracle the lane body is diffed against")
   assert(c:find("KsResult_ks_sum_bytes ks_sum_bytes(", 1, true),
      "a block kernel keeps its scalar result pack in the native ABI")
   assert(c:find("size_t count_first, size_t count_second", 1, true),
      "a block kernel receives each span's independent length")
   assert(c:find("double value;", 1, true),
      "a native arena field retains physical binary64 storage")
   -- A module with no `@aot` in it produces nothing rather than an empty file.
   test.equal(read(dir .. "/build/native/aot/src/plain.c"), nil,
      "a module with no @aot function produces no artifact")
   assert(read(dir .. "/build/native/kernel.lua"),
      "the ordinary Lua body is still emitted: emit-c adds an artifact, it does not replace one")
end

--- The key one source's artifact was recorded under, or nothing.
local function key(dir)
   local state = read(dir .. "/build/native/.nupp-state.json")
   if not state then return nil end
   local recorded = state:match('"aot":(%b{})')
   if not recorded then return nil end
   return recorded:match('kernel%.nupp":"([0-9a-f]+)"')
end

--- When a path was last written, or nothing.
local function modified(path)
   for _, flags in ipairs({"-f %m", "-c %Y"}) do
      local pipe = assert(io.popen(("stat %s %q 2>/dev/null"):format(flags, path)))
      local stamp = tonumber(pipe:read("*l"))
      pipe:close()
      if stamp then return stamp end
   end
   return nil
end

function M.anUnchangedArtifactIsNotRewritten()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local first = assert(modified(dir .. "/build/native/aot/src/kernel.c"), "the artifact was written")

   -- A second's granularity is all `stat` promises, so a rewrite has to land in
   -- a later second to be visible. Waiting is what makes the assertion mean
   -- something rather than pass on a coarse clock.
   os.execute("sleep 1.1")
   out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(modified(dir .. "/build/native/aot/src/kernel.c"), first,
      "an artifact whose key still matches is left alone rather than rewritten")
end

function M.aMissingArtifactIsWrittenAgain()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local first = assert(read(dir .. "/build/native/aot/src/kernel.c"))
   assert(key(dir), "the build recorded what it built the artifact under")

   -- The recorded key still matches, so a build that trusted it would leave
   -- nothing behind. The key is evidence about bytes that have to be there.
   os.remove(dir .. "/build/native/aot/src/kernel.c")
   out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(dir .. "/build/native/aot/src/kernel.c"), first,
      "a deleted artifact comes back rather than being believed on a digest")
end

function M.anEditedArtifactIsOverwritten()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local first = assert(read(dir .. "/build/native/aot/src/kernel.c"))

   local handle = assert(io.open(dir .. "/build/native/aot/src/kernel.c", "wb"))
   handle:write("/* not what the compiler wrote */\n")
   handle:close()

   out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(dir .. "/build/native/aot/src/kernel.c"), first,
      "an artifact whose bytes disagree with its key is written again")
end

function M.theKeyIsOverTheIRRatherThanTheSource()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local before = assert(key(dir), "a key was recorded")

   local handle = assert(io.open(dir .. "/src/kernel.nupp", "ab"))
   handle:write("\n-- A comment, which changes no instruction.\n")
   handle:close()

   out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(key(dir), before,
      "two sources that lower to one program share one artifact: a comment is not a rebuild")
end

function M.anUnknownFeatureTierIsRejected()
   local dir = project("emit-c")
   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('aot = "emit%-c",', 'aot = "emit-c", aotFeatures = "avx9",')))
   manifest:close()

   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("aotFeatures", 1, true) and out:find("has no feature tier avx9", 1, true),
      "naming the key and what was wrong with it: " .. out)
   assert(out:find("it has", 1, true),
      "and the tiers this architecture does have, which is the actionable part: " .. out)
end

--- The widest tier this host's architecture has, and whether asking for it
--- changes anything. x86-64 defaults to `baseline` and widens to `avx2`;
--- aarch64 has one tier, so naming it is accepted and changes nothing.
local function widestTier()
   local pipe = assert(io.popen("uname -m"))
   local machine = pipe:read("*l")
   pipe:close()
   if machine == "x86_64" or machine == "amd64" then
      return "avx2", true
   end
   return "neon", false
end

function M.theFeatureTierReachesTheBackend()
   local tier, widens = widestTier()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local before = assert(read(dir .. "/build/native/aot/src/kernel.c"))

   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('aot = "emit%-c",', 'aot = "emit-c", aotFeatures = "' .. tier .. '",')))
   manifest:close()

   out, code = build(dir)
   test.equal(code, 0, "the manifest key is accepted\n" .. out)
   local after = assert(read(dir .. "/build/native/aot/src/kernel.c"))
   assert(after:find("vector_size(32)", 1, true),
      "the widest tier gets the widest gang: " .. after:sub(1, 200))

   if widens then
      assert(before:find("vector_size(16)", 1, true),
         "and the default was the narrow one, since nothing promised AVX")
      assert(after ~= before, "so asking widened it")
   else
      test.equal(after, before, "naming the only tier an architecture has changes nothing")
   end
   assert(key(dir), "and the artifact is recorded under a key that carries the tier")
end

--- The manifest with extra keys spliced into the native target.
local function withKeys(dir, extra)
   local handle = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = handle:read("*a")
   handle:close()
   handle = assert(io.open(dir .. "/nupp.lua", "wb"))
   handle:write((text:gsub('outDir = "build/native",', 'outDir = "build/native", ' .. extra)))
   handle:close()
end

function M.anUnknownCrossTargetIsRejected()
   local dir = project("emit-c")
   withKeys(dir, 'aotTarget = "sparc-sun-solaris",')
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("aotTarget", 1, true) and out:find("unknown target", 1, true),
      "and names the key as well as the value: " .. out)
end

function M.aTierIsCheckedAgainstTheTargetItAppliesTo()
   local dir = project("emit-c")
   -- `avx2` is a real tier and not one aarch64 has. Checking it against the set
   -- of all tiers would accept it; it has to be checked against the target.
   withKeys(dir, 'aotTarget = "aarch64-apple-darwin", aotFeatures = "avx2",')
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("aarch64 has no feature tier avx2", 1, true), out)
end

function M.crossCompilingEmitsThatTargetsCode()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local host = assert(read(dir .. "/build/native/aot/src/kernel.c"))

   -- A target this machine is not, whichever machine it is. Naming one
   -- architecture outright would be naming the host on half of them, and a
   -- cross build that is not one proves nothing. Emitting C needs no toolchain
   -- for the target, which is what makes `emit-c` the answer for a platform
   -- whose compiler is somebody else's.
   local targets = require("nupp.compiler.aot.target")
   local here = assert(targets.select(nil, nil))
   local elsewhere = here.architecture == "x86_64" and "aarch64-unknown-linux-gnu"
      or "x86_64-unknown-linux-gnu"
   withKeys(dir, ('aotTarget = "%s",'):format(elsewhere))
   out, code = build(dir)
   test.equal(code, 0, "a target this machine is not still emits\n" .. out)
   local cross = assert(read(dir .. "/build/native/aot/src/kernel.c"))
   assert(cross:find("vector_size(", 1, true),
      "which is that target's code: " .. cross:sub(1, 200))
   assert(cross ~= host, "and not what the host produced")
end

function M.anUnknownPolicyIsRejected()
   local dir = project("sometimes")
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find('must be "off", "emit-c" or "require"', 1, true), out)
end


--- What this host calls a shared library, asked of the compiler rather than
--- guessed from `uname`. The two could drift, and the one that decides where
--- the file actually goes is the compiler.
local function librarySuffix()
   local targets = require("nupp.compiler.aot.target")
   local host = assert(targets.select(nil, nil), "this host is a modeled target")
   return select(2, aot.linkage(host))
end

--- Whether `require` can be exercised here at all.
---
--- The condition is a C compiler, not a platform: `require` works wherever
--- Clang or a new enough GCC does, and works nowhere without one. A machine
--- with neither skips these rather than failing, because what it is missing is
--- a build dependency the project opts into.
local function hasToolchain()
   return (aot.toolchain()) ~= nil
end

--- Where `require` puts the library for the `native` target.
local function libraryPath(dir)
   return dir .. "/" .. aot.libraryPath("build/native", "native", librarySuffix())
end

--- The key the linked library was recorded under, or nothing.
local function libraryKey(dir)
   local state = read(dir .. "/build/native/.nupp-state.json")
   return state and state:match('"aotLibrary":"([0-9a-f]+)"')
end

function M.requireBuildsTheLibraryFromTheGeneratedC()
   if not hasToolchain() then return end

   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 0, "the generated C compiles cleanly at -Werror\n" .. out)

   assert(read(dir .. "/build/native/aot/src/kernel.c"),
      "require writes the C as well; it is a superset of emit-c, not a replacement")
   assert(read(libraryPath(dir)), "and compiled it into the project's own library")
   assert(libraryKey(dir), "recorded under a key of its own")
end

function M.luaBuilderRegistrationReturnsOrdinaryTables()
   if not hasToolchain() then return end

   local function answer(policy)
      local dir = builderProject(policy)
      local out, code = build(dir)
      test.equal(code, 0, out)
      local script = [[
         local builder = require("builder")
         local rows = builder.rows(4)
         local object = builder.object("nupp")
         local streamed, byte, word = builder.stream("name42flag", string.char(7, 0, 0, 0), {})
         print(table.concat(rows, ","))
         print(object.name, object.ready, table.concat(object.nested, ","))
         print(streamed.name, streamed.flag, byte, word)
      ]]
      local pipe = assert(io.popen((
         "cd %q && luajit -e %q 2>&1"
      ):format(dir, ('package.path="build/native/?.lua;%s/../build/?.lua;"..package.path;'):format(HERE)
         .. script)))
      local result = pipe:read("*a")
      pipe:close()
      return result, dir
   end

   local ordinary = answer("off")
   local native, dir = answer("require")
   test.equal(native, ordinary, "the VM-aware ABI preserves the ordinary source answer")
   assert(native:find("2,4,6,8", 1, true), native)
   assert(native:find("nupp\ttrue\t1,2,3", 1, true), native)
   assert(native:find("42\ttrue\t52\t7", 1, true), native)
   local primitives = assert(io.popen((
      "cd %q && luajit -e %q 2>&1"
   ):format(dir, ('package.path="build/native/?.lua;%s/../build/?.lua;"..package.path;'):format(HERE)
      .. 'local b=require("builder");local values,full,tail,classes=b.primitives(string.rep(string.char(7),40),{});print(table.concat(values,","),full+tail,classes)')))
   local primitiveText = primitives:read("*a")
   primitives:close()
   assert(primitiveText:find("10,12,44\t40", 1, true), primitiveText)
   local generated = assert(read(dir .. "/build/native/builder.lua"))
   assert(generated:find("ks_register_", 1, true), generated)
   assert(not generated:find("cdef function ks_object", 1, true),
      "a builder loads a C closure rather than fabricating lua_State through FFI")
   local failure = assert(io.popen((
      "cd %q && luajit -e %q 2>&1"
   ):format(dir, ('package.path="build/native/?.lua;%s/../build/?.lua;"..package.path;'):format(HERE)
      .. 'local b=require("builder");'
      .. 'local ok,why=pcall(b.rows,-1);print(ok,tostring(why))')))
   local failureText = failure:read("*a")
   failure:close()
   assert(failureText:find("false", 1, true) and
      failureText:find("array capacity at 6:", 1, true),
      "a modeled native failure is protected and source-attributed: " .. failureText)
end

function M.theLibraryIsNotRelinkedWhenNothingChanged()
   if not hasToolchain() then return end

   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local first = assert(modified(libraryPath(dir)))

   os.execute("sleep 1.1")
   out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(modified(libraryPath(dir)), first,
      "a library whose key still matches is left alone")
end

function M.aMissingLibraryIsBuiltAgain()
   if not hasToolchain() then return end

   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local before = assert(libraryKey(dir))

   -- Same rule the C follows: the key is evidence about something that has to
   -- be there, and here the something is what the loader would open.
   os.remove(libraryPath(dir))
   out, code = build(dir)
   test.equal(code, 0, out)
   assert(read(libraryPath(dir)), "a deleted library comes back rather than being believed")
   test.equal(libraryKey(dir), before, "under the same key, because nothing about it changed")
end

function M.aProjectWithNoAotFunctionLinksNothing()
   if not hasToolchain() then return end

   local dir = project("require")
   -- The policy says what to do with `@aot` code, not that there has to be any.
   assert(os.remove(dir .. "/src/kernel.nupp"))
   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('"kernel", ', "")))
   manifest:close()

   local out, code = build(dir)
   test.equal(code, 0, "a project with nothing to compile still builds\n" .. out)
   test.equal(read(libraryPath(dir)), nil, "and gets no library rather than an empty one")
end

function M.theBuiltLibraryLoadsAndComputes()
   if not hasToolchain() then return end

   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 0, out)

   -- The point of `require` is that the answer comes out of the object rather
   -- than out of a file listing. Declared by hand here because the wrapper that
   -- will declare it in a build is the next piece of work; what is being
   -- checked is the object, not the wrapper.
   local ffi = require("ffi")
   ffi.cdef[[
      typedef struct { float value; float weight; } NuppAotSample;
      typedef struct { double v1; uint32_t v2; uint32_t v3; } KsResult_ks_sum_bytes;
      void ks_scale(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      void ks_scale_forced_scalar(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      KsResult_ks_sum_bytes ks_sum_bytes(const uint8_t *first, const uint8_t *second,
         size_t count_first, size_t count_second);
      uint32_t ks_scale_layout_Sample_size(void);
   ]]
   local lib = ffi.load(libraryPath(dir))

   test.equal(tonumber(lib.ks_scale_layout_Sample_size()), 8,
      "the object reports the layout the wrapper will check against")

   local count = 1000
   local lanes = ffi.new("NuppAotSample[?]", count)
   local scalar = ffi.new("NuppAotSample[?]", count)
   local source = ffi.new("NuppAotSample[?]", count)
   for i = 0, count - 1 do
      source[i].value, source[i].weight = i * 0.5, i * 0.25
   end
   lib.ks_scale(lanes, source, 1, count, 3.0, count)
   lib.ks_scale_forced_scalar(scalar, source, 1, count, 3.0, count)

   -- Bit-identical, not close. The whole lane lowering rests on the claim that
   -- running four iterations at once changes the strategy and never the answer.
   for i = 0, count - 1 do
      test.equal(lanes[i].value, scalar[i].value, "value diverged at lane " .. i)
      test.equal(lanes[i].weight, scalar[i].weight, "weight diverged at lane " .. i)
   end
   test.equal(lanes[7].value, 7 * 0.5 * 3.0 + 7 * 0.25, "and it is the arithmetic the source asked for")

   local first = ffi.new("uint8_t[2]", {1, 2})
   local second = ffi.new("uint8_t[3]", {3, 4, 250})
   local result = lib.ks_sum_bytes(first, second, 2, 3)
   test.equal(result.v1, 260,
      "independent block loops read their own span bounds and return a scalar")
   test.equal(tonumber(result.v2), 2, "the second scalar result crosses the result aggregate")
   test.equal(tonumber(result.v3), 3, "the third scalar result crosses the result aggregate")

end

function M.scopedPackedBytesHandleEveryTailWithoutOverreading()
   if not hasToolchain() then return end

   local dir = project("require")
   local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   handle:write(SIMD_KERNEL)
   handle:close()
   local out, code = build(dir)
   test.equal(code, 0, out)

   local ffi = require("ffi")
   ffi.cdef[[
      uint32_t ks_count_quotes(const uint8_t *source, size_t count_source);
      uint32_t ks_count_quotes_forced_scalar(const uint8_t *source, size_t count_source);
      typedef struct { uint32_t v1, v2, v3, v4; } KsMaskOpsResult;
      KsMaskOpsResult ks_mask_ops(uint32_t low, uint32_t high);
      uint32_t ks_lookup_aligned(const uint8_t *source, size_t count_source);
      uint32_t ks_lookup_aligned_forced_scalar(const uint8_t *source, size_t count_source);
   ]]
   local lib = ffi.load(libraryPath(dir))
   for count = 0, 40 do
      local source = ffi.new("uint8_t[?]", math.max(count, 1))
      local expected = 0
      for i = 0, count - 1 do
         source[i] = i % 5 == 0 and 34 or i
         if source[i] == 34 then expected = expected + 1 end
      end
      test.equal(tonumber(lib.ks_count_quotes(source, count)), expected,
         "packed and scalar tail lanes agree at length " .. count)
      test.equal(
         tonumber(lib.ks_count_quotes(source, count)),
         tonumber(lib.ks_count_quotes_forced_scalar(source, count)),
         "packed implementation agrees with its forced-scalar oracle at length " .. count
      )
   end
   local mask = lib.ks_mask_ops(5, 1)
   test.equal(tonumber(mask.v1), 3, "prefix XOR crosses the low mask word")
   test.equal(tonumber(mask.v2), 0xFFFFFFFF, "prefix XOR carries into the high mask word")
   test.equal(tonumber(mask.v3), 0, "firstSet finds the first logical bit")
   test.equal(tonumber(mask.v4), 33, "clearFirst drains one bit from a 64-bit mask")
   local lookupSource = ffi.new("uint8_t[64]")
   for i = 0, 63 do lookupSource[i] = i % 16 end
   test.equal(
      tonumber(lib.ks_lookup_aligned(lookupSource, 64)),
      tonumber(lib.ks_lookup_aligned_forced_scalar(lookupSource, 64)),
      "lookup and cross-vector alignment agree with the scalar oracle"
   )
end

function M.explicitSimdNamesWhyAotOffCannotRunIt()
   local dir = project("off")
   local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   handle:write(SIMD_KERNEL)
   handle:close()
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("simd.preferredU8", 1, true), out)
   assert(out:find("cannot run with aot=off", 1, true), out)
end

--- Two `@aot` functions over one struct, which is what used to produce a
--- binding that declared its layout constant twice and did not compile.
local TWO = [[
local span = require("nupp.span")

local struct Point
    x: float
    y: float
end

@aot(lanes = true)
local function scaleBoth(
    exclusive out: span.WriteSpan<Point>, borrows src: span.Span<Point>,
    first: integer, last: integer, factor: number
): nil
    if #out ~= #src then error("length mismatch", 2) end
    if first < 1 or last > #out or first > last + 1 then error("range out of bounds", 2) end
    for i = first, last do
        local o = out[i]
        local s = src[i]
        o.x = s.x * factor
        o.y = s.y * factor
    end
end

@aot(lanes = true)
local function shiftBoth(
    exclusive out: span.WriteSpan<Point>, borrows src: span.Span<Point>,
    first: integer, last: integer, delta: number
): nil
    if #out ~= #src then error("length mismatch", 2) end
    if first < 1 or last > #out or first > last + 1 then error("range out of bounds", 2) end
    for i = first, last do
        local o = out[i]
        local s = src[i]
        o.x = s.x + delta
        o.y = s.y + delta
    end
end

return {scaleBoth = scaleBoth, shiftBoth = shiftBoth, Point = Point,}
]]

function M.twoAotFunctionsOverOneStructBuild()
   if not hasToolchain() then return end

   local dir = project("require")
   local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   handle:write(TWO)
   handle:close()

   local out, code = build(dir)
   -- Each function checks the struct against its own object's reporters, so the
   -- two layout constants have to be named apart. One name for both declared it
   -- twice and reported NUPP2008.
   test.equal(code, 0, "two @aot functions sharing a struct compile\n" .. out)
   local lua = assert(read(dir .. "/build/native/kernel.lua"))
   -- The C symbol is the snake_cased name, which is what the wrapper calls.
   assert(lua:find("ks_scale_both(", 1, true), "the first wrapper calls the compiled symbol")
   assert(lua:find("ks_shift_both(", 1, true), "and so does the second")
   assert(lua:find("ks_scale_both_PointLayout", 1, true),
      "each checks the struct under its own name, which is what used to collide")
   assert(lua:find("ks_shift_both_PointLayout", 1, true), "both of them")
end

function M.theDispatchedModuleAnswersWhatTheInterpretedOneDoes()
   if not hasToolchain() then return end

   -- Two builds of one source, one calling the compiled code and one not.
   -- Nothing else about `@aot` matters if these disagree: the annotation says
   -- the strategy changes and the answer does not.
   -- `off` first: switching back to it drops the library the build no longer
   -- produces, so building the dispatched one last is what leaves it on disk.
   local dir = project("off")
   local out, code = build(dir)
   test.equal(code, 0, out)
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", dir .. "/ordinary")) == 0)

   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('aot = "off",', 'aot = "require",')))
   manifest:close()
   out, code = build(dir)
   test.equal(code, 0, out)
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", dir .. "/dispatched")) == 0)

   local dispatched = assert(read(dir .. "/dispatched/kernel.lua"))
   assert(dispatched:find("ks_scale(", 1, true), "the first build calls the compiled symbol")
   assert(not read(dir .. "/ordinary/kernel.lua"):find("ks_scale(", 1, true),
      "and the second does not, so the two are really different programs")

   -- Run from the project root: the wrapper names the library the way the build
   -- wrote it, which is relative to where the build ran.
   local script = dir .. "/compare.lua"
   local handle = assert(io.open(script, "wb"))
   handle:write(([[
      local ffi = require("ffi")
      local NUPP = %q
      local spans = (function()
         package.path = NUPP .. ";" .. package.path
         return require("nupp.span")
      end)()
      local count = 4096
      local function run(which)
         package.loaded["kernel"] = nil
         package.path = %q .. "/" .. which .. "/?.lua;" .. NUPP .. ";" .. package.path
         local mod = require("kernel")
         -- The generated chunk is gone after require returns. Force enough
         -- unrelated allocation and a collection that a library handle rooted
         -- only in that chunk would be closed before its exported wrapper runs.
         local pressure = {}
         for i = 1, 5000 do pressure[i] = {i} end
         collectgarbage("collect")
         local src = ffi.new("struct { float value; float weight; }[?]", count)
         for i = 0, count - 1 do
            src[i].value = (i %% 37) * 0.25 - 3
            src[i].weight = (i %% 53) * 0.125 - 2
         end
         local dst = ffi.new("struct { float value; float weight; }[?]", count)
         mod.scale(spans.writeCarray(dst, count), spans.fromCarray(src, count), 1, count, 1.75)
         local seen = {}
         for i = 0, count - 1 do
            seen[#seen + 1] = dst[i].value
            seen[#seen + 1] = dst[i].weight
         end
         return seen
      end
      local a, b = run("ordinary"), run("dispatched")
      if #a ~= #b then print("LENGTHS " .. #a .. " " .. #b) os.exit(1) end
      for i = 1, #a do
         if a[i] ~= b[i] then print(("DIFFERS %%d %%s %%s"):format(i, a[i], b[i])) os.exit(1) end
      end
      print("SAME " .. #a)
   ]]):format(HERE .. "/../build/?.lua", dir))
   handle:close()

   local pipe = assert(io.popen(("cd %q && luajit compare.lua 2>&1"):format(dir)))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("SAME 8192", 1, true),
      "the compiled body answers exactly what the interpreted one does: " .. report)
end

function M.theLibraryTravelsWithWhatWasBuilt()
   if not hasToolchain() then return end

   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 0, out)

   local lua = assert(read(dir .. "/build/native/kernel.lua"))
   -- Marked rather than pathed: a build-time path is either absolute, which
   -- ships a program that runs on one machine, or relative to where the build
   -- ran, which ships one that runs from one directory.
   assert(lua:find('__nuppLib("@lib/', 1, true),
      "the wrapper names the library relative to itself: " .. lua:sub(1, 200))
   assert(not lua:find(dir, 1, true), "and the build directory does not appear in the output")

   -- The test of relocatable is that a copy somewhere else still runs.
   local moved = dir .. "/moved"
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", moved)) == 0)
   local script = dir .. "/run.lua"
   local handle = assert(io.open(script, "wb"))
   handle:write(([[
      local ffi = require("ffi")
      package.path = %q .. "/?.lua;" .. %q .. ";" .. package.path
      local spans = require("nupp.span")
      local mod = require("kernel")
      local count = 64
      local src = ffi.new("struct { float value; float weight; }[?]", count)
      for i = 0, count - 1 do src[i].value = i * 0.5 src[i].weight = i * 0.25 end
      local dst = ffi.new("struct { float value; float weight; }[?]", count)
      mod.scale(spans.writeCarray(dst, count), spans.fromCarray(src, count), 1, count, 3.0)
      print("VALUE " .. tostring(dst[7].value))
   ]]):format(moved, HERE .. "/../build/?.lua"))
   handle:close()

   -- Run from a directory that is neither the project nor the copy, so nothing
   -- about the answer can come from the working directory.
   local pipe = assert(io.popen(("cd / && luajit %q 2>&1"):format(script)))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("VALUE 12.25", 1, true),
      "a copied output tree runs from anywhere: " .. report)
end

function M.aLibraryLeftBehindIsANamedFailure()
   if not hasToolchain() then return end

   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 0, out)

   local moved = dir .. "/incomplete"
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", moved)) == 0)
   assert(os.execute(("rm -rf %q"):format(moved .. "/lib")) == 0)

   local script = dir .. "/missing.lua"
   local handle = assert(io.open(script, "wb"))
   handle:write(([[
      package.path = %q .. "/?.lua;" .. %q .. ";" .. package.path
      print(select(2, pcall(require, "kernel")))
   ]]):format(moved, HERE .. "/../build/?.lua"))
   handle:close()

   local pipe = assert(io.popen(("cd / && luajit %q 2>&1"):format(script)))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("at or above", 1, true),
      "copying the modules without the library says so, rather than failing obscurely: " .. report)
end

function M.aBundleCarriesItsCompiledLibrary()
   if not hasToolchain() then return end

   -- A bundle is one file someone moves somewhere. Its library lives in the
   -- build directory the bundle was assembled in, which is not where the bundle
   -- ends up, so the build has to put a copy beside it.
   local dir = project("require")
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([[
return {
   include = {"src"},
   build = {
      targets = {
         native = {
            kind = "bundle",
            entries = {"kernel"},
            outDir = "build/native",
            output = "dist/app.lua",
            aot = "require",
         },
      },
   },
}
]])
   manifest:close()
   assert(os.remove(dir .. "/src/plain.nupp"))

   local out, code = build(dir)
   test.equal(code, 0, out)
   assert(read(dir .. "/dist/app.lua"), "the bundle was written where it was asked for")
   assert(read(dir .. "/dist/lib/" .. aot.libraryFile("native", librarySuffix())),
      "and the compiled library went with it rather than staying in build/")
end

--- The triple this host can cross-compile to without a sysroot to install, or
--- nothing where there is none. macOS ships both architectures' headers, so an
--- arm64 machine builds x86-64 objects and the reverse, which is a real cross
--- build rather than a rehearsal of one.
local function crossTriple()
   local targets = require("nupp.compiler.aot.target")
   local host = targets.select(nil, nil)
   if host == nil or targets.system(host.triple) ~= "darwin" then return nil end
   if host.architecture == "aarch64" then return "x86_64-apple-darwin", "avx2" end
   return "aarch64-apple-darwin", "neon"
end

function M.requireCrossCompilesToAnotherMachine()
   local triple, tier = crossTriple()
   if triple == nil or not hasToolchain() then return end

   local dir = project("require")
   withKeys(dir, ('aotTarget = "%s", aotFeatures = "%s",'):format(triple, tier))
   local out, code = build(dir)
   test.equal(code, 0, "a cross build completes rather than only being attempted\n" .. out)

   -- What makes this a cross build is the object, not the command line.
   local pipe = assert(io.popen(("file %q 2>&1"):format(libraryPath(dir))))
   local described = pipe:read("*a")
   pipe:close()
   local wanted = triple:match("^([^-]+)") == "x86_64" and "x86_64" or "arm64"
   assert(described:find(wanted, 1, true),
      "and it is that machine's object rather than this one's: " .. described)
end

function M.aStampedBinaryFindsItsCompiledLibrary()
   if not hasToolchain() then return end

   -- A binary carries its payload rather than loading a module file, so the
   -- chunk the wrapper ends up in is the executable. What is being checked is
   -- that this still gives the `@` walk somewhere to start.
   local dir = project("require")
   -- Not called `native`: a binary target's host stub goes in `<outDir>/native`,
   -- so a target of that name would want its executable at a path that is
   -- already a directory.
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([[
return {
   include = {"src"},
   build = {
      targets = {
         app = {
            kind = "binary",
            entries = {"main"},
            outDir = "build/app",
            stub = "nupp",
            aot = "require",
         },
      },
   },
}
]])
   manifest:close()
   assert(os.remove(dir .. "/src/plain.nupp"))
   local main = assert(io.open(dir .. "/src/main.nupp", "wb"))
   main:write([[
local span = require("nupp.span")
local kernel = require("kernel")

const count: integer = 8
local source = carray(kernel.Sample, 8)
local target = carray(kernel.Sample, 8)
for i = 1, count do
    local one = source[i - 1]
    one.value = i * 0.5
    one.weight = i * 0.25
end

kernel.scale(span.writeCarray(target, count), span.fromCarray(source, count), 1, count, 3.0)
print("VALUE " .. tostring(target[6].value))
]])
   main:close()

   local building = assert(io.popen(
      ("cd %q && NO_COLOR= %q build --target app 2>&1; echo \"__exit__:$?\""):format(dir, NUPP)))
   local out = building:read("*a")
   building:close()
   test.equal(tonumber(out:match("__exit__:(%d+)%s*$")), 0, out)

   -- Run from the repository, which is neither the project nor the output the
   -- binary was stamped into, so nothing about the answer can come from the
   -- working directory: the library sits in a temporary directory nowhere near
   -- here. The runtime goes on the path relatively, because an absolute one
   -- spelled for this shell is not one the binary's own runtime can read on
   -- every platform. A minimal project does not carry the runtime; the compiled
   -- library is what this is about, and that travels.
   local pipe = assert(io.popen(
      ('cd %q && LUA_PATH=%q %q 2>&1'):format(
         HERE .. "/..", "build/?.lua;build/?/init.lua;;", dir .. "/build/app/app")))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("VALUE 12.25", 1, true),
      "a stamped binary reaches its compiled code: " .. report)
end

function M.aNamedCompilerThatCannotBuildThisCIsRefused()
   local dir = project("require")
   local pipe = assert(io.popen(
      ("cd %q && NUPP_NATIVE_CC=false NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\""):format(
         dir, NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")))

   test.equal(code, 1, "a toolchain that cannot build the C fails the build\n" .. out)
   assert(out:find("NUPP_NATIVE_CC", 1, true),
      "and says how to name a working one rather than only that it failed: " .. out)
   assert(out:find("emit-c", 1, true), "and what to select instead: " .. out)
end


-- Version parsing, checked against banners rather than against whatever
-- compiler happens to be installed. A machine with only one of the two cannot
-- exercise the other's path any other way, and getting this wrong means
-- refusing a working compiler or accepting one that cannot build the C.
local BANNERS = {
   {"Apple clang version 16.0.0 (clang-1600.0.26.6)", "clang", 16},
   {"clang version 18.1.8 (Fedora 18.1.8-1.fc40)", "clang", 18},
   {"Ubuntu clang version 14.0.0-1ubuntu1.1", "clang", 14},
   {"gcc (Ubuntu 13.2.0-23ubuntu4) 13.2.0", "gcc", 13},
   {"gcc (GCC) 9.5.0", "gcc", 9},
   {"gcc (Debian 8.3.0-6) 8.3.0", "gcc", 8},
   {"cc (GCC) 12.3.0", "gcc", 12},
   -- Red Hat continues past the version with a build date and a second
   -- parenthetical, so the version is not at the end of the line.
   {"gcc (GCC) 11.4.1 20230605 (Red Hat 11.4.1-2)", "gcc", 11},
   {"gcc (GCC) 14.2.1 20240912 (Red Hat 14.2.1-3)", "gcc", 14},
}

function M.aCompilerIsIdentifiedFromWhatItSaysRatherThanItsName()
   for _, one in ipairs(BANNERS) do
      local banner, dialect, version = one[1], one[2], one[3]
      local gotDialect, gotVersion = aot.identify(banner .. "\nsome trailing line\n")
      test.equal(gotDialect, dialect, "dialect of: " .. banner)
      test.equal(gotVersion, version, "version of: " .. banner)
   end
end

function M.somethingThatIsNeitherCompilerIsNotGuessedAt()
   local dialect = aot.identify("Microsoft (R) C/C++ Optimizing Compiler Version 19.39\n")
   test.equal(dialect, nil,
      "MSVC has neither vector_size nor __builtin_convertvector, so it is refused rather than tried")
end

function M.tooOldAGccIsRefusedRatherThanTried()
   -- GCC 8 predates __builtin_convertvector. Nothing here runs it to find out;
   -- the version is the answer.
   local _, version = aot.identify("gcc (Debian 8.3.0-6) 8.3.0\n")
   assert(version < aot.OLDEST_GCC, "8 is older than the floor")
end

return M
