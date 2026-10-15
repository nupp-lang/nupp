_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.comptime.materialize.observe\0runtime\0001") };



local cst = require ( "nupp.compiler.syntax.cst" )

local observe = {} observe.__index = observe ;_G.nupp.__reflect.link(observe,__nuppT1[1],{ })




local function copyPublic ( entry ) 
return {
source = entry . source ,
line = entry . line ,
column = entry . column ,
provider = entry . provider ,
schema = entry . schema ,
fingerprint = entry . fingerprint ,
backend = entry . backend ,
blueprintSize = entry . blueprintSize ,
generatedSize = entry . generatedSize ,
runtimeFeatures = entry . runtimeFeatures ,
abis = entry . abis ,
}
end

local function copyStored ( entry ) 
local copy = { }
for key , value in pairs ( entry ) do
copy [ key ] = value
end

return copy
end



function observe . collect ( root , filename ) 
local found = { }

local function walk ( node ) 
if not node or cst . isToken ( node ) then
return
end
if node . materializationObservation then
local token = cst . firstToken ( node )



local entry = copyStored ( node . materializationObservation )
entry . source = filename
entry . line = token and token . line or 1
entry . column = token and token . col or 1
found [ # found + 1 ] = entry
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( root )

return found
end


function observe . public ( entries ) 
local out = { }
for index , entry in ipairs ( entries or { } ) do
out [ index ] = ( { source = entry . source , line = entry . line , column = entry . column , provider = entry . provider , schema = entry . schema , fingerprint = entry . fingerprint , backend = entry . backend , blueprintSize = entry . blueprintSize , generatedSize = entry . generatedSize , runtimeFeatures = entry . runtimeFeatures , abis = entry . abis , } )
end

return out
end

local __nuppExportValue= observe ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.comptime.materialize.observe"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.comptime.materialize.observe"]=__nuppExports;return __nuppExports