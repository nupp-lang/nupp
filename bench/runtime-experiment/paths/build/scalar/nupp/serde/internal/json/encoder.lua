_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.internal.json.encoder"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local select;__nuppExports["select"]=function(...) return select(...) end;


local core = require ( "nupp.serde.internal.value" )
local plans = require ( "nupp.serde.internal.json.plan" )
local lowering = require ( "nupp.serde.internal.json.lower" )
local declarations = require ( "nupp.serde.internal.declaration" )
local structures = require ( "nupp.serde.internal.structure" )
local scalars = require ( "nupp.serde.internal.scalar" )
local numbers = require ( "nupp.serde.internal.numbers" )
local json = require ( "nupp.codec.json" )
local errors = require ( "nupp.serde.internal.errors" )





local Project = {} Project.__index = Project






function Project:emit(value, sink, budget) 
if self . present ( value ) then
sink :__nupp_m_c0a8d47c0983c3150b410efc4887655d05ff375642ad698506d923a11726a9cc ( self . key )
local get = self . get
if get . kind == "borrowed" then
self . encoding : write ( get . read ( value ) , sink , budget )
else
self . encoding : write ( get . read ( value ) , sink , budget )
end
end
end

function Project:write(value, sink, budget) 
local ok , problem = pcall ( self . emit , self , value , sink , budget )
if not ok then
error ( errors . wrap ( problem , self . path , nil ) , 0 )
end
end

local Field = {} Field.__index = Field




function Field:apply(member, has, get, set, adapter, fallback) 








if self . plan : action ( member ) ~= "traverse" then
return false
end
local child = self . plan : child ( member )
if child == nil then
return false
end
local path = self . path .. "[" .. json . encode ( member . name ) .. "]"
local encoding = self . resolver : resolve ( adapter , child , path )
if encoding == nil then
return false
end
self . fields [
# self . fields + 1
] = _G.setmetatable({ dynamic =
encoding . dynamic ,  key =
assert ( self . plan : key ( member ) ) ,  path =
path ,  present =
has ,  get =
get ,  encoding =
encoding }, Project)


return true
end

local Structure = {} Structure.__index = Structure



function Structure:write(value, sink, budget) 
if budget ~= nil then
budget : step ( self . path )
end
sink : startObject ( )
for _ , field in ipairs ( self . fields ) do
field : write ( value , sink , budget )
end
sink : endObject ( )
end

local SelectStructure = {} SelectStructure.__index = SelectStructure



function SelectStructure:apply(member, fields, construction, unknown, additional) 







if additional ~= nil then
return nil
end
local selected = { }
for _ , field in ipairs ( fields ) do
if not field : accept (
_G.setmetatable({ resolver =  self . resolver ,  plan =  self . plan ,  path =  self . path ,  fields =  selected }, Field)
) then
return nil
end
end

local dynamic = false
for _ , field in ipairs ( selected ) do
dynamic = dynamic or field . dynamic
end

return ( _G.setmetatable({ fields =  selected ,  dynamic =  dynamic ,  path =  self . path }, Structure) )
end

local Primitive = {} Primitive.__index = Primitive



function Primitive:write(value, sink, budget) 
if budget ~= nil then
budget : step ( self . path )
end
if self . kind == "string" then
sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( ( value ) : sub ( 1 ) )
elseif self . kind == "boolean" then
sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( value == true )
else
sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( numbers . floating ( ( value ) * 1 , 64 ) )
end
end

local Resolver = {} Resolver.__index = Resolver



function Resolver:resolve(adapter, plan, path) 
if self . active [ adapter ] or plan . description . nullable or self . depth >= 64 or self . values >= 1000000 then
return nil
end
self . active [ adapter ] = true
self . depth += 1
self . values += 1
local encoding = declarations . nativeEncoding ( adapter , plan , self , path )
if encoding == nil then
local scalar = scalars . nativeScalar ( adapter )
if scalar ~= nil then
encoding = _G.setmetatable({ kind =  scalar ,  path =  path ,  dynamic =  false }, Primitive)
else
encoding = structures . inspect (
adapter ,
_G.setmetatable({ resolver =  self ,  plan =  plan ,  path =  path }, SelectStructure)
)
end
end
self . active [ adapter ] = nil
self . depth -= 1

return encoding
end




select=function ( adapter , plan ) 
return ( _G.setmetatable({ active =  {} ,  depth =  0 ,  values =  0 }, Resolver) ) : resolve ( adapter , plan , "$" )
end ;__nuppExports["select"]=select
 end);if not __nuppOk then package.loaded["nupp.serde.internal.json.encoder"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.encoder"]=__nuppExports;return __nuppExports