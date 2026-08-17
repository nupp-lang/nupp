-- The build's ahead-of-time policy.
--
-- Driven through the real binary, because the policy is a manifest key and what
-- it produces is a file on disk; neither is visible from inside the compiler.

local test = require("assert")

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

@aot(lanes = true)
local function scale(
    exclusive samples: span.WriteSpan<Sample>,
    borrows source: span.Span<Sample>,
    first: integer,
    last: integer,
    factor: number
): nil
    if samples.count ~= source.count then
        error("length mismatch", 2)
    end
    if first < 1 or last > samples.count or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local sample = samples:getMut(i)
        local input = source:get(i)
        sample.value = input.value * factor + input.weight
        sample.weight = input.weight * factor
    end
end

return {scale = scale, Sample = Sample,}
]]

local PLAIN = [[
local m = {}

--- An ordinary module with no `@aot` anywhere in it.
function m.greet(name: string): string
    return "hello " .. name
end

return m
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

function M.requireIsRefusedRatherThanPromised()
   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 1, "a policy the build cannot keep is refused\n" .. out)
   assert(out:find("require is not implemented yet", 1, true),
      "and says why rather than only that the value is wrong: " .. out)
end

function M.anUnknownPolicyIsRejected()
   local dir = project("sometimes")
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find('must be "off" or "emit-c"', 1, true), out)
end

return M
