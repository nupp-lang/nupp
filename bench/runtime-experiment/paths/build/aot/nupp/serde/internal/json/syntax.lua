_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.json.syntax"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local reader;__nuppExports["reader"]=function(...) return reader(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.json.syntax\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.syntax\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.syntax\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.syntax\0runtime\0004") };

local json = require ( "nupp.codec.json" )
local errors = require ( "nupp.serde.internal.errors" )



local Limits = {} Limits.__index = Limits ;_G.nupp.__reflect.link(Limits,__nuppT1[1],{ }) ;__nuppExports["Limits"]=Limits





local Frame = {} Frame.__index = Frame ;_G.nupp.__reflect.link(Frame,__nuppT1[2],{ })








local Mark = {} Mark.__index = Mark ;_G.nupp.__reflect.link(Mark,__nuppT1[3],{ }) ;__nuppExports["Mark"]=Mark




local Cursor = {} Cursor.__index = Cursor










function Cursor:path() 
local parts = { "$" }
for _ , frame in ipairs ( self . frames ) do
if frame . kind == "object" and frame . currentName ~= nil then
parts [ # parts + 1 ] = "[" .. json . encode ( frame . logicalName or frame . currentName ) .. "]"
elseif frame . kind == "array" and frame . phase ~= "first" then
local index = frame . phase == "after" and frame . count or frame . count + 1
parts [ # parts + 1 ] = "[" .. tostring ( index ) .. "]"
end
end

return table . concat ( parts )
end

function Cursor:selectMember(name) 
local frame = assert ( self . frames [ # self . frames ] , "member outside object" )
assert ( frame . kind == "object" , "member outside object" )
frame . logicalName = name
end

function Cursor:offset() 
return self . position
end

function Cursor:fail(message, code) 
error (
_G.setmetatable({ code =
code or "syntax" ,  message =
message ,  path =
self : path ( ) ,  byte =
self . position ,  cause =
nil ,  suppressed =  {} }, errors.Error)
,
0
)
end

function Cursor:space() 
if self . closed then
self : fail ( "reader is closed" )
end
local position = self . position
while position <= # self . input do
local byte = self . input : byte ( position )
if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then
do break end
end
position += 1
end
self . position = position
end

function Cursor:peek() 
self : space ( )
local byte = self . input : byte ( self . position )
if byte == 110 then
return "null"
elseif byte == 116 or byte == 102 then
return "boolean"
elseif byte == 34 then
return "string"
elseif byte == 123 then
return "object"
elseif byte == 91 then
return "array"
elseif byte == 45 or ( byte ~= nil and byte >= 48 and byte <= 57 ) then
return "number"
end
self : fail ( "expected a value" )
end

function Cursor:beginValue() 
self : space ( )
local frame = self . frames [ # self . frames ]
if frame ~= nil then
assert ( frame . phase == "value" , "JSON value is not expected here" )
elseif self . roots ~= 0 then
self : fail ( "more than one root value" )
end
self . tokens += 1
if self . tokens > self . maxTokens then
self : fail ( "token limit exceeded" , "limit" )
end
end

function Cursor:finishValue() 
local frame = self . frames [ # self . frames ]
if frame == nil then
self . roots += 1



self : space ( )
if self . position <= # self . input then
self : fail ( "trailing input" )
end
else
frame . phase = "after"
frame . count += 1
end
end

function Cursor:endScalar() 
local byte = self . input : byte ( self . position )
if byte ~= nil
and byte ~= 32
and byte ~= 9
and byte ~= 10
and byte ~= 13
and byte ~= 44
and byte ~= 93
and byte ~= 125
then
self : fail ( "invalid value boundary" )
end
self : finishValue ( )
end

function Cursor:literal(text) 
self : beginValue ( )
if # text > self . limits . tokenBytes then
self : fail ( "literal token limit exceeded" , "limit" )
end
if self . input : sub ( self . position , self . position + # text - 1 ) ~= text then
self : fail ( "expected " .. text )
end
self . position += # text
self : endScalar ( )
end

function Cursor:readNull() 
self : literal ( "null" )
end

function Cursor:readBoolean() 
self : space ( )
if self . input : sub ( self . position , self . position ) == "t" then
self : literal ( "true" )
return true
end
self : literal ( "false" )

return false
end

function Cursor:stringToken() 
self : space ( )
local start = self . position
if self . input : byte ( start ) ~= 34 then
self : fail ( "expected string" )
end
local position = start + 1
while position <= # self . input do
if position - start + 1 > self . limits . tokenBytes then
self : fail ( "string token limit exceeded" , "limit" )
end
local byte = self . input : byte ( position )
if byte == 34 then
local value , message = json . decode ( self . input : sub ( start , position ) )
if type ( value ) ~= "string" then
self : fail ( message or "invalid string" )
end
self . position = position + 1
return value
elseif byte == 92 then
position += 1
end
position += 1
end
self : fail ( "unterminated string" )
end

function Cursor:readString() 
self : beginValue ( )
local result = self : stringToken ( )
self : endScalar ( )
return result
end

function Cursor:readNumber() 
self : beginValue ( )
local start = self . position
local position = start
local input = self . input
if input : byte ( position ) == 45 then
position += 1
end
local byte = input : byte ( position )
if byte == 48 then
position += 1
elseif byte ~= nil and byte >= 49 and byte <= 57 then
repeat
position += 1
byte = input : byte ( position )
until byte == nil or byte < 48 or byte > 57
else
self : fail ( "expected integer part" )
end
if input : byte ( position ) == 46 then
position += 1
local first = position
byte = input : byte ( position )
while byte ~= nil and byte >= 48 and byte <= 57 do
position += 1
byte = input : byte ( position )
end
if position == first then
self : fail ( "expected fraction digits" )
end
end
byte = input : byte ( position )
if byte == 69 or byte == 101 then
position += 1
byte = input : byte ( position )
if byte == 43 or byte == 45 then
position += 1
end
local first = position
byte = input : byte ( position )
while byte ~= nil and byte >= 48 and byte <= 57 do
position += 1
byte = input : byte ( position )
end
if position == first then
self : fail ( "expected exponent digits" )
end
end
if position - start > self . limits . tokenBytes then
self : fail ( "number token limit exceeded" , "limit" )
end
self . position = position
self : endScalar ( )

return input : sub ( start , position - 1 )
end

function Cursor:start(kind) 
self : beginValue ( )
local expected = kind == "object" and 123 or 91
if self . input : byte ( self . position ) ~= expected then
self : fail ( "expected " .. kind )
end
if # self . frames >= self . maxDepth then
self : fail ( "nesting limit exceeded" , "limit" )
end
self . position += 1
self . frames [ # self . frames + 1 ] = _G.setmetatable({ kind =  kind ,  phase =  "first" ,  names =  { } ,  count =  0 }, Frame)
end

function Cursor:next(kind) 
self : space ( )
local frame = self . frames [ # self . frames ]
if frame == nil or frame . kind ~= kind then
self : fail ( "wrong container" )
end
assert ( frame . phase ~= "value" , "previous JSON value was not consumed" )
frame . currentName , frame . logicalName = nil , nil
local close = kind == "object" and 125 or 93
if self . input : byte ( self . position ) == close then
self . position += 1
table . remove ( self . frames )
self : finishValue ( )
return false
end
if frame . phase == "after" then
if self . input : byte ( self . position ) ~= 44 then
self : fail ( "expected comma or container end" )
end
self . position += 1
self : space ( )
frame . phase = "value"
if self . input : byte ( self . position ) == close then
self : fail ( "trailing comma" )
end
end
if frame . count >= self . limits . aggregateEntries then
self : fail ( "aggregate entry limit exceeded" , "limit" )
end
frame . currentName = nil
frame . logicalName = nil
frame . phase = "value"

return true
end

function Cursor:nextKey() 
if not self : next ( "object" ) then
return nil
end
local name = self : stringToken ( )
local frame = self . frames [ # self . frames ]
frame . currentName = name
if frame . names [ name ] then
self : fail ( "duplicate member " .. name )
end
frame . names [ name ] = true
self : space ( )
if self . input : byte ( self . position ) ~= 58 then
self : fail ( "expected colon" )
end
self . position += 1

return name
end

function Cursor:nextElement() 
return self : next ( "array" )
end

function Cursor:skipValue() 
local token = self : peek ( )
if token == "null" then
self : readNull ( )
elseif token == "boolean" then
self : readBoolean ( )
elseif token == "number" then
self : readNumber ( )
elseif token == "string" then
self : readString ( )
elseif token == "object" then
self : start ( "object" )
while self : nextKey ( ) ~= nil do
self : skipValue ( )
end
else
self : start ( "array" )
while self : nextElement ( ) do
self : skipValue ( )
end
end
end

function Cursor:mark() 
local frame = self . frames [ # self . frames ]
return ( _G.setmetatable({ depth =  # self . frames ,  count =  frame ~= nil and frame . count or self . roots }, Mark) )
end

function Cursor:consumed(mark) 
local frame = self . frames [ # self . frames ]
local count = frame ~= nil and frame . count or self . roots
if # self . frames ~= mark . depth or count ~= mark . count + 1 or ( frame ~= nil and frame . phase ~= "after" ) then
self : fail ( "callback must consume exactly one value" )
end
end

function Cursor:finish() 
self : space ( )
if # self . frames ~= 0 or self . roots ~= 1 then
self : fail ( "incomplete root value" )
end
if self . position <= # self . input then
self : fail ( "trailing input" )
end
self . closed = true
end ;_G.nupp.__reflect.link(Cursor,__nuppT1[4],{ __nuppT1[2] , __nuppT1[1] }) ;__nuppExports["Cursor"]=Cursor


reader=function ( input , maxDepth , maxTokens , limits ) 
local depth , tokens = maxDepth or 128 , maxTokens or 1000000
local bounds = limits or _G.setmetatable({ tokenBytes =  16777216 ,  aggregateEntries =  1000000 ,  inputBytes =  67108864 }, Limits)
assert (
bounds . tokenBytes >= 1 and bounds . aggregateEntries >= 1 and bounds . inputBytes >= 1 ,
"JSON limits must be positive"
)
if # input > bounds . inputBytes then
error (
_G.setmetatable({ code =  "limit" ,  message =  "input byte limit exceeded" ,  path =  "$" ,  byte =  1 ,  cause =  nil ,  suppressed =  {} }, errors.Error) ,
0
)
end
if depth < 1 or depth > 1024 or tokens < 1 then
error ( "JSON limits require depth 1..1024 and a positive token budget" , 2 )
end

return ( _G.setmetatable({ input =
input ,  position =
1 ,  frames =
{ } ,  roots =
0 ,  tokens =
0 ,  maxDepth =
depth ,  maxTokens =
tokens ,  limits =
bounds ,  closed =
false }, Cursor) )

end ;__nuppExports["reader"]=reader
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Cursor]="nupp.serde.internal.json.syntax\0Cursor";__nuppWorkerRecords[Limits]="nupp.serde.internal.json.syntax\0Limits";__nuppWorkerRecords[Mark]="nupp.serde.internal.json.syntax\0Mark"; end);if not __nuppOk then package.loaded["nupp.serde.internal.json.syntax"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.syntax"]=__nuppExports;return __nuppExports