_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local capabilities = { }

local CONTRACTS


= {
bitops = { effect = "runtime.bitops" } ,
int64 = { effect = "runtime.int64" } ,
structvalue = { effect = "runtime.structvalue" } ,
cstorage = { effect = "runtime.cstorage" } ,
simd = { compiler = true } ,
cinterop = { } ,
presize = { compiler = true } ,
}


function capabilities . resolve ( ) 
local resolved = { byName = { } }
for name , contract in pairs ( CONTRACTS ) do
resolved . byName [ name ] = { kind = "native" , name = name , effect = contract . effect }
end

return resolved
end


function capabilities . get ( resolved , name ) 
local capability = resolved and resolved . byName and resolved . byName [ name ] or nil
assert ( CONTRACTS [ name ] ~= nil and capability ~= nil , "unknown language capability " .. name )

return capability
end


local function resolution ( checker ) 
local resolved = checker . opts . _capabilityResolution
if resolved == nil then
resolved = capabilities . resolve ( )
checker . opts . _capabilityResolution = resolved
end

return resolved
end





function capabilities . available ( checker , name ) 
return capabilities . get ( resolution ( checker ) , name ) . kind ~= "missing"
end


function capabilities . require ( checker , name , at ) 
if checker . opts . compat == "lua51" and not checker . declarationFile and ( checker . comptimeDepth or 0 ) == 0 then
checker . diag ( "NUPP3014" , at , ("compat = \"lua51\" does not include the `%s` representation") : format ( name ) )
return false
end
local capability = capabilities . get ( resolution ( checker ) , name )
if capability . kind ~= "missing" then
return true
end
local because = capability . reason and ": " .. capability . reason or ""
checker . diag ( "NUPP3006" , at , ("this compiler has no `%s` capability%s") : format ( name , because ) )

return false
end

local __nuppExportValue= capabilities ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.capabilities"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.capabilities"]=__nuppExports;return __nuppExports