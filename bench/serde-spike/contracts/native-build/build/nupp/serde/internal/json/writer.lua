_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT39={}; local function __nuppT36(...) return {n=select("#",...),...} end; local __nuppT40,__nuppT41,__nuppT42,__nuppT43,__nuppT44,__nuppT45,__nuppT46,__nuppT47=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT37(value) return value end; local function __nuppT38(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT45({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT46(v.primary) for _,reason in __nuppT47(v.suppressed) do text=text.."\ncleanup: "..__nuppT46(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.internal.json.writer"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local output;__nuppExports["output"]=function(...) return output(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.json.writer\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.writer\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.writer\0runtime\0003") };

local core = require ( "nupp.serde.internal.value" )
local errors = require ( "nupp.serde.internal.errors" )
local plans = require ( "nupp.serde.internal.json.plan" )
local json = require ( "nupp.codec.json" )
local base64 = require ( "nupp.codec.base64" )
local numbers = require ( "nupp.serde.internal.numbers" )
local identities = require ( "nupp.serde.internal.json.document" )
local extensions = require ( "nupp.serde.internal.json.extensions" )

local Budget = {} Budget.__index = Budget ;_G.nupp.__reflect.link(Budget,__nuppT1[1],{ }) ;__nuppExports["Budget"]=Budget






local writeContents








local Frame = {} Frame.__index = Frame ;_G.nupp.__reflect.link(Frame,__nuppT1[2],{ _G.nupp.__reflect.reference("nupp.serde.internal.json.plan\0runtime\0001","nupp.serde.internal.json.plan") })








local Output = {} Output.__index = Output













function Output:live() 
if self . closed then
error ( "value writer scope has expired" , 2 )
end
end

function Output:emit(adapter, value) 
self : live ( )
local ok , problem = pcall ( adapter . write , adapter , value , self )
if ok and ( self . roots ~= 1 or # self . frames ~= 0 ) then
ok = false
problem = _G.setmetatable({ code =
"contract" ,  message =
"binding must write exactly one root value" ,  path =
"$" ,  cause =
nil ,  suppressed =  {} }, errors.Error)

end
if not ok then
self . closed = true
self . sink : abort ( )
error ( errors . wrap ( problem , self : path ( ) , nil ) , 0 )
end
end

function Output:path() 
local parts = { "$" }
for _ , frame in ipairs ( self . frames ) do
if frame . currentName ~= nil then
parts [ # parts + 1 ] = "[" .. json . encode ( frame . currentName ) .. "]"
elseif frame . currentIndex ~= nil then
parts [ # parts + 1 ] = "[" .. tostring ( frame . currentIndex ) .. "]"
end
end

return table . concat ( parts )
end

function Output:select(member) 
local frame = self . frames [ # self . frames ]
if frame ~= nil then
if frame . kind == "object" then
frame . currentName = member . name
elseif frame . kind == "array" then
frame . currentIndex = frame . count + 1
end
end
end

function Output:include(member) 
self : live ( )
self : select ( member )
local frame = self . frames [ # self . frames ]
local action = frame ~= nil and frame . plan : action ( member ) or "traverse"
if action == "redact" then
self : writeString ( member , "[redacted]" )
end

return action == "traverse"
end

function Output:position(member) 
self : live ( )
self . budget . values += 1
if self . budget . values > self . budget . maxValues then
self : limit ( "value limit exceeded" )
end
if self . keyMode then
error ( "JSON map keys must be scalar" , 2 )
end
local frame = self . frames [ # self . frames ]
if frame ~= nil then
if frame . kind == "object" then
local key = frame . plan : key ( member )
local name = frame . plan : wireName ( member )
if key == nil and frame . plan . description . kind == "dynamic" then
name = self . policy : name ( member )
key = json . encodedString ( name )
end
if key == nil then
error ( "member was not selected for JSON: " .. member . name , 2 )
end
self : claim ( assert ( name ) )
self . sink :__nupp_m_c0a8d47c0983c3150b410efc4887655d05ff375642ad698506d923a11726a9cc ( key )
end
frame . count += 1
else
self . roots += 1
if self . roots ~= 1 then
error (
_G.setmetatable({ code =
"contract" ,  message =
"binding wrote more than one root value" ,  path =
"$" ,  cause =
nil ,  suppressed =  {} }, errors.Error)
,
0
)
end
end
end

function Output:limit(message) 
self . closed = true
error ( _G.setmetatable({ code =  "limit" ,  message =  message ,  path =  self : path ( ) ,  cause =  nil ,  suppressed =  {} }, errors.Error) , 0 )
end

function Output:enter() 
if self . budget . depth >= self . budget . maxDepth then
self : limit ( "nesting limit exceeded" )
end
self . budget . depth += 1
end

function Output:claim(name) 
local frame = assert ( self . frames [ # self . frames ] , "key outside an object" )
if frame . seen [ name ] then
error ( "duplicate JSON member: " .. name , 2 )
end
frame . seen [ name ] = true
end

function Output:key(text) 
self : live ( )
self . keyCount += 1
if self . keyCount ~= 1 then
error ( "map key emitted more than one value" , 2 )
end
local frame = assert ( self . frames [ # self . frames ] )
frame . currentName = text
self : claim ( text )
self . sink :__nupp_m_d9930e4662ee507090a52ff19d65f1844d2ce3c0cfdf6a56bcf88945d7356737 ( text )
end

function Output:writeNull(member) 
self : live ( )
self : select ( member )
local description = self : child ( member ) . description
if not description . nullable and description . kind ~= "null" then
error ( "binding does not admit null" , 2 )
end
self : position ( member )
self . sink : null ( )
end

function Output:writeBoolean(member, value) 
self : live ( )
self : select ( member )
if self . keyMode then
self : key ( value and "true" or "false" )
else
self : position ( member )
self . sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( value )
end
end

function Output:writeInteger(member, value) 
self : live ( )
self : select ( member )
numbers . integer ( value . decimal , value . width , value . signed )
local encoded = json . numberToken ( value . decimal )
if self . keyMode then
self : key ( value . decimal )
else
self : position ( member )
self . sink :__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0 ( encoded )
end
end

function Output:writeFloat(member, value, width) 
self : live ( )
self : select ( member )
value = numbers . floating ( value , width )
self : position ( member )
self . sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( value )
end

function Output:writeBigInteger(member, value) 
self : live ( )
self : select ( member )
if not value : match ( "^%-?%d+$" ) then
error ( "expected big integer" , 2 )
end
self : position ( member )
self . sink :__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0 ( json . numberToken ( value ) )
end

function Output:writeDecimal(member, value) 
self : live ( )
self : select ( member )
if not value . coefficient : match ( "^%-?%d+$" ) then
error ( "invalid decimal coefficient" , 2 )
end
if value . exponent < - 2147483648 or value . exponent > 2147483647 then
error ( "decimal exponent is out of range" , 2 )
end
self : position ( member )
self . sink :__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0 ( json . numberToken ( value . coefficient .. "e" .. tostring ( value . exponent ) ) )
end

function Output:writeNumberToken(member, value) 
self : live ( )
self : select ( member )
self : position ( member )
self . sink :__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0 ( json . numberToken ( value ) )
end

function Output:writeString(member, value) 
self : live ( )
self : select ( member )
if self . keyMode then
self : key ( value )
else
self : position ( member )
self . sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( value )
end
end

function Output:writeBytes(member, value) 
self : live ( )
self : select ( member )
self : position ( member )
self . sink :__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71 ( base64 . encode ( value ) )
end

function Output:writeTimestamp(member, value) 
self : live ( )
self : select ( member )
local encoded = self . policy : timestamp ( member , value )
self : position ( member )
self . sink :__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0 ( encoded )
end

function Output:writeAtom(member, value) 
self : live ( )
self : select ( member )
error (
_G.setmetatable({ code =
"unsupported" ,  message =
"JSON atom requires a model conversion" ,  path =
self : path ( ) ,  cause =
nil ,  suppressed =  {} }, errors.Error)
,
0
)
end

function Output:writeDocument(member, value, adapter) 
self : live ( )
self : select ( member )
self : position ( member )
self : enter ( )
local depth = self . budget . depth
local ok , problem = pcall ( writeContents , adapter , value , self . sink , self . factory , self . cache , self . budget )
self . budget . depth = depth - 1
if not ok then
self . closed = true
error ( errors . prefix ( problem , self : path ( ) ) , 0 )
end
end

function Output:child(member) 
self : live ( )
local frame = self . frames [ # self . frames ]
if frame == nil then
return self . root
end

return frame . plan : child ( member ) or frame . plan
end

function Output:aggregate(member, source, emit, kind, expected) 







self : live ( )
self : select ( member )
local plan = self : child ( member )
self : position ( member )
self : enter ( )
if kind == "array" then
self . sink : startArray ( )
else
self . sink : startObject ( )
end
local frame = _G.setmetatable({ kind =  kind ,  plan =  plan ,  count =  0 ,  seen =  { } }, Frame)
self . frames [ # self . frames + 1 ] = frame
emit : apply ( source , self )
if expected ~= nil and frame . count ~= expected then
error ( "wrong aggregate size" , 2 )
end
table . remove ( self . frames )
self . budget . depth -= 1
if kind == "array" then
self . sink : endArray ( )
else
self . sink : endObject ( )
end
end

function Output:writeStruct(member, source, emit) 
self : live ( )
self : aggregate ( member , source , emit , "object" , nil )
end

function Output:writeUnion(member, source, emit) 
self : live ( )
self : aggregate ( member , source , emit , "object" , 1 )
end

function Output:writeList(member, size, source, emit) 
self : live ( )
self : aggregate ( member , source , emit , "array" , size )
end

function Output:writeTuple(member, size, source, emit) 
self : live ( )
self : aggregate ( member , source , emit , "array" , size )
end

function Output:writeMap(member, size, source, emit) 
self : live ( )
self : aggregate ( member , source , emit , "map" , size )
end

function Output:writeEntry(key, keyEmit, value, valueEmit) 






self : live ( )
local frame = self . frames [ # self . frames ]
if frame == nil or frame . kind ~= "map" then
error ( "entry outside map" , 2 )
end
frame . currentName = "<key>"
self . keyMode , self . keyCount = true , 0
keyEmit : apply ( key , self )
self . keyMode = false
assert ( self . keyCount == 1 , "map key did not emit a value" )
local before = frame . count
valueEmit : apply ( value , self )
if frame . count ~= before + 1 then
error ( "map entry must emit one value" , 2 )
end
end

function Output:writeUnknown(field, value, adapter) 





self : live ( )
local frame = self . frames [ # self . frames ]
if frame == nil or frame . kind ~= "object" or self . keyMode then
error ( "unknown field outside object" , 2 )
end
local name = identities . name ( field )
frame . currentName = name
if frame . plan : member ( name ) ~= nil or frame . plan : omitsName ( name ) then
error ( "unknown field collides with a known member" , 2 )
end
local source = adapter : context ( value )
if source ~= nil and source . profile ~= self . factory then
error ( "unknown value cannot be replayed under another profile" , 2 )
end
self : claim ( name )
self . sink :__nupp_m_d9930e4662ee507090a52ff19d65f1844d2ce3c0cfdf6a56bcf88945d7356737 ( name )
frame . count += 1
self : enter ( )
local depth = self . budget . depth
local ok , problem = pcall ( writeContents , adapter , value , self . sink , self . factory , self . cache , self . budget )
self . budget . depth = depth - 1
if not ok then
self . closed = true
error ( errors . prefix ( problem , self : path ( ) ) , 0 )
end
end

function Output:close() 
self . closed = true
end ;_G.nupp.__reflect.link(Output,__nuppT1[3],{ _G.nupp.__reflect.reference("../../../../src/nupp/codec/json/spi.nupp\0Writer\0interface\0module\0001","nupp.codec.json.spi") , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/json/plan.nupp\0PolicyFactory\0interface\0module\0001","nupp.serde.internal.json.plan") , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/json/plan.nupp\0Policy\0interface\0module\0001","nupp.serde.internal.json.plan") , _G.nupp.__reflect.reference("nupp.serde.internal.json.plan\0runtime\0001","nupp.serde.internal.json.plan") , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/json/extensions.nupp\0Scope\0interface\0module\0001","nupp.serde.internal.json.extensions") , __nuppT1[1] , __nuppT1[2] }) ;__nuppExports["Output"]=Output


output=function (
sink ,
factory ,
policy ,
root ,
cache ,
budget
) 
assert ( cache == nil or cache : profile ( ) == factory , "JSON extensions belong to another profile" )
local limits = budget or _G.setmetatable({ maxDepth =  128 ,  maxValues =  1000000 ,  depth =  0 ,  values =  0 }, Budget)
assert ( limits . maxDepth > 0 and limits . maxDepth <= 1024 and limits . maxValues > 0 , "invalid JSON output limits" )
return ( _G.setmetatable({ anchor =
sink ,  sink =
sink ,  factory =
factory ,  policy =
policy ,  root =
root ,  cache =
cache ,  budget =
limits ,  frames =
{ } ,  keyMode =
false ,  keyCount =
0 ,  closed =
false ,  roots =  0 }, Output) )

end ;__nuppExports["output"]=output

local ContentsConsumer = {} ContentsConsumer.__index = ContentsConsumer



function ContentsConsumer:apply(adapter, value, sink) 





local operation = self . cache : resolve ( adapter , "write" )
do local __nuppT48=0; local  __nuppT54 ; local __nuppT55=false ; local __nuppT49,__nuppT50,__nuppT51=__nuppT41(function() do local __nuppT56= output ( sink , self . factory , operation . policy , operation . plan , self . cache , self . budget ) ; __nuppT54= __nuppT56 ; __nuppT48=1;  __nuppT55=true;  local writer=__nuppT54;
writer : emit ( adapter , value )
do (function(__nuppT57,...)  __nuppT55=false; return __nuppT57:close(...)  end)( writer ) end end; return "normal" end,__nuppT37); local __nuppT52={}; local __nuppT53=0; if __nuppT48>=1 and __nuppT55 then  local __nuppT58,__nuppT59=__nuppT40(__nuppCleanup1,__nuppT54);  if not __nuppT58 then __nuppT53=__nuppT53+1; __nuppT52[__nuppT53]=__nuppT59 end; end; if not __nuppT49 then if __nuppT53>0 then __nuppT42(__nuppT38(__nuppT50,__nuppT52,1),0) else __nuppT42(__nuppT50,0) end end; if __nuppT53>0 then if __nuppT53>1 then __nuppT42(__nuppT38(__nuppT52[1],__nuppT52,2),0) else __nuppT42(__nuppT52[1],0) end end; if __nuppT50=="return" then  return __nuppT43(__nuppT51,1,__nuppT51.n)  end; end
end


writeContents = function (
adapter ,
value ,
sink ,
factory ,
cache ,
budget
) 
local consumer = _G.setmetatable({ factory =
factory ,  cache =
cache or extensions . scope ( factory ) ,  budget =
budget }, ContentsConsumer)

adapter : contents ( ) : acceptInto ( consumer , value , sink )
end
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Budget]="nupp.serde.internal.json.writer\0Budget";__nuppWorkerRecords[Output]="nupp.serde.internal.json.writer\0Output"; end);if not __nuppOk then package.loaded["nupp.serde.internal.json.writer"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.writer"]=__nuppExports;return __nuppExports