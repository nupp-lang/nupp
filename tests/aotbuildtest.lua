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
   assert(out:find("aotFeatures must be one of", 1, true),
      "and names the tiers there are rather than only refusing: " .. out)
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

function M.anUnknownPolicyIsRejected()
   local dir = project("sometimes")
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find('must be "off", "emit-c" or "require"', 1, true), out)
end


--- What this host suffixes a shared library with, or nothing when it is one the
--- suite does not know how to name. `require` is a supported-platform
--- statement, so a host outside it skips rather than fails.
local function librarySuffix()
   local pipe = assert(io.popen("uname -s"))
   local system = pipe:read("*l")
   pipe:close()
   if system == "Darwin" then return ".dylib" end
   if system == "Linux" then return ".so" end
   return nil
end

--- Where `require` puts the library for the `native` target.
local function libraryPath(dir)
   return dir .. "/build/native/lib/libnative_aot" .. librarySuffix()
end

--- The key the linked library was recorded under, or nothing.
local function libraryKey(dir)
   local state = read(dir .. "/build/native/.nupp-state.json")
   return state and state:match('"aotLibrary":"([0-9a-f]+)"')
end

function M.requireBuildsTheLibraryFromTheGeneratedC()
   if librarySuffix() == nil then return end

   local dir = project("require")
   local out, code = build(dir)
   test.equal(code, 0, "the generated C compiles cleanly at -Werror\n" .. out)

   assert(read(dir .. "/build/native/aot/src/kernel.c"),
      "require writes the C as well; it is a superset of emit-c, not a replacement")
   assert(read(libraryPath(dir)), "and compiled it into the project's own library")
   assert(libraryKey(dir), "recorded under a key of its own")
end

function M.theLibraryIsNotRelinkedWhenNothingChanged()
   if librarySuffix() == nil then return end

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
   if librarySuffix() == nil then return end

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
   if librarySuffix() == nil then return end

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
   if librarySuffix() == nil then return end

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
      void ks_scale(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      void ks_scale_forced_scalar(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
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
    if out.count ~= src.count then error("length mismatch", 2) end
    if first < 1 or last > out.count or first > last + 1 then error("range out of bounds", 2) end
    for i = first, last do
        local o = out:getMut(i)
        local s = src:get(i)
        o.x = s.x * factor
        o.y = s.y * factor
    end
end

@aot(lanes = true)
local function shiftBoth(
    exclusive out: span.WriteSpan<Point>, borrows src: span.Span<Point>,
    first: integer, last: integer, delta: number
): nil
    if out.count ~= src.count then error("length mismatch", 2) end
    if first < 1 or last > out.count or first > last + 1 then error("range out of bounds", 2) end
    for i = first, last do
        local o = out:getMut(i)
        local s = src:get(i)
        o.x = s.x + delta
        o.y = s.y + delta
    end
end

return {scaleBoth = scaleBoth, shiftBoth = shiftBoth, Point = Point,}
]]

function M.twoAotFunctionsOverOneStructBuild()
   if librarySuffix() == nil then return end

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
   if librarySuffix() == nil then return end

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
local aot = require("nupp.compiler.build.aot")

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
