_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





































local COMPILER_SURFACES

= {
[ "nupp.workers.spi" ] = { Scope = { spawn = { rotate = true , sendableLast = true , } , } , } ,
[
"nupp.tasks"
] = {
Scope = {
spawn = { rotate = true , overloadMembers = { [ 2 ] = "_spawnNamed" } , bodyMayBorrowScope = true , } ,
fork = { effect = "runtime.workers" , rotate = true , sendableLast = true , } ,
} ,
} ,
}



local function rotates ( moduleName , nominal , member ) 
local byNominal = COMPILER_SURFACES [ moduleName ]
local members = byNominal and byNominal [ nominal ] or nil
local surface = members and members [ member ] or nil

return surface ~= nil and surface . rotate == true
end

local __nuppExportValue= { COMPILER_SURFACES = COMPILER_SURFACES , rotates = rotates } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.surfaces"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.surfaces"]=__nuppExports;return __nuppExports