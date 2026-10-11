_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.spi"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local load;__nuppExports["load"]=function(...) return load(...) end;local select;__nuppExports["select"]=function(...) return select(...) end;




















const _DYNAMIC_REQUIRES = "@requires-dynamically nupp.spi.index"


local indexWasPresent = package . loaded [ "nupp.spi.index" ] ~= nil or package . preload [ "nupp.spi.index" ] ~= nil
local found , loaded = pcall ( require , "nupp.spi.index" )
local indexWasMissing = not found and tostring ( loaded ) : find ( "module 'nupp.spi.index' not found:" , 1 , true ) == 1
if not found and ( indexWasPresent or not indexWasMissing ) then
error ( "nupp: cannot read provider index: " .. tostring ( loaded ) , 0 )
end
local index = found and loaded or { }








local origins = setmetatable ( { } , { __mode = "k" } )








load=function ( interface ) 
local modules = index [ interface ] or { }
local position = 0
const iterator = function ( ) 
local name = modules [ position + 1 ]
if name == nil then
return nil
end

local implementation = require ( name )
position = position + 1

return implementation
end
origins [ iterator ] = { interface = interface , modules = modules }

return iterator
end ;__nuppExports["load"]=load










select=function ( candidates ) 
local chosen = nil
local best = 0
local chosenAt = 0
local tiedAt = nil
local position = 0
for candidate in candidates do
position = position + 1
const priority = ( ( candidate ) . priority ?? 0 )
if chosen == nil or priority > best then
chosen = candidate
best = priority
chosenAt = position
tiedAt = nil
elseif priority == best and tiedAt == nil then
tiedAt = position
end
end
if tiedAt ~= nil then
const origin = origins [ candidates ]
if origin ~= nil then
error (
(
"nupp: multiple implementations have the highest priority for %s: %s and %s, at %s"
) : format ( origin . interface , origin . modules [ chosenAt ] , origin . modules [ tiedAt ] , tostring ( best ) ) ,
2
)
end
error (
(
"nupp: multiple implementations have the highest priority: candidates %d and %d, at %s"
) : format ( chosenAt , tiedAt , tostring ( best ) ) ,
2
)
end

return chosen
end ;__nuppExports["select"]=select
 end);if not __nuppOk then package.loaded["nupp.spi"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.spi"]=__nuppExports;return __nuppExports