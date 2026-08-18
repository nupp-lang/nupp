-- This repository's own sources are formatted.
--
-- The claim the corpus cannot make. `tests/fmtcorpus` says what the formatter does
-- with the inputs it was given; this says that what it does is what is checked in,
-- which is the only version of the claim that stops the tree drifting away from the
-- formatter again while every suite stays green.
--
-- Through the binary rather than the module, because that is what makes it cheap
-- enough to keep: `nupp fmt` stores each file's verdict, so an unchanged tree is
-- answered in about the time it takes to start, where formatting all of it in this
-- process costs a minute and a half and would be the longest thing in the run. The
-- store is content-keyed and never load-bearing, so a stale or missing entry costs one
-- slow run and changes no answer.
--
-- In parts, because a cold run is that minute and a half and the runner can only
-- spread a suite across shards case by case. One case asking about the whole tree was
-- the floor of the whole test run whenever the formatter changed; four each ask about
-- their quarter and can run at once. Every file is in exactly one part.
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pwd = assert(io.popen("pwd"))
   HERE = pwd:read("*l") .. "/" .. HERE
   pwd:close()
end
-- The parent named outright rather than `HERE .. "/.."`, which lists nothing: the
-- source listing takes the include roots as spelled, and a path with a `..` in the
-- middle of it does not match what is under them.
local ROOT = assert(HERE:match("^(.*)/[^/]+$"), "tests directory has no parent")
local NUPP = ROOT .. "/bin/nupp"
local PARTS = 4

--- The project's sources, as `nupp fmt` with nothing named would find them.
---
--- Asked of the compiler rather than of `find`, so a part cannot quietly stop covering
--- a directory this suite has not heard of.
local sources = nil
local function sourceFiles()
   if not sources then
      sources = envMod.listSourceFiles(envMod.new(ROOT))
      table.sort(sources)
      assert(#sources > 100,
         ("the project has %d source files, which is too few to be the whole tree")
         :format(#sources))
   end
   return sources
end

local function checkPart(part)
   local files = sourceFiles()
   local mine = {}
   for index = part, #files, PARTS do
      mine[#mine + 1] = ("'%s'"):format(files[index])
   end
   assert(#mine > 0, "a part with no files in it is a part that proves nothing")
   local outfile = os.tmpname()
   -- One store per part, named for the part rather than for whatever shard it landed
   -- in, so a run reuses what the last run worked out however the two were packed.
   local cache = ("%s/build/.nupp-test-cache/fmt-%d"):format(ROOT, part)
   local status = os.execute(("cd '%s' && NUPP_CACHE_DIR='%s' '%s' fmt --check %s > '%s' 2>&1")
      :format(ROOT, cache, NUPP, table.concat(mine, " "), outfile))
   local file = assert(io.open(outfile, "rb"))
   local out = file:read("*a")
   file:close()
   os.remove(outfile)
   assert(status == 0,
      ("this tree is not formatted; run `nupp fmt --write`:\n%s"):format(out))
end

local M = {}

function M.everySourceIsFormattedPart1()
   checkPart(1)
end

function M.everySourceIsFormattedPart2()
   checkPart(2)
end

function M.everySourceIsFormattedPart3()
   checkPart(3)
end

function M.everySourceIsFormattedPart4()
   checkPart(4)
end

return M
