-- Reference Lua 5.5 twin of catalog-environment.nupp, without its types.
-- os.getenv through the bridge's environment import: a set variable, an
-- unset one, a value past the first 256-byte copy, and a scale read the way
-- the bench workloads read BENCH_SCALE.
local probe = os.getenv("NUPP_GUEST_PROBE")
local unset = os.getenv("NUPP_GUEST_PROBE_UNSET")
local long = os.getenv("NUPP_GUEST_LONG") or ""
local scale = tonumber(os.getenv("NUPP_GUEST_SCALE") or "1") or 1
local result = 0
if probe == "core-environment" then
    result = result + 1
end
if unset == nil then
    result = result + 10
end
if probe ~= nil then
    result = result + #probe * 100
end
return result + scale * 100000 + #long * 1000000
