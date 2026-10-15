-- Checks the built normalizer against the corpus and times it: nanoseconds
-- per input byte over the whole corpus, best of nine rounds of the corpus.
local bench = require("nupp.bench.pathbench")
local cases = {}
local total = 0
for line in io.lines(arg[1]) do
    local path, windows, want = line:match("^([^\t]*)\t([01])\t(.*)$")
    cases[#cases + 1] = {path, windows == "1", want}
    total = total + #path
end
for _, c in ipairs(cases) do
    local got = bench.normalize(c[1], c[2])
    if got ~= c[3] then error(("mismatch for %q windows=%s: got %q want %q"):format(c[1], tostring(c[2]), got, c[3])) end
end
local best = math.huge
for _ = 1, 9 do
    local t = os.clock()
    local s = 0
    for _ = 1, 20 do for _, c in ipairs(cases) do s = s + #bench.normalize(c[1], c[2]) end end
    local e = (os.clock() - t) / 20
    if e < best then best = e end
end
print(("%s\t%.2f ns per input byte\t%.3f us per call\t(%d cases, %d bytes)"):format(arg[2] or "?", best / total * 1e9, best / #cases * 1e6, #cases, total))
