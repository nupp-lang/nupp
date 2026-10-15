_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






const _DYNAMIC_REQUIRES = "@requires-dynamically nothing"




















local reflectruntime = { }
local extensions = require ( "nupp.compiler.runtime.extensions" )







local function claim ( namespace , name , fresh ) 
local present = rawget ( namespace , name )
if present ~= nil then
return present
end
rawset ( namespace , name , fresh )

return fresh
end









function reflectruntime . installFieldCodec ( namespace ) 
local fieldcodec = claim ( namespace , "fieldcodec" , { } )
fieldcodec . keyed = function ( fields , fingerprint , recordType ) 
local Codec = { }
Codec . __index = Codec
function Codec : encode ( value ) 
if type ( value ) ~= "table" then
error ( "nupp: keyed codec value must be a table" , 2 )
end
local out = { }
for _ , name in ipairs ( fields ) do
local field = rawget ( value , name )
if field ~= nil then
out [ name ] = field
end
end

return out
end

function Codec : decode ( value ) 
if type ( value ) ~= "table" then
return nil , "$: expected keyed table"
end
local out = { }
for _ , name in ipairs ( fields ) do
local field = rawget ( value , name )
if field ~= nil then
out [ name ] = field
end
end

return setmetatable ( out , recordType ) , nil
end

return setmetatable ( { fingerprint = fingerprint } , Codec )
end
end



function reflectruntime . install ( namespace ) 
require ( "nupp.compiler.runtime.typewitness" ) . install ( namespace )
local api = claim ( namespace , "reflect" , { } )
api . extensionKey = extensions . key
local reflect = claim ( namespace , "__reflect" , { } )
local blueprints = reflect . blueprints or setmetatable ( { } , { __mode = "k" } )
local infos = claim ( reflect , "valueInfos" , setmetatable ( { } , { __mode = "kv" } ) )
local states = claim ( reflect , "valueStates" , setmetatable ( { } , { __mode = "kv" } ) )
local infoKey = claim ( reflect , "infoKey" , { } )
local ctypeInfos = claim ( reflect , "ctypeInfos" , setmetatable ( { } , { __mode = "k" } ) )
local references = claim ( reflect , "references" , setmetatable ( { } , { __mode = "k" } ) )
local targetsKey = reflect . targetsKey
local ctypeTargets = reflect . ctypeTargets

local Info = { }












function Info : extension ( extension ) 
local state = states [ self ]
if not state then
error ( "nupp: foreign reflection descriptor" , 2 )
end

return extensions . resolve ( self , extension )
end




Info . read = function ( state , key ) 
if key == "extension" then
return Info . extension
elseif key == "type" then
return state and state . type
end

return state and state . blueprint [ key ]
end

Info . __newindex = function ( ) 
error ( "nupp: reflection descriptors are immutable" , 2 )
end

function reflect . get ( typeObject ) 
local prior = infos [ typeObject ] or ctypeInfos [ typeObject ]
if prior then
return prior
end
local declared = blueprints [ typeObject ]
if not declared then
error ( "nupp: type has no reflection blueprint" , 2 )
end
local state = { type = typeObject , blueprint = declared }
local info = setmetatable ( { } , {
__index = function ( _ , key ) 
return Info . read ( state , key )
end ,
__newindex = Info . __newindex ,
} )
infos [ typeObject ] = info
states [ info ] = state


if type ( typeObject ) == "table" then
rawset ( typeObject , infoKey , info )
else
ctypeInfos [ typeObject ] = info
end
extensions . host ( info )

return info
end

api . runtime = reflect . get

function api . runtimeType ( info , index ) 
local state = states [ info ]
if state == nil then
error ( "nupp: foreign reflection descriptor" , 2 )
end
if index == state . blueprint . root then
return state . type
end
local keys = references [ state . type ]
local wanted = keys and keys [ tostring ( index ) ]
if wanted == nil then
return nil
end
local visited = { }

local function search ( typeObject ) 
if visited [ typeObject ] then
return nil
end
visited [ typeObject ] = true
local targets = type ( typeObject ) == "table" and rawget ( typeObject , targetsKey ) or ctypeTargets [ typeObject ]
if targets == nil then
return nil
end
local direct = targets [ wanted ]
if direct ~= nil then
if direct [ 1 ] == nil and direct . module then
require ( direct . module )
end
return direct [ 1 ]
end
for _ , cell in pairs ( targets ) do
if cell [ 1 ] == nil and cell . module then
require ( cell . module )
end
if cell [ 1 ] ~= nil then
local answer = search ( cell [ 1 ] )
if answer ~= nil then
return answer
end
end
end

return nil
end

return search ( state . type )
end

end

local __nuppExportValue= reflectruntime ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.runtime.reflect"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.runtime.reflect"]=__nuppExports;return __nuppExports