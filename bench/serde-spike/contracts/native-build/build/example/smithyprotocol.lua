_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["example.smithyprotocol"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local body;__nuppExports["body"]=function(...) return body(...) end;local parameters;__nuppExports["parameters"]=function(...) return parameters(...) end;

local core = require ( "nupp.serde" )
local smithy = require ( "example.smithy" )
local routing = require ( "example.routing" )
local plans = require ( "nupp.serde.json" )
local json = require ( "nupp.codec.json" )

local function route ( member ) 
local header = member . traits : get ( "smithy.api#httpHeader" )
local query = member . traits : get ( "smithy.api#httpQuery" )
local stream = member : trait ( "smithy.api#streaming" )
assert ( header == nil or query == nil , "conflicting HTTP member locations" )
assert ( stream == nil or header == nil and query == nil , "stream cannot be a parameter" )
if header ~= nil then
return ( _G.setmetatable({ location =  "header" ,  name =  header : string ( ) }, routing.Route) )
elseif query ~= nil then
return ( _G.setmetatable({ location =  "query" ,  name =  query : string ( ) }, routing.Route) )
elseif stream ~= nil then
return ( _G.setmetatable({ location =  "stream" ,  name =  member . name }, routing.Route) )
else
return ( _G.setmetatable({ location =  "body" ,  name =  member . name }, routing.Route) )
end
end

local Parameters = {} Parameters.__index = Parameters

function Parameters:route(member) 
assert ( getmetatable ( member ) == smithy . Member , "expected Smithy member" )
local selected = member
assert ( selected . container == self . shape , "foreign Smithy member" )
return route ( selected )
end

local ParameterFactory = {} ParameterFactory.__index = ParameterFactory

function ParameterFactory:policy(member) 
assert (
getmetatable ( member ) == smithy . Member and ( member ) . target == self . shape ,
"foreign Smithy request"
)

return ( _G.setmetatable({ shape =  self . shape }, Parameters) )
end


local Body = {} Body.__index = Body

function Body:name(member) 
return self . base : name ( member )
end

function Body:select(member, direction) 
if route ( member ) . location ~= "body" then
return "omit"
end
return self . base : select ( member , direction )
end

function Body:timestamp(member, value) 
return self . base : timestamp ( member , value )
end

function Body:parseTimestamp(member, value, kind) 
return self . base : parseTimestamp ( member , value , kind )
end

local BodyFactory = {} BodyFactory.__index = BodyFactory

function BodyFactory:policy(member) 
local selected = self . base : policy ( member )
if getmetatable ( member ) ~= smithy . Member then
return selected
end

return ( _G.setmetatable({ base =  selected }, Body) )
end


parameters=function ( shape ) 
return ( _G.setmetatable({ shape =  shape }, ParameterFactory) )
end ;__nuppExports["parameters"]=parameters

body=function ( base ) 
return ( _G.setmetatable({ base =  base }, BodyFactory) )
end ;__nuppExports["body"]=body
 end);if not __nuppOk then package.loaded["example.smithyprotocol"]=nil;error(__nuppWhy,0) end;package.loaded["example.smithyprotocol"]=__nuppExports;return __nuppExports