local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
if not source:match("^/") and not source:match("^%a:/") then
    local current = assert(io.popen("pwd"))
    source = assert(current:read("*l")) .. "/" .. source
    current:close()
end
local directory = assert(source:match("^(.*)/[^/]+$"))
local root = assert(directory:match("^(.*)/tests/simd$"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local obligations = require("tests.simd.obligations")
local equivalence = require("tests.simd.equivalence")
local _, ledger = obligations.load()
local selected = {}
for _, argument in ipairs(arg) do
    local defect = argument:match("^%-%-defect=(.+)$")
    assert(defect, "unknown equivalence option " .. argument)
    selected[defect] = true
end
if next(selected) then
    local defects = {}
    for _, defect in ipairs(ledger.defects) do
        if selected[defect.id] then
            defects[#defects + 1] = defect
            selected[defect.id] = nil
        end
    end
    assert(next(selected) == nil, "unknown equivalence defect")
    ledger = {defects = defects}
end
local report = equivalence.run(ledger)
io.write(equivalence.encode(report), "\n")
os.exit(report.ok and 0 or 1)
