_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["contract.hotpath"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("contract.hotpath\0runtime\0001") };

local declarations = require ( "nupp.serde" )
local json = require ( "nupp.serde.json" )

local Payload = {} Payload.__index = Payload ;_G.nupp.__reflect.link(Payload,__nuppT1[1],{ })




local binding = declarations . binding ( (_G.nupp.__reflect.known( Payload ) and  Payload  or  _G.nupp.__reflect.ensure( Payload ,function() return {["annotations"]={},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="uint32",["name"]="id",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="boolean",["name"]="active",["readable"]=true,["stored"]=true,["type"]=3,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="string",["name"]="name",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true}},["fingerprint"]="6eda281fdfeec107beff3791e765200d80b607e54e1f9ba4ded61723fe6e149d",["kind"]="record",["name"]="Payload",["qualifiedName"]="Payload",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="id",["optional"]=false,["type"]=2},{["mode"]="plain",["name"]="active",["optional"]=false,["type"]=3},{["mode"]="plain",["name"]="name",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="id",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="active",["read"]=3,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=3},{["annotations"]={},["hasDefault"]=false,["name"]="name",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="contract.hotpath",["name"]="Payload",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="uint32"},{["kind"]="boolean"},{["kind"]="string"}}},{["1"]="contract.hotpath\0runtime\0001"} end) ) )
local codec = json . codec ( )
local value = _G.setmetatable({ id =  0 ,  active =  true ,  name =  "trace probe" }, Payload)
local inputs = { }
for index = 1 , 16 do
value . id = (__nuppBitTobit( index )%4294967296)
inputs [ index ] = codec : encode ( binding , value )
end
local mode = arg [ 1 ] or "new-decode"
local requested = assert ( tonumber ( arg [ 2 ] or "20000" ) )
assert ( requested > 0 and requested % 1 == 0 )
local count = requested
local strings = { }
local values = { }
local checksum = 0
local start = os . clock ( )
if mode == "new-encode" then
for index = 1 , count do
value . id = (__nuppBitTobit( index % 16 + 1 )%4294967296)
local bytes = codec : encode ( binding , value )
strings [ index % 256 + 1 ] = bytes
checksum += # bytes
end
elseif mode == "new-decode" then
for index = 1 , count do
local decoded = codec : decode ( binding , inputs [ index % 16 + 1 ] )
values [ index % 256 + 1 ] = decoded
checksum += decoded . id
end

else
error ( "unknown trace probe mode" )
end
print ( mode , count , os . clock ( ) - start , checksum , # strings , # values )
 end);if not __nuppOk then package.loaded["contract.hotpath"]=nil;error(__nuppWhy,0) end;package.loaded["contract.hotpath"]=__nuppExports;return __nuppExports