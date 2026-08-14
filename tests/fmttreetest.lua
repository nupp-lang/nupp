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
-- process costs half a minute and would be the longest suite in the run. The store
-- is content-keyed and never load-bearing, so a stale or missing entry costs one
-- slow run and changes no answer.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pwd = assert(io.popen("pwd"))
   HERE = pwd:read("*l") .. "/" .. HERE
   pwd:close()
end
local ROOT = HERE .. "/.."
local NUPP = ROOT .. "/bin/nupp"

local M = {}

function M.everySourceIsFormatted()
   local outfile = os.tmpname()
   local status = os.execute(("cd '%s' && '%s' fmt --check > '%s' 2>&1")
      :format(ROOT, NUPP, outfile))
   local file = assert(io.open(outfile, "rb"))
   local out = file:read("*a")
   file:close()
   os.remove(outfile)
   assert(status == 0, ("this tree is not formatted; run `nupp fmt --write`:\n%s"):format(out))
end

return M
