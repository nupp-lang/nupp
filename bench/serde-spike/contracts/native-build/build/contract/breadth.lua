_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("contract.breadth\0runtime\0001") , _G.nupp.__reflect.declaration("contract.breadth\0runtime\0004") , _G.nupp.__reflect.declaration("contract.breadth\0runtime\0005") };

local __serdeJson = require ( "nupp.serde.json" )

local model = require ( "example.richmodel" )
local smithy = require ( "example.smithy" )
local api = require ( "example.openapi" )
local registry = require ( "example.registry" )
local core = require ( "nupp.serde" )
local serde = require ( "nupp.serde" )
local json = require ( "nupp.serde.json" )
local syntax = require ( "nupp.codec.json" )
local text = require ( "nupp.text" )
local docs = require ( "nupp.serde.document" )
local bridge = require ( "nupp.serde.document" )
local readers = require ( "nupp.serde.document" )
local views = require ( "nupp.serde.document" )
local cases = { }

local function task ( name , work ) 
local value = work ( )
assert ( value ~= nil )
cases [ # cases + 1 ] = { name = name , work = work }
end

local function bindingCases ( name , binding , input , policy ) 
local codec = json . codec ( policy )
local value = codec : decode ( binding , input )
local canonical = codec : encode ( binding , value )
assert ( codec : encode ( binding , codec : decode ( binding , canonical ) ) == canonical )
local buffer = text . newBuffer ( )
task ( name .. "/encode" , function ( ) 
return codec : encode ( binding , value )
end )
task ( name .. "/decode" , function ( ) 
return codec : decode ( binding , input )
end )
task ( name .. "/buffer" , function ( ) 
buffer : reset ( )
codec : encodeInto ( binding , value , buffer )
return # buffer
end )
task ( name .. "/fresh-buffer" , function ( ) 
local fresh = text . newBuffer ( )
codec : encodeInto ( binding , value , fresh )
return fresh
end )
task ( name .. "/embedded" , function ( ) 
buffer : reset ( )
do local __nuppT21=0; local  __nuppT27 ; local __nuppT28=false ; local __nuppT22,__nuppT23,__nuppT24=__nuppT14(function() do local __nuppT29= syntax . newWriter ( buffer ) ; __nuppT27= __nuppT29 ; __nuppT21=1;  __nuppT28=true;  local sink=__nuppT27;
sink : startArray ( )
codec : writeValue ( binding , value , sink )
sink : endArray ( )
do (function(__nuppT30,...)  __nuppT28=false; return __nuppT30:close(...)  end)( sink ) end

return "return",__nuppT9( # buffer ) end; return "normal" end,__nuppT10); local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 and __nuppT28 then  local __nuppT31,__nuppT32=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT31 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT32 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end )

return value , codec
end

local schema = model . newModel ( )
local nominal , indexed , document = model . binding ( schema ) , model . indexed ( schema ) , model . documentBinding ( schema )
local epoch , date = model . policy ( true ) , model . policy ( false )

local value , codec = bindingCases ( "recursive/nominal" , nominal , "{\"identifier\":\"outer\",\"created\":0.000000001,\"next\":{\"identifier\":\"inner\",\"created\":-0.5},\"labels\":{\"7\":\"seven\"}}" , epoch )
bindingCases ( "recursive/indexed" , indexed , "{\"identifier\":\"outer\",\"created\":0.000000001,\"next\":{\"identifier\":\"inner\",\"created\":-0.5},\"labels\":{\"7\":\"seven\"}}" , epoch )
bindingCases ( "recursive/document" , document , "{\"identifier\":\"outer\",\"created\":0.000000001,\"next\":{\"identifier\":\"inner\",\"created\":-0.5},\"labels\":{\"7\":\"seven\"}}" , epoch )
local logical = bridge . from ( nominal , value )
local view , viewAdapter = views . view ( nominal , value ) , views . viewAdapter ( nominal )
task ( "document/typed-view-create" , function ( ) 
return views . view ( nominal , value )
end )
task ( "document/typed-view-encode" , function ( ) 
return codec : encodeDocument ( viewAdapter , view )
end )
task ( "document/typed-snapshot" , function ( ) 
return view : snapshot ( )
end )
task ( "document/snapshot" , function ( ) 
return readers . snapshot ( logical )
end )
task ( "document/project" , function ( ) 
return bridge . from ( nominal , value )
end )
local reconstruction = bridge . decoder ( nominal )
task ( "document/reconstruct" , function ( ) 
return reconstruction : read ( logical )
end )
local store = registry . registry ( )
store : register ( "example#Packet" , nominal )
task ( "document/registry" , function ( ) 
return store : reconstruct ( "example#Packet" , logical )
end )
local dateCodec = json . codec ( date )
local alternate = false
task ( "policy/switch" , function ( ) 
alternate = not alternate
return ( alternate and codec or dateCodec ) : encode ( nominal , value )
end )
task ( "extensions/cold" , function ( ) 
local fresh = json . codec ( epoch )
return fresh : encode ( nominal , value )
end )
local apiBinding = api . binding ( api . model ( ) )
bindingCases (
"openapi/request" ,
apiBinding ,
"{\"name\":\"other\",\"secret\":\"hidden\",\"payload\":7,\"extra\":true}" ,
api . policy ( "request" )
)
local ast = "{\"smithy\":\"2.0\",\"shapes\":{\"example#Request\":{\"type\":\"structure\",\"members\":{\"id\":{\"target\":\"smithy.api#String\",\"traits\":{\"smithy.api#required\":{}}},\"active\":{\"target\":\"smithy.api#Boolean\",\"traits\":{\"smithy.api#required\":{}}},\"name\":{\"target\":\"smithy.api#String\",\"traits\":{\"smithy.api#required\":{}}}}}}}"
local loaded = smithy . parse ( "{\"smithy\":\"2.0\",\"shapes\":{\"example#Request\":{\"type\":\"structure\",\"members\":{\"id\":{\"target\":\"smithy.api#String\",\"traits\":{\"smithy.api#required\":{}}},\"active\":{\"target\":\"smithy.api#Boolean\",\"traits\":{\"smithy.api#required\":{}}},\"name\":{\"target\":\"smithy.api#String\",\"traits\":{\"smithy.api#required\":{}}}}}}}" )
local smithyBinding = smithy . binding ( loaded : shape ( "example#Request" ) )
bindingCases ( "smithy/document" , smithyBinding , "{\"id\":\"7\",\"active\":true,\"name\":\"sample\"}" , smithy . policy ( false , true ) )
task ( "model/load" , function ( ) 
return smithy . parse ( "{\"smithy\":\"2.0\",\"shapes\":{\"example#Request\":{\"type\":\"structure\",\"members\":{\"id\":{\"target\":\"smithy.api#String\",\"traits\":{\"smithy.api#required\":{}}},\"active\":{\"target\":\"smithy.api#Boolean\",\"traits\":{\"smithy.api#required\":{}}},\"name\":{\"target\":\"smithy.api#String\",\"traits\":{\"smithy.api#required\":{}}}}}}}" )
end )
local Strings = {} Strings.__index = Strings ;_G.nupp.__reflect.link(Strings,__nuppT1[1],{ })




local structure = require ( "nupp.serde.adapters" )
local scalar = require ( "nupp.serde.adapters" )
local StringBuilder = {} StringBuilder.__index = StringBuilder



function StringBuilder:close() 
self . id , self . active , self . name = nil , nil , nil
end

local StringConstruction = {} StringConstruction.__index = StringConstruction
function StringConstruction:begin() 
return ( _G.setmetatable({ }, StringBuilder) )
end

function StringConstruction:finish(state) 
do local __nuppT46=0; local  __nuppT52 ; local __nuppT53=false ; local __nuppT47,__nuppT48,__nuppT49=__nuppT14(function() do local __nuppT54= state ; __nuppT52= __nuppT54 ; __nuppT46=1;  __nuppT53=true;  local owned=__nuppT52;
local active = owned . active
assert ( active ~= nil )
local result = _G.setmetatable({ id =  assert ( owned . id ) ,  active =  active ,  name =  assert ( owned . name ) }, Strings)
do (function(__nuppT55,...)  __nuppT53=false; return __nuppT55:close(...)  end)( owned ) end

return "return",__nuppT9( result ) end; return "normal" end,__nuppT10); local __nuppT50={}; local __nuppT51=0; if __nuppT46>=1 and __nuppT53 then  local __nuppT56,__nuppT57=__nuppT13(__nuppCleanup1,__nuppT52);  if not __nuppT56 then __nuppT51=__nuppT51+1; __nuppT50[__nuppT51]=__nuppT57 end; end; if not __nuppT47 then if __nuppT51>0 then __nuppT15(__nuppT11(__nuppT48,__nuppT50,1),0) else __nuppT15(__nuppT48,0) end end; if __nuppT51>0 then if __nuppT51>1 then __nuppT15(__nuppT11(__nuppT50[1],__nuppT50,2),0) else __nuppT15(__nuppT50[1],0) end end; if __nuppT48=="return" then  return __nuppT16(__nuppT49,1,__nuppT49.n)  end; end
end

local smithyShape = loaded : shape ( "example#Request" )
local idMember , activeMember , nameMember = assert (
smithyShape : member ( "id" )
) , assert ( smithyShape : member ( "active" ) ) , assert ( smithyShape : member ( "name" ) )
local smithyFields = {
structure . field (
idMember ,
function ( value ) 
return value . id
end ,
function ( state , value ) 
state . id = value
end ,
scalar . text ( idMember ) ,
true ,
false
) ,
structure . field (
activeMember ,
function ( value ) 
return value . active
end ,
function ( state , value ) 
state . active = value
end ,
scalar . boolean ( activeMember ) ,
true ,
false
) ,
structure . field (
nameMember ,
function ( value ) 
return value . name
end ,
function ( state , value ) 
state . name = value
end ,
scalar . text ( nameMember ) ,
true ,
false
)
}
local typedSmithy = _G.setmetatable({ adapter =
structure . structure ( smithy . root ( smithyShape ) , smithyFields , _G.setmetatable({ }, StringConstruction) , nil , nil , true ) }, core.Bound)

bindingCases ( "smithy/nominal" , typedSmithy , "{\"id\":\"7\",\"active\":true,\"name\":\"sample\"}" , smithy . policy ( false , true ) )
bindingCases ( "declaration/smithy-equivalent" , serde . binding ( (_G.nupp.__reflect.known( Strings ) and  Strings  or  _G.nupp.__reflect.ensure( Strings ,function() return {["annotations"]={},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="string",["name"]="id",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="boolean",["name"]="active",["readable"]=true,["stored"]=true,["type"]=3,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="string",["name"]="name",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true}},["fingerprint"]="6ad0ee698834673269f0f8714c0649d62b079c54e911241961ec6aca73a56cc2",["kind"]="record",["name"]="Strings",["qualifiedName"]="Strings",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="id",["optional"]=false,["type"]=2},{["mode"]="plain",["name"]="active",["optional"]=false,["type"]=3},{["mode"]="plain",["name"]="name",["optional"]=false,["type"]=2}},["requiresFactory"]=false},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="id",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="active",["read"]=3,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=3},{["annotations"]={},["hasDefault"]=false,["name"]="name",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="contract.breadth",["name"]="Strings",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="string"},{["kind"]="boolean"}}},{["1"]="contract.breadth\0runtime\0001"} end) ) ) , "{\"id\":\"7\",\"active\":true,\"name\":\"sample\"}" )
local Escaped = {} Escaped.__index = Escaped ;_G.nupp.__reflect.link(Escaped,__nuppT1[2],{ })


local escaped = serde . binding (
(_G.nupp.__reflect.known( Escaped ) and  Escaped  or  _G.nupp.__reflect.ensure( Escaped ,function() return {["annotations"]={},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="string",["name"]="name",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true}},["fingerprint"]="1807b748dc3825371dc4d8721c914d6e87124a2cb434a879fe2ce78e4739f2e1",["kind"]="record",["name"]="Escaped",["qualifiedName"]="Escaped",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="name",["optional"]=false,["type"]=2}},["requiresFactory"]=false},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="name",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="contract.breadth",["name"]="Escaped",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="string"}}},{["1"]="contract.breadth\0runtime\0004"} end) ) ,
_G.setmetatable({ fields =  { name = _G.setmetatable({ name =  'a"b' ,  omitEmpty =  false }, serde.FieldOptions) } ,  unknownMembers =  "ignore" ,  naming =  "identity" }, serde.Options)
)
bindingCases ( "matching/escaped-unknown" , escaped , "{\"unknown\":{\"nested\":[1,null,{\"x\":false}]},\"a\\\"b\":\"value\"}" )
local Event = {} Event.__index = Event ;_G.nupp.__reflect.link(Event,__nuppT1[3],{ })


local hook = serde . binding (
(_G.nupp.__reflect.known( Event ) and  Event  or  _G.nupp.__reflect.ensure( Event ,function() return {["annotations"]={},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="integer",["name"]="createdAt",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true}},["fingerprint"]="c93855f257b30638725f85b3d4fc480d216b6afbc5ea3a20e8148f19c9827e74",["kind"]="record",["name"]="Event",["qualifiedName"]="Event",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="createdAt",["optional"]=false,["type"]=2}},["requiresFactory"]=false},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="createdAt",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="contract.breadth",["name"]="Event",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="integer"}}},{["1"]="contract.breadth\0runtime\0005"} end) ) ,
_G.setmetatable({ fields =  { createdAt = _G.setmetatable({ representation =  serde . iso8601Seconds ,  omitEmpty =  false }, serde.FieldOptions) } ,  naming =  "identity" ,  unknownMembers =  "reject" }, serde.Options)
)
bindingCases ( "hook/timestamp" , hook , "{\"createdAt\":\"1970-01-01T00:00:02Z\"}" )
local documentAdapter = docs . adapter ( )
local rich = docs . tuple ( {
docs . bigInteger ( "123456789012345678901234567890" ) ,
docs . decimal ( _G.setmetatable({ coefficient =  "12345678901234567890" ,  exponent =  - 9 }, core.Decimal) ) ,
docs . bytes ( string . rep ( "blob" , 16384 ) )
} )
local richCodec = json . codec ( epoch )
local richBytes = richCodec : encodeDocument ( documentAdapter , rich )
task ( "rich/blob-exact-encode" , function ( ) 
return richCodec : encodeDocument ( documentAdapter , rich )
end )
task ( "rich/json-contents-decode" , function ( ) 
return richCodec : decodeDocument ( documentAdapter , richBytes )
end )
bindingCases (
"large-string" ,
serde . binding ( (_G.nupp.__reflect.known( Strings ) and  Strings  or  _G.nupp.__reflect.ensure( Strings ,function() return {["annotations"]={},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="string",["name"]="id",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="boolean",["name"]="active",["readable"]=true,["stored"]=true,["type"]=3,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="string",["name"]="name",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true}},["fingerprint"]="6ad0ee698834673269f0f8714c0649d62b079c54e911241961ec6aca73a56cc2",["kind"]="record",["name"]="Strings",["qualifiedName"]="Strings",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="id",["optional"]=false,["type"]=2},{["mode"]="plain",["name"]="active",["optional"]=false,["type"]=3},{["mode"]="plain",["name"]="name",["optional"]=false,["type"]=2}},["requiresFactory"]=false},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="id",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="active",["read"]=3,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=3},{["annotations"]={},["hasDefault"]=false,["name"]="name",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="contract.breadth",["name"]="Strings",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="string"},{["kind"]="boolean"}}},{["1"]="contract.breadth\0runtime\0001"} end) ) ) ,
"{\"id\":\"7\",\"active\":true,\"name\":" .. syntax . encode ( string . rep ( "large \" payload " , 4096 ) ) .. "}"
)
local richContents = documentAdapter : contents ( )
local richBuffer = text . newBuffer ( )
local richCanonical = richCodec : encode ( richContents , rich )
richCodec : encodeInto ( richContents , rich , richBuffer )
assert ( richBuffer : tostring ( ) == richCanonical )
task ( "rich/blob-buffer" , function ( ) 
richBuffer : reset ( )
richCodec : encodeInto ( richContents , rich , richBuffer )
return # richBuffer
end )
task ( "rich/blob-fresh-buffer" , function ( ) 
local fresh = text . newBuffer ( )
richCodec : encodeInto ( richContents , rich , fresh )
return fresh
end )
task ( "rich/blob-embedded" , function ( ) 
richBuffer : reset ( )
do local __nuppT69=0; local  __nuppT75 ; local __nuppT76=false ; local __nuppT70,__nuppT71,__nuppT72=__nuppT14(function() do local __nuppT77= syntax . newWriter ( richBuffer ) ; __nuppT75= __nuppT77 ; __nuppT69=1;  __nuppT76=true;  local sink=__nuppT75;
sink : startArray ( )
richCodec : writeValue ( richContents , rich , sink )
sink : endArray ( )
do (function(__nuppT78,...)  __nuppT76=false; return __nuppT78:close(...)  end)( sink ) end

return "return",__nuppT9( # richBuffer ) end; return "normal" end,__nuppT10); local __nuppT73={}; local __nuppT74=0; if __nuppT69>=1 and __nuppT76 then  local __nuppT79,__nuppT80=__nuppT13(__nuppCleanup1,__nuppT75);  if not __nuppT79 then __nuppT74=__nuppT74+1; __nuppT73[__nuppT74]=__nuppT80 end; end; if not __nuppT70 then if __nuppT74>0 then __nuppT15(__nuppT11(__nuppT71,__nuppT73,1),0) else __nuppT15(__nuppT71,0) end end; if __nuppT74>0 then if __nuppT74>1 then __nuppT15(__nuppT11(__nuppT73[1],__nuppT73,2),0) else __nuppT15(__nuppT73[1],0) end end; if __nuppT71=="return" then  return __nuppT16(__nuppT72,1,__nuppT72.n)  end; end
end )

local bounded = json . codec ( epoch , 8 )
for index = 1 , 64 do
local binding = model . binding ( model . newModel ( ) )
local item = bounded : decode ( binding , "{\"identifier\":\"outer\",\"created\":0.000000001,\"next\":{\"identifier\":\"inner\",\"created\":-0.5},\"labels\":{\"7\":\"seven\"}}" )
assert ( bounded : encode ( binding , item ) ~= "" )
assert ( bounded : cachedBindings ( ) <= 8 )
end
bounded : clear ( )
assert ( bounded : cachedBindings ( ) == 0 )
local __nuppExportValue= cases ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["contract.breadth"]=nil;error(__nuppWhy,0) end;package.loaded["contract.breadth"]=__nuppExports;return __nuppExports