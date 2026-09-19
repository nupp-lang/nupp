-- The archived compiler must carry GPU costs without a development sidecar.
-- Configuring an empty cost stream needs no adapter or device.
local ffi = require("ffi")
local bit = require("bit")
ffi.cdef[[uint64_t nuppNativeFeatures(void);]]
assert(bit.band(tonumber(ffi.C.nuppNativeFeatures()), 4) ~= 0, "linked host lacks GPU")
assert(rawget(_G, "__nuppNativeLibrary") == ffi.C, "archived compiler loaded a sidecar provider")
