_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.json.reader"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local input;__nuppExports["input"]=function(...) return input(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.json.reader\0runtime\0001") };

local core = require ( "nupp.serde.internal.value" )
local publication = require ( "nupp.serde.internal.publication" )
local errors = require ( "nupp.serde.internal.errors" )
local plans = require ( "nupp.serde.internal.json.plan" )
local syntax = require ( "nupp.serde.internal.json.syntax" )
local documents = require ( "nupp.serde.internal.json.document" )
local numbers = require ( "nupp.serde.internal.numbers" )
local base64 = require ( "nupp.codec.base64" )
local json = require ( "nupp.codec.json" )

local Input = {} Input.__index = Input








function Input:expire() 
self . expired = true
end

function Input:live() 
if self . expired then
error ( "value reader scope has expired" , 2 )
end
end

function Input:context() 
self : live ( )
return self . sourceContext
end

function Input:isNull() 
self : live ( )
return self . mapKey == nil and self . cursor : peek ( ) == "null"
end

function Input:key() 
self : live ( )
local key = self . mapKey
if key ~= nil then
if self . usedKey then
error ( "map key has already been consumed" , 2 )
end
self . usedKey = true
end

return key
end

function Input:readNull(member) 
self : live ( )
if not self . plan . description . nullable and self . plan . description . kind ~= "null" then
error ( "binding does not admit null" , 2 )
end
if self . mapKey ~= nil then
error ( "JSON map key cannot be null" , 2 )
end
self . cursor : readNull ( )
end

function Input:readBoolean(member) 
local key = self : key ( )
if key ~= nil then
if key == "true" then
return true
elseif key == "false" then
return false
end
error ( "JSON map key is not a boolean" , 2 )
end

return self . cursor : readBoolean ( )
end

function Input:readInteger(member, width, signed) 
local key = self : key ( )
return numbers . integer ( key or self . cursor : readNumber ( ) , width , signed )
end

function Input:readFloat(member, width) 
self : live ( )
if self . mapKey ~= nil then
error ( "JSON map key cannot be a float" , 2 )
end
local value = tonumber ( self . cursor : readNumber ( ) )
if value == nil then
error ( "invalid float" , 2 )
end

return numbers . floating ( value , width )
end

function Input:readBigInteger(member) 
self : live ( )
local value = self . cursor : readNumber ( )
if not value : match ( "^%-?%d+$" ) then
error ( "expected big integer" , 2 )
end

return value
end

function Input:readDecimal(member) 
self : live ( )
local token = self . cursor : readNumber ( )
local mantissa , exponent = token : match ( "^(.-)[eE]([+-]?%d+)$" )
if mantissa == nil then
mantissa , exponent = token , "0"
end
local whole , fraction = mantissa : match ( "^(.-)%.(%d+)$" )
local parsed = tonumber ( exponent )
if parsed == nil or parsed < - 2147483648 or parsed > 2147483647 then
error ( "decimal exponent is out of range" , 2 )
end
local scale = parsed
if whole ~= nil and scale - # fraction < - 2147483648 then
error ( "decimal exponent is out of range" , 2 )
end
if whole ~= nil then
local coefficient = whole .. fraction
local negative = coefficient : sub ( 1 , 1 ) == "-"
local digits = negative and coefficient : sub ( 2 ) or coefficient
digits = digits : gsub ( "^0+" , "" )
if digits == "" then
digits = "0"
end
return ( _G.setmetatable({ coefficient =  ( negative and "-" or "" ) .. digits ,  exponent =  scale - # fraction }, core.Decimal) )
end

return ( _G.setmetatable({ coefficient =  mantissa ,  exponent =  scale }, core.Decimal) )
end

function Input:readNumberToken(member) 
self : live ( )
return self . cursor : readNumber ( )
end

function Input:readString(member) 
local key = self : key ( )
return key or self . cursor : readString ( )
end

function Input:readBytes(member) 
self : live ( )
local value , problem = base64 . decode ( self . cursor : readString ( ) )
if value == nil then
error ( problem , 2 )
end

return value
end

function Input:readTimestamp(member) 
self : live ( )
local kind = self . cursor : peek ( )
if kind == "string" then
return self . policy : parseTimestamp ( member , self . cursor : readString ( ) , "string" )
elseif kind == "number" then
return self . policy : parseTimestamp ( member , self . cursor : readNumber ( ) , "number" )
else
error ( "expected a timestamp" , 2 )
end
end

function Input:readAtom(member) 
self : live ( )
error ( "JSON atom requires a model conversion" , 2 )
end

function Input:readDocument(member, adapter) 
self : live ( )
local mark = self . cursor : mark ( )
local reader = documents . contents ( self . cursor , self . sourceContext )
local ok , result = pcall ( adapter . readContents , adapter , reader )
reader : expire ( )
if not ok then
error ( result , 0 )
end
local complete , problem = pcall ( self . cursor . consumed , self . cursor , mark )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return result
end

function Input:child(member) 
return ( _G.setmetatable({ cursor =
self . cursor ,  policy =
self . policy ,  plan =
self . plan : child ( member ) or self . plan ,  sourceContext =
self . sourceContext ,  mapKey =
nil ,  usedKey =
false ,  expired =
false }, Input) )

end

function Input:object(member, state, consume, unknown, union) 







self : live ( )
self . cursor : start ( "object" )
local count = 0
while true do
local name = self . cursor : nextKey ( )
if name == nil then
do break end
end
count += 1
local field = self . plan : member ( name )
local mark = self . cursor : mark ( )
if field ~= nil and self . plan : action ( field ) == "traverse" then
self . cursor : selectMember ( field . name )
local reader = self : child ( field )
local ok , problem = pcall ( consume . apply , consume , state , field , reader )
reader . expired = true
if not ok then
error ( errors . wrap ( problem , self . cursor : path ( ) , self . cursor : offset ( ) ) , 0 )
end
elseif field ~= nil or self . plan : omitsName ( name ) then
self . cursor : skipValue ( )
else
local reader = documents . unknown ( self . cursor , self . sourceContext )
local identity = _G.setmetatable({ name =  name }, documents.Name)
local ok , problem = pcall ( unknown . apply , unknown , state , identity , reader )
reader : expire ( )
if not ok then
error ( errors . wrap ( problem , self . cursor : path ( ) , self . cursor : offset ( ) ) , 0 )
end
end
self . cursor : consumed ( mark )
end
if union and count ~= 1 then
error ( "union requires exactly one alternative" , 2 )
end
end

function Input:readStruct(member, state, consume, unknown) 






self : object ( member , state , consume , unknown , false )
end

function Input:readUnion(member, state, consume, unknown) 






self : object ( member , state , consume , unknown , true )
end

function Input:array(member, state, consume, size) 






self : live ( )
self . cursor : start ( "array" )
local index = 0
while self . cursor : nextElement ( ) do
index += 1
local mark = self . cursor : mark ( )
local reader = _G.setmetatable({ cursor =
self . cursor ,  policy =
self . policy ,  plan =
self . plan : slot ( size ~= nil and index or 1 ) or self . plan ,  sourceContext =
self . sourceContext ,  mapKey =
nil ,  usedKey =
false ,  expired =
false }, Input)

local ok , problem = pcall ( consume . apply , consume , state , index , reader )
reader . expired = true
if not ok then
error ( errors . wrap ( problem , self . cursor : path ( ) , self . cursor : offset ( ) ) , 0 )
end
self . cursor : consumed ( mark )
end
if size ~= nil and index ~= size then
error ( "wrong tuple size" , 2 )
end
end

function Input:readList(member, state, consume) 
self : array ( member , state , consume , nil )
end

function Input:readTuple(member, size, state, consume) 






self : array ( member , state , consume , size )
end

function Input:readMap(member, state, consume) 
self : live ( )
self . cursor : start ( "object" )
while true do
local name = self . cursor : nextKey ( )
if name == nil then
do break end
end
local mark = self . cursor : mark ( )
local reader = _G.setmetatable({ cursor =
self . cursor ,  policy =
self . policy ,  plan =
self . plan : slot ( 2 ) or self . plan ,  sourceContext =
self . sourceContext ,  mapKey =
nil ,  usedKey =
false ,  expired =
false }, Input)

local key = _G.setmetatable({ cursor =
syntax . reader ( json . encode ( name ) ) ,  policy =
self . policy ,  plan =
self . plan : slot ( 1 ) or self . plan ,  sourceContext =
self . sourceContext ,  mapKey =
name ,  usedKey =
false ,  expired =
false }, Input)

local ok , problem = pcall ( consume . apply , consume , state , key , reader )
reader . expired , key . expired = true , true
if not ok then
error ( errors . wrap ( problem , self . cursor : path ( ) , self . cursor : offset ( ) ) , 0 )
end
if not key . usedKey then
error ( "map key was not consumed" , 2 )
end
self . cursor : consumed ( mark )
end
end

function Input:containerSize() 
self : live ( )
return nil
end ;_G.nupp.__reflect.link(Input,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.serde.internal.json.syntax\0runtime\0004","nupp.serde.internal.json.syntax") , _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/json/plan.nupp\0Policy\0interface\0module\0001","nupp.serde.internal.json.plan") , _G.nupp.__reflect.reference("nupp.serde.internal.json.plan\0runtime\0001","nupp.serde.internal.json.plan") , _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") }) ;__nuppExports["Input"]=Input


input=function (
cursor ,
policy ,
plan ,
context
) 
return ( _G.setmetatable({ cursor =
cursor ,  policy =
policy ,  plan =
plan ,  sourceContext =
context ,  mapKey =
nil ,  usedKey =
false ,  expired =
false }, Input) )

end ;__nuppExports["input"]=input
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Input]="nupp.serde.internal.json.reader\0Input"; end);if not __nuppOk then package.loaded["nupp.serde.internal.json.reader"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.reader"]=__nuppExports;return __nuppExports