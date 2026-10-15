_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT34={}; local function __nuppT31(...) return {n=select("#",...),...} end; local __nuppT35,__nuppT36,__nuppT37,__nuppT38,__nuppT39,__nuppT40,__nuppT41,__nuppT42=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT32(value) return value end; local function __nuppT33(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT40({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT41(v.primary) for _,reason in __nuppT42(v.suppressed) do text=text.."\ncleanup: "..__nuppT41(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["example.routing"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local codec;__nuppExports["codec"]=function(...) return codec(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;local query;__nuppExports["query"]=function(...) return query(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.routing\0runtime\0001") , _G.nupp.__reflect.declaration("example.routing\0runtime\0002") };

local core = require ( "nupp.serde" )


local Route = {} Route.__index = Route ;_G.nupp.__reflect.link(Route,__nuppT1[1],{ }) ;__nuppExports["Route"]=Route









local Parameter = {} Parameter.__index = Parameter ;_G.nupp.__reflect.link(Parameter,__nuppT1[2],{ }) ;__nuppExports["Parameter"]=Parameter





local function escape ( value ) 
return ( value : gsub ( "[^A-Za-z0-9_.~-]" , function ( byte ) 
return ("%%%02X") : format ( assert ( byte : byte ( ) ) )
end ) )
end

local Output = {} Output.__index = Output




function Output:include(member) 
return self . selected [ member ] ~= nil
end

function Output:token(member, value) 
assert ( self . depth == 1 and self . selected [ member ] ~= nil , "parameter outside the selected structure" )
local route = assert ( self . selected [ member ] )
assert ( route . location == "header" or route . location == "query" , "parameter has another location" )
if route . location == "header" then
assert ( not value : find ( "[\r\n]" ) , "invalid header value" )
end
self . parameters [
# self . parameters + 1
] = _G.setmetatable({ location =
route . location ,  name =
route . name ,  value =
route . location == "query" and escape ( value ) or value }, Parameter)

end

function Output:writeNull(member) 
error ( "null has no parameter representation in this protocol" , 2 )
end

function Output:writeString(member, value) 
self : token ( member , value )
end

function Output:writeBoolean(member, value) 
self : token ( member , value and "true" or "false" )
end

function Output:writeInteger(member, value) 
self : token ( member , value . decimal )
end

function Output:writeFloat(member, value, width) 
assert ( value == value and value ~= math . huge and value ~= - math . huge , "nonfinite parameter" )
self : token ( member , ( "%.17g" ) : format ( value ) )
end

function Output:writeNumberToken(member, value) 
self : token ( member , value )
end

function Output:writeBigInteger(member, value) 
self : token ( member , value )
end

function Output:writeDecimal(member, value) 
self : token ( member , value . coefficient .. "e" .. tostring ( value . exponent ) )
end

function Output:writeTimestamp(member, value) 
error ( "timestamp parameters require an explicit protocol conversion" , 2 )
end

function Output:writeBytes(member, value) 
error ( "blob parameters require an explicit protocol conversion" , 2 )
end

function Output:writeAtom(member, value) 
error ( "atom parameters require an explicit protocol conversion" , 2 )
end

function Output:writeDocument(member, value, adapter) 
error ( "documents have no parameter representation in this protocol" , 2 )
end

function Output:writeStruct(member, source, emit) 
assert ( self . depth == 0 , "nested parameter structure" )
self . depth = 1
emit : apply ( source , self )
self . depth = 0
end

function Output:writeUnion(member, source, emit) 
error ( "unions have no parameter representation in this protocol" , 2 )
end

function Output:writeList(member, size, source, emit) 
error ( "lists require an explicit protocol parameter style" , 2 )
end

function Output:writeTuple(member, size, source, emit) 
error ( "tuples have no parameter representation in this protocol" , 2 )
end

function Output:writeMap(member, size, source, emit) 
error ( "maps require an explicit protocol parameter style" , 2 )
end

function Output:writeEntry(key, keyEmit, value, valueEmit) 






error ( "map entry outside a parameter map" , 2 )
end

function Output:writeUnknown(field, value, adapter) 





error ( "unknown members have no parameter routing" , 2 )
end

function Output:close() 
end


local Selection = {} Selection.__index = Selection


local Entry = {} Entry.__index = Entry



local Scope = {} Scope.__index = Scope




function Scope:clear() 
assert ( self . active == 0 , "parameter extensions are initializing" )
self . entries = { }
self . count = 0
end

function Scope:resolve(adapter, factory) 
local entry = self . entries [ adapter ]
if entry ~= nil then
assert ( entry . state ~= "initializing" , "recursive parameter extension" )
if entry . state == "failed" then
error ( entry . value , 0 )
elseif entry . state ~= "ready" then
error ( "invalid parameter extension state" , 0 )
end
return entry . value
end
assert ( self . count < 256 , "parameter extension cache is full" )
entry = _G.setmetatable({ state =  "initializing" }, Entry)
self . entries [ adapter ] = entry
self . count += 1
self . active += 1
local ok , value = pcall ( function ( ) 
local description = adapter : describe ( "write" )
assert ( description . kind == "structure" , "parameters require a structure" )
local policy = factory : policy ( description . member )
local routes = { }
local names = { }
for _ , child in ipairs ( description . children ) do
local route = policy : route ( child . member )
if route . location == "header" or route . location == "query" then
local field = child : describe ( "write" )
assert (
field . kind == "string"
or field . kind == "boolean"
or field . kind == "integer"
or field . kind == "float"
or field . kind == "numberToken"
or field . kind == "bigInteger"
or field . kind == "decimal" ,
"unsupported parameter representation"
)
local identity = route . location .. ":" .. (
route . location == "header" and route . name : lower ( ) or route . name
)
assert ( not names [ identity ] , "colliding parameter name" )
names [ identity ] = true
if route . location == "header" then
assert ( route . name : match ( "^[!#$%%&'*+.^_`|~%w-]+$" ) , "invalid header name" )
end
routes [
child . member
] = _G.setmetatable({ location =
route . location ,  name =
route . location == "query" and escape ( route . name ) or route . name }, Route)

end
end

return ( _G.setmetatable({ routes =  routes }, Selection) )
end )
self . active -= 1
entry . state = ok and "ready" or "failed"
entry . value = value
if not ok then
error ( value , 0 )
end

return value
end


local function output ( parameters , selected ) 
return ( _G.setmetatable({ parameters =  parameters ,  selected =  selected ,  depth =  0 }, Output) )
end

local Encode = {} Encode.__index = Encode


function Encode:apply(adapter, value) 
local selected = self . scope : resolve ( adapter , self . factory )
local parameters = { }
do local __nuppT43=0; local  __nuppT49 ; local __nuppT50=false ; local __nuppT44,__nuppT45,__nuppT46=__nuppT36(function() do local __nuppT51= output ( parameters , selected . routes ) ; __nuppT49= __nuppT51 ; __nuppT43=1;  __nuppT50=true;  local writer=__nuppT49;
adapter : write ( value , writer )
do (function(__nuppT52,...)  __nuppT50=false; return __nuppT52:close(...)  end)( writer ) end

return "return",__nuppT31( parameters ) end; return "normal" end,__nuppT32); local __nuppT47={}; local __nuppT48=0; if __nuppT43>=1 and __nuppT50 then  local __nuppT53,__nuppT54=__nuppT35(__nuppCleanup1,__nuppT49);  if not __nuppT53 then __nuppT48=__nuppT48+1; __nuppT47[__nuppT48]=__nuppT54 end; end; if not __nuppT44 then if __nuppT48>0 then __nuppT37(__nuppT33(__nuppT45,__nuppT47,1),0) else __nuppT37(__nuppT45,0) end end; if __nuppT48>0 then if __nuppT48>1 then __nuppT37(__nuppT33(__nuppT47[1],__nuppT47,2),0) else __nuppT37(__nuppT47[1],0) end end; if __nuppT45=="return" then  return __nuppT38(__nuppT46,1,__nuppT46.n)  end; end
end






local Cached = {} Cached.__index = Cached


function Cached:encode(binding, value) 
return binding : accept ( _G.setmetatable({ factory =  self . factory ,  scope =  self . scope }, Encode) , value )
end

function Cached:clear() 
self . scope : clear ( )
end

codec=function ( factory ) 
return ( _G.setmetatable({ factory =  factory ,  scope =  _G.setmetatable({ entries =  {} ,  count =  0 ,  active =  0 }, Scope) }, Cached) )
end ;__nuppExports["codec"]=codec

encode=function ( binding , value , factory ) 
return binding : accept ( _G.setmetatable({ factory =  factory ,  scope =  _G.setmetatable({ entries =  {} ,  count =  0 ,  active =  0 }, Scope) }, Encode) , value )
end ;__nuppExports["encode"]=encode

query=function ( parameters ) 
local parts = { }
for _ , parameter in ipairs ( parameters ) do
if parameter . location == "query" then
parts [ # parts + 1 ] = parameter . name .. "=" .. parameter . value
end
end

return table . concat ( parts , "&" )
end ;__nuppExports["query"]=query
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Parameter]="example.routing\0Parameter";__nuppWorkerRecords[Route]="example.routing\0Route"; end);if not __nuppOk then package.loaded["example.routing"]=nil;error(__nuppWhy,0) end;package.loaded["example.routing"]=__nuppExports;return __nuppExports